/// 6502 CPU フラグレジスタのビット定義
pub mod flags {
    pub const C: u8 = 0x01; // Carry
    pub const Z: u8 = 0x02; // Zero
    pub const I: u8 = 0x04; // Interrupt Disable
    pub const D: u8 = 0x08; // Decimal Mode (NES では未使用)
    pub const B: u8 = 0x10; // Break Command
    pub const U: u8 = 0x20; // Unused (常に 1)
    pub const V: u8 = 0x40; // Overflow
    pub const N: u8 = 0x80; // Negative
}

/// CPU が Bus にアクセスするためのトレイト
pub trait Memory {
    fn read(&mut self, addr: u16) -> u8;
    fn write(&mut self, addr: u16, val: u8);

    fn read16(&mut self, addr: u16) -> u16 {
        let lo = self.read(addr) as u16;
        let hi = self.read(addr.wrapping_add(1)) as u16;
        (hi << 8) | lo
    }

    /// ゼロページラップアラウンドする 16bit 読み取り
    fn read16_zp_wrap(&mut self, addr: u8) -> u16 {
        let lo = self.read(addr as u16) as u16;
        let hi = self.read(addr.wrapping_add(1) as u16) as u16;
        (hi << 8) | lo
    }

    /// ページをまたがないバグ付き 16bit 読み取り（Indirect 命令用）
    fn read16_page_bug(&mut self, addr: u16) -> u16 {
        let lo = self.read(addr) as u16;
        let hi_addr = (addr & 0xFF00) | ((addr.wrapping_add(1)) & 0x00FF);
        let hi = self.read(hi_addr) as u16;
        (hi << 8) | lo
    }
}

/// 6502 CPU
pub struct Cpu {
    pub a: u8,   // アキュムレータ
    pub x: u8,   // X インデックスレジスタ
    pub y: u8,   // Y インデックスレジスタ
    pub sp: u8,  // スタックポインタ
    pub pc: u16, // プログラムカウンタ
    pub p: u8,   // ステータスレジスタ (flags)

    pub cycles: u64, // 累計サイクル数
    pub stall: u32,  // DMA 等で停止するサイクル数
}

impl Cpu {
    pub fn new() -> Self {
        Self {
            a: 0,
            x: 0,
            y: 0,
            sp: 0xFD,
            pc: 0,
            p: flags::U | flags::I,
            cycles: 0,
            stall: 0,
        }
    }

    /// RESET 割り込みを実行する
    pub fn reset<M: Memory>(&mut self, mem: &mut M) {
        self.a = 0;
        self.x = 0;
        self.y = 0;
        self.sp = 0xFD;
        self.p = flags::U | flags::I;
        self.pc = mem.read16(0xFFFC);
        self.cycles = 7; // RESET は 7 サイクル
    }

    /// NMI 割り込みを実行する
    pub fn nmi<M: Memory>(&mut self, mem: &mut M) {
        self.push16(mem, self.pc);
        let p = (self.p | flags::U) & !flags::B;
        self.push(mem, p);
        self.p |= flags::I;
        self.pc = mem.read16(0xFFFA);
        self.cycles += 7;
    }

    /// IRQ 割り込みを実行する（I フラグが 0 の場合のみ）
    pub fn irq<M: Memory>(&mut self, mem: &mut M) {
        if self.p & flags::I == 0 {
            self.push16(mem, self.pc);
            let p = (self.p | flags::U) & !flags::B;
            self.push(mem, p);
            self.p |= flags::I;
            self.pc = mem.read16(0xFFFE);
            self.cycles += 7;
        }
    }

    /// 1 命令を実行し、消費サイクル数を返す
    pub fn step<M: Memory>(&mut self, mem: &mut M) -> u32 {
        if self.stall > 0 {
            self.stall -= 1;
            self.cycles += 1;
            return 1;
        }

        let opcode = self.fetch(mem);
        let cycles = self.execute(opcode, mem);
        self.cycles += cycles as u64;
        cycles
    }

    fn fetch<M: Memory>(&mut self, mem: &mut M) -> u8 {
        let op = mem.read(self.pc);
        self.pc = self.pc.wrapping_add(1);
        op
    }

    fn fetch16<M: Memory>(&mut self, mem: &mut M) -> u16 {
        let lo = self.fetch(mem) as u16;
        let hi = self.fetch(mem) as u16;
        (hi << 8) | lo
    }

    // ---- スタック操作 ----

    fn push<M: Memory>(&mut self, mem: &mut M, val: u8) {
        mem.write(0x0100 | self.sp as u16, val);
        self.sp = self.sp.wrapping_sub(1);
    }

    fn pop<M: Memory>(&mut self, mem: &mut M) -> u8 {
        self.sp = self.sp.wrapping_add(1);
        mem.read(0x0100 | self.sp as u16)
    }

    fn push16<M: Memory>(&mut self, mem: &mut M, val: u16) {
        self.push(mem, (val >> 8) as u8);
        self.push(mem, val as u8);
    }

    fn pop16<M: Memory>(&mut self, mem: &mut M) -> u16 {
        let lo = self.pop(mem) as u16;
        let hi = self.pop(mem) as u16;
        (hi << 8) | lo
    }

    // ---- フラグ操作 ----

    fn set_flag(&mut self, flag: u8, val: bool) {
        if val {
            self.p |= flag;
        } else {
            self.p &= !flag;
        }
    }

    fn flag(&self, flag: u8) -> bool {
        self.p & flag != 0
    }

    fn set_zn(&mut self, val: u8) {
        self.set_flag(flags::Z, val == 0);
        self.set_flag(flags::N, val & 0x80 != 0);
    }

    // ---- アドレッシングモード ----

    fn addr_immediate<M: Memory>(&mut self, _mem: &mut M) -> u16 {
        let addr = self.pc;
        self.pc = self.pc.wrapping_add(1);
        addr
    }

    fn addr_zeropage<M: Memory>(&mut self, mem: &mut M) -> u16 {
        self.fetch(mem) as u16
    }

    fn addr_zeropage_x<M: Memory>(&mut self, mem: &mut M) -> u16 {
        let base = self.fetch(mem);
        base.wrapping_add(self.x) as u16
    }

    fn addr_zeropage_y<M: Memory>(&mut self, mem: &mut M) -> u16 {
        let base = self.fetch(mem);
        base.wrapping_add(self.y) as u16
    }

    fn addr_absolute<M: Memory>(&mut self, mem: &mut M) -> u16 {
        self.fetch16(mem)
    }

    fn addr_absolute_x<M: Memory>(&mut self, mem: &mut M) -> (u16, bool) {
        let base = self.fetch16(mem);
        let addr = base.wrapping_add(self.x as u16);
        let page_crossed = (base & 0xFF00) != (addr & 0xFF00);
        (addr, page_crossed)
    }

    fn addr_absolute_y<M: Memory>(&mut self, mem: &mut M) -> (u16, bool) {
        let base = self.fetch16(mem);
        let addr = base.wrapping_add(self.y as u16);
        let page_crossed = (base & 0xFF00) != (addr & 0xFF00);
        (addr, page_crossed)
    }

    fn addr_indirect<M: Memory>(&mut self, mem: &mut M) -> u16 {
        let ptr = self.fetch16(mem);
        mem.read16_page_bug(ptr)
    }

    fn addr_indirect_x<M: Memory>(&mut self, mem: &mut M) -> u16 {
        let base = self.fetch(mem);
        let ptr = base.wrapping_add(self.x);
        mem.read16_zp_wrap(ptr)
    }

    fn addr_indirect_y<M: Memory>(&mut self, mem: &mut M) -> (u16, bool) {
        let ptr = self.fetch(mem);
        let base = mem.read16_zp_wrap(ptr);
        let addr = base.wrapping_add(self.y as u16);
        let page_crossed = (base & 0xFF00) != (addr & 0xFF00);
        (addr, page_crossed)
    }

    fn branch<M: Memory>(&mut self, mem: &mut M, cond: bool) -> u32 {
        let offset = self.fetch(mem) as i8;
        if cond {
            let old_pc = self.pc;
            self.pc = self.pc.wrapping_add(offset as u16);
            let page_crossed = (old_pc & 0xFF00) != (self.pc & 0xFF00);
            if page_crossed { 4 } else { 3 }
        } else {
            2
        }
    }

    /// 命令を実行し消費サイクル数を返す
    #[allow(clippy::too_many_lines)]
    fn execute<M: Memory>(&mut self, opcode: u8, mem: &mut M) -> u32 {
        match opcode {
            // ---- LDA ----
            0xA9 => { let addr = self.addr_immediate(mem); self.a = mem.read(addr); self.set_zn(self.a); 2 }
            0xA5 => { let addr = self.addr_zeropage(mem); self.a = mem.read(addr); self.set_zn(self.a); 3 }
            0xB5 => { let addr = self.addr_zeropage_x(mem); self.a = mem.read(addr); self.set_zn(self.a); 4 }
            0xAD => { let addr = self.addr_absolute(mem); self.a = mem.read(addr); self.set_zn(self.a); 4 }
            0xBD => { let (addr, p) = self.addr_absolute_x(mem); self.a = mem.read(addr); self.set_zn(self.a); if p { 5 } else { 4 } }
            0xB9 => { let (addr, p) = self.addr_absolute_y(mem); self.a = mem.read(addr); self.set_zn(self.a); if p { 5 } else { 4 } }
            0xA1 => { let addr = self.addr_indirect_x(mem); self.a = mem.read(addr); self.set_zn(self.a); 6 }
            0xB1 => { let (addr, p) = self.addr_indirect_y(mem); self.a = mem.read(addr); self.set_zn(self.a); if p { 6 } else { 5 } }

            // ---- LDX ----
            0xA2 => { let addr = self.addr_immediate(mem); self.x = mem.read(addr); self.set_zn(self.x); 2 }
            0xA6 => { let addr = self.addr_zeropage(mem); self.x = mem.read(addr); self.set_zn(self.x); 3 }
            0xB6 => { let addr = self.addr_zeropage_y(mem); self.x = mem.read(addr); self.set_zn(self.x); 4 }
            0xAE => { let addr = self.addr_absolute(mem); self.x = mem.read(addr); self.set_zn(self.x); 4 }
            0xBE => { let (addr, p) = self.addr_absolute_y(mem); self.x = mem.read(addr); self.set_zn(self.x); if p { 5 } else { 4 } }

            // ---- LDY ----
            0xA0 => { let addr = self.addr_immediate(mem); self.y = mem.read(addr); self.set_zn(self.y); 2 }
            0xA4 => { let addr = self.addr_zeropage(mem); self.y = mem.read(addr); self.set_zn(self.y); 3 }
            0xB4 => { let addr = self.addr_zeropage_x(mem); self.y = mem.read(addr); self.set_zn(self.y); 4 }
            0xAC => { let addr = self.addr_absolute(mem); self.y = mem.read(addr); self.set_zn(self.y); 4 }
            0xBC => { let (addr, p) = self.addr_absolute_x(mem); self.y = mem.read(addr); self.set_zn(self.y); if p { 5 } else { 4 } }

            // ---- STA ----
            0x85 => { let addr = self.addr_zeropage(mem); mem.write(addr, self.a); 3 }
            0x95 => { let addr = self.addr_zeropage_x(mem); mem.write(addr, self.a); 4 }
            0x8D => { let addr = self.addr_absolute(mem); mem.write(addr, self.a); 4 }
            0x9D => { let (addr, _) = self.addr_absolute_x(mem); mem.write(addr, self.a); 5 }
            0x99 => { let (addr, _) = self.addr_absolute_y(mem); mem.write(addr, self.a); 5 }
            0x81 => { let addr = self.addr_indirect_x(mem); mem.write(addr, self.a); 6 }
            0x91 => { let (addr, _) = self.addr_indirect_y(mem); mem.write(addr, self.a); 6 }

            // ---- STX ----
            0x86 => { let addr = self.addr_zeropage(mem); mem.write(addr, self.x); 3 }
            0x96 => { let addr = self.addr_zeropage_y(mem); mem.write(addr, self.x); 4 }
            0x8E => { let addr = self.addr_absolute(mem); mem.write(addr, self.x); 4 }

            // ---- STY ----
            0x84 => { let addr = self.addr_zeropage(mem); mem.write(addr, self.y); 3 }
            0x94 => { let addr = self.addr_zeropage_x(mem); mem.write(addr, self.y); 4 }
            0x8C => { let addr = self.addr_absolute(mem); mem.write(addr, self.y); 4 }

            // ---- Transfer ----
            0xAA => { self.x = self.a; self.set_zn(self.x); 2 } // TAX
            0x8A => { self.a = self.x; self.set_zn(self.a); 2 } // TXA
            0xA8 => { self.y = self.a; self.set_zn(self.y); 2 } // TAY
            0x98 => { self.a = self.y; self.set_zn(self.a); 2 } // TYA
            0xBA => { self.x = self.sp; self.set_zn(self.x); 2 } // TSX
            0x9A => { self.sp = self.x; 2 }                      // TXS

            // ---- Stack ----
            0x48 => { self.push(mem, self.a); 3 }                // PHA
            0x08 => { self.push(mem, self.p | flags::B | flags::U); 3 } // PHP
            0x68 => { self.a = self.pop(mem); self.set_zn(self.a); 4 } // PLA
            0x28 => { self.p = (self.pop(mem) | flags::U) & !flags::B; 4 } // PLP

            // ---- AND ----
            0x29 => { let addr = self.addr_immediate(mem); self.a &= mem.read(addr); self.set_zn(self.a); 2 }
            0x25 => { let addr = self.addr_zeropage(mem); self.a &= mem.read(addr); self.set_zn(self.a); 3 }
            0x35 => { let addr = self.addr_zeropage_x(mem); self.a &= mem.read(addr); self.set_zn(self.a); 4 }
            0x2D => { let addr = self.addr_absolute(mem); self.a &= mem.read(addr); self.set_zn(self.a); 4 }
            0x3D => { let (addr, p) = self.addr_absolute_x(mem); self.a &= mem.read(addr); self.set_zn(self.a); if p { 5 } else { 4 } }
            0x39 => { let (addr, p) = self.addr_absolute_y(mem); self.a &= mem.read(addr); self.set_zn(self.a); if p { 5 } else { 4 } }
            0x21 => { let addr = self.addr_indirect_x(mem); self.a &= mem.read(addr); self.set_zn(self.a); 6 }
            0x31 => { let (addr, p) = self.addr_indirect_y(mem); self.a &= mem.read(addr); self.set_zn(self.a); if p { 6 } else { 5 } }

            // ---- EOR ----
            0x49 => { let addr = self.addr_immediate(mem); self.a ^= mem.read(addr); self.set_zn(self.a); 2 }
            0x45 => { let addr = self.addr_zeropage(mem); self.a ^= mem.read(addr); self.set_zn(self.a); 3 }
            0x55 => { let addr = self.addr_zeropage_x(mem); self.a ^= mem.read(addr); self.set_zn(self.a); 4 }
            0x4D => { let addr = self.addr_absolute(mem); self.a ^= mem.read(addr); self.set_zn(self.a); 4 }
            0x5D => { let (addr, p) = self.addr_absolute_x(mem); self.a ^= mem.read(addr); self.set_zn(self.a); if p { 5 } else { 4 } }
            0x59 => { let (addr, p) = self.addr_absolute_y(mem); self.a ^= mem.read(addr); self.set_zn(self.a); if p { 5 } else { 4 } }
            0x41 => { let addr = self.addr_indirect_x(mem); self.a ^= mem.read(addr); self.set_zn(self.a); 6 }
            0x51 => { let (addr, p) = self.addr_indirect_y(mem); self.a ^= mem.read(addr); self.set_zn(self.a); if p { 6 } else { 5 } }

            // ---- ORA ----
            0x09 => { let addr = self.addr_immediate(mem); self.a |= mem.read(addr); self.set_zn(self.a); 2 }
            0x05 => { let addr = self.addr_zeropage(mem); self.a |= mem.read(addr); self.set_zn(self.a); 3 }
            0x15 => { let addr = self.addr_zeropage_x(mem); self.a |= mem.read(addr); self.set_zn(self.a); 4 }
            0x0D => { let addr = self.addr_absolute(mem); self.a |= mem.read(addr); self.set_zn(self.a); 4 }
            0x1D => { let (addr, p) = self.addr_absolute_x(mem); self.a |= mem.read(addr); self.set_zn(self.a); if p { 5 } else { 4 } }
            0x19 => { let (addr, p) = self.addr_absolute_y(mem); self.a |= mem.read(addr); self.set_zn(self.a); if p { 5 } else { 4 } }
            0x01 => { let addr = self.addr_indirect_x(mem); self.a |= mem.read(addr); self.set_zn(self.a); 6 }
            0x11 => { let (addr, p) = self.addr_indirect_y(mem); self.a |= mem.read(addr); self.set_zn(self.a); if p { 6 } else { 5 } }

            // ---- BIT ----
            0x24 => {
                let addr = self.addr_zeropage(mem);
                let val = mem.read(addr);
                self.set_flag(flags::Z, self.a & val == 0);
                self.set_flag(flags::V, val & 0x40 != 0);
                self.set_flag(flags::N, val & 0x80 != 0);
                3
            }
            0x2C => {
                let addr = self.addr_absolute(mem);
                let val = mem.read(addr);
                self.set_flag(flags::Z, self.a & val == 0);
                self.set_flag(flags::V, val & 0x40 != 0);
                self.set_flag(flags::N, val & 0x80 != 0);
                4
            }

            // ---- ADC ----
            0x69 => { let addr = self.addr_immediate(mem); self.adc(mem.read(addr)); 2 }
            0x65 => { let addr = self.addr_zeropage(mem); self.adc(mem.read(addr)); 3 }
            0x75 => { let addr = self.addr_zeropage_x(mem); self.adc(mem.read(addr)); 4 }
            0x6D => { let addr = self.addr_absolute(mem); self.adc(mem.read(addr)); 4 }
            0x7D => { let (addr, p) = self.addr_absolute_x(mem); self.adc(mem.read(addr)); if p { 5 } else { 4 } }
            0x79 => { let (addr, p) = self.addr_absolute_y(mem); self.adc(mem.read(addr)); if p { 5 } else { 4 } }
            0x61 => { let addr = self.addr_indirect_x(mem); self.adc(mem.read(addr)); 6 }
            0x71 => { let (addr, p) = self.addr_indirect_y(mem); self.adc(mem.read(addr)); if p { 6 } else { 5 } }

            // ---- SBC ----
            0xE9 => { let addr = self.addr_immediate(mem); self.sbc(mem.read(addr)); 2 }
            0xE5 => { let addr = self.addr_zeropage(mem); self.sbc(mem.read(addr)); 3 }
            0xF5 => { let addr = self.addr_zeropage_x(mem); self.sbc(mem.read(addr)); 4 }
            0xED => { let addr = self.addr_absolute(mem); self.sbc(mem.read(addr)); 4 }
            0xFD => { let (addr, p) = self.addr_absolute_x(mem); self.sbc(mem.read(addr)); if p { 5 } else { 4 } }
            0xF9 => { let (addr, p) = self.addr_absolute_y(mem); self.sbc(mem.read(addr)); if p { 5 } else { 4 } }
            0xE1 => { let addr = self.addr_indirect_x(mem); self.sbc(mem.read(addr)); 6 }
            0xF1 => { let (addr, p) = self.addr_indirect_y(mem); self.sbc(mem.read(addr)); if p { 6 } else { 5 } }

            // ---- CMP ----
            0xC9 => { let addr = self.addr_immediate(mem); self.cmp(self.a, mem.read(addr)); 2 }
            0xC5 => { let addr = self.addr_zeropage(mem); self.cmp(self.a, mem.read(addr)); 3 }
            0xD5 => { let addr = self.addr_zeropage_x(mem); self.cmp(self.a, mem.read(addr)); 4 }
            0xCD => { let addr = self.addr_absolute(mem); self.cmp(self.a, mem.read(addr)); 4 }
            0xDD => { let (addr, p) = self.addr_absolute_x(mem); self.cmp(self.a, mem.read(addr)); if p { 5 } else { 4 } }
            0xD9 => { let (addr, p) = self.addr_absolute_y(mem); self.cmp(self.a, mem.read(addr)); if p { 5 } else { 4 } }
            0xC1 => { let addr = self.addr_indirect_x(mem); self.cmp(self.a, mem.read(addr)); 6 }
            0xD1 => { let (addr, p) = self.addr_indirect_y(mem); self.cmp(self.a, mem.read(addr)); if p { 6 } else { 5 } }

            // ---- CPX ----
            0xE0 => { let addr = self.addr_immediate(mem); self.cmp(self.x, mem.read(addr)); 2 }
            0xE4 => { let addr = self.addr_zeropage(mem); self.cmp(self.x, mem.read(addr)); 3 }
            0xEC => { let addr = self.addr_absolute(mem); self.cmp(self.x, mem.read(addr)); 4 }

            // ---- CPY ----
            0xC0 => { let addr = self.addr_immediate(mem); self.cmp(self.y, mem.read(addr)); 2 }
            0xC4 => { let addr = self.addr_zeropage(mem); self.cmp(self.y, mem.read(addr)); 3 }
            0xCC => { let addr = self.addr_absolute(mem); self.cmp(self.y, mem.read(addr)); 4 }

            // ---- INC/DEC ----
            0xE6 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.set_zn(v); 5 }
            0xF6 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.set_zn(v); 6 }
            0xEE => { let addr = self.addr_absolute(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.set_zn(v); 6 }
            0xFE => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.set_zn(v); 7 }
            0xC6 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.set_zn(v); 5 }
            0xD6 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.set_zn(v); 6 }
            0xCE => { let addr = self.addr_absolute(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.set_zn(v); 6 }
            0xDE => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.set_zn(v); 7 }

            0xE8 => { self.x = self.x.wrapping_add(1); self.set_zn(self.x); 2 } // INX
            0xC8 => { self.y = self.y.wrapping_add(1); self.set_zn(self.y); 2 } // INY
            0xCA => { self.x = self.x.wrapping_sub(1); self.set_zn(self.x); 2 } // DEX
            0x88 => { self.y = self.y.wrapping_sub(1); self.set_zn(self.y); 2 } // DEY

            // ---- Shift/Rotate ----
            0x0A => { let c = self.a >> 7; self.a <<= 1; self.set_flag(flags::C, c != 0); self.set_zn(self.a); 2 } // ASL A
            0x06 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 5 }
            0x16 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 6 }
            0x0E => { let addr = self.addr_absolute(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 6 }
            0x1E => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 7 }

            0x4A => { let c = self.a & 1; self.a >>= 1; self.set_flag(flags::C, c != 0); self.set_zn(self.a); 2 } // LSR A
            0x46 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 5 }
            0x56 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 6 }
            0x4E => { let addr = self.addr_absolute(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 6 }
            0x5E => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 7 }

            0x2A => { let old_c = self.flag(flags::C) as u8; let c = self.a >> 7; self.a = (self.a << 1) | old_c; self.set_flag(flags::C, c != 0); self.set_zn(self.a); 2 } // ROL A
            0x26 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 5 }
            0x36 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 6 }
            0x2E => { let addr = self.addr_absolute(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 6 }
            0x3E => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 7 }

            0x6A => { let old_c = self.flag(flags::C) as u8; let c = self.a & 1; self.a = (self.a >> 1) | (old_c << 7); self.set_flag(flags::C, c != 0); self.set_zn(self.a); 2 } // ROR A
            0x66 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 5 }
            0x76 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 6 }
            0x6E => { let addr = self.addr_absolute(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 6 }
            0x7E => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.set_zn(r); 7 }

            // ---- Jump/Call ----
            0x4C => { self.pc = self.addr_absolute(mem); 3 }             // JMP abs
            0x6C => { self.pc = self.addr_indirect(mem); 5 }             // JMP ind
            0x20 => { // JSR
                let target = self.fetch16(mem);
                let ret = self.pc.wrapping_sub(1);
                self.push16(mem, ret);
                self.pc = target;
                6
            }
            0x60 => { self.pc = self.pop16(mem).wrapping_add(1); 6 }    // RTS
            0x40 => { // RTI
                self.p = (self.pop(mem) | flags::U) & !flags::B;
                self.pc = self.pop16(mem);
                6
            }

            // ---- Branch ----
            0x90 => self.branch(mem, !self.flag(flags::C)), // BCC
            0xB0 => self.branch(mem, self.flag(flags::C)),  // BCS
            0xF0 => self.branch(mem, self.flag(flags::Z)),  // BEQ
            0xD0 => self.branch(mem, !self.flag(flags::Z)), // BNE
            0x30 => self.branch(mem, self.flag(flags::N)),  // BMI
            0x10 => self.branch(mem, !self.flag(flags::N)), // BPL
            0x70 => self.branch(mem, self.flag(flags::V)),  // BVS
            0x50 => self.branch(mem, !self.flag(flags::V)), // BVC

            // ---- Flag operations ----
            0x18 => { self.set_flag(flags::C, false); 2 } // CLC
            0x38 => { self.set_flag(flags::C, true);  2 } // SEC
            0x58 => { self.set_flag(flags::I, false); 2 } // CLI
            0x78 => { self.set_flag(flags::I, true);  2 } // SEI
            0xB8 => { self.set_flag(flags::V, false); 2 } // CLV
            0xD8 => { self.set_flag(flags::D, false); 2 } // CLD
            0xF8 => { self.set_flag(flags::D, true);  2 } // SED

            // ---- NOP ----
            0xEA => 2,
            // unofficial NOPs
            0x1A | 0x3A | 0x5A | 0x7A | 0xDA | 0xFA => 2,
            0x80 | 0x82 | 0x89 | 0xC2 | 0xE2 => { self.pc = self.pc.wrapping_add(1); 2 }
            0x04 | 0x44 | 0x64 => { self.pc = self.pc.wrapping_add(1); 3 }
            0x14 | 0x34 | 0x54 | 0x74 | 0xD4 | 0xF4 => { self.pc = self.pc.wrapping_add(1); 4 }
            0x0C => { self.pc = self.pc.wrapping_add(2); 4 }
            0x1C | 0x3C | 0x5C | 0x7C | 0xDC | 0xFC => { let (_, p) = self.addr_absolute_x(mem); if p { 5 } else { 4 } }

            // ---- BRK ----
            0x00 => {
                self.pc = self.pc.wrapping_add(1);
                self.push16(mem, self.pc);
                self.push(mem, self.p | flags::B | flags::U);
                self.p |= flags::I;
                self.pc = mem.read16(0xFFFE);
                7
            }

            // ---- unofficial: LAX ----
            0xA7 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr); self.a = v; self.x = v; self.set_zn(v); 3 }
            0xB7 => { let addr = self.addr_zeropage_y(mem); let v = mem.read(addr); self.a = v; self.x = v; self.set_zn(v); 4 }
            0xAF => { let addr = self.addr_absolute(mem); let v = mem.read(addr); self.a = v; self.x = v; self.set_zn(v); 4 }
            0xBF => { let (addr, p) = self.addr_absolute_y(mem); let v = mem.read(addr); self.a = v; self.x = v; self.set_zn(v); if p { 5 } else { 4 } }
            0xA3 => { let addr = self.addr_indirect_x(mem); let v = mem.read(addr); self.a = v; self.x = v; self.set_zn(v); 6 }
            0xB3 => { let (addr, p) = self.addr_indirect_y(mem); let v = mem.read(addr); self.a = v; self.x = v; self.set_zn(v); if p { 6 } else { 5 } }

            // ---- unofficial: SAX ----
            0x87 => { let addr = self.addr_zeropage(mem); mem.write(addr, self.a & self.x); 3 }
            0x97 => { let addr = self.addr_zeropage_y(mem); mem.write(addr, self.a & self.x); 4 }
            0x8F => { let addr = self.addr_absolute(mem); mem.write(addr, self.a & self.x); 4 }
            0x83 => { let addr = self.addr_indirect_x(mem); mem.write(addr, self.a & self.x); 6 }

            // ---- unofficial: DCP ----
            0xC7 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.cmp(self.a, v); 5 }
            0xD7 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.cmp(self.a, v); 6 }
            0xCF => { let addr = self.addr_absolute(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.cmp(self.a, v); 6 }
            0xDF => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.cmp(self.a, v); 7 }
            0xDB => { let (addr, _) = self.addr_absolute_y(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.cmp(self.a, v); 7 }
            0xC3 => { let addr = self.addr_indirect_x(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.cmp(self.a, v); 8 }
            0xD3 => { let (addr, _) = self.addr_indirect_y(mem); let v = mem.read(addr).wrapping_sub(1); mem.write(addr, v); self.cmp(self.a, v); 8 }

            // ---- unofficial: ISC (ISB) ----
            0xE7 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.sbc(v); 5 }
            0xF7 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.sbc(v); 6 }
            0xEF => { let addr = self.addr_absolute(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.sbc(v); 6 }
            0xFF => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.sbc(v); 7 }
            0xFB => { let (addr, _) = self.addr_absolute_y(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.sbc(v); 7 }
            0xE3 => { let addr = self.addr_indirect_x(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.sbc(v); 8 }
            0xF3 => { let (addr, _) = self.addr_indirect_y(mem); let v = mem.read(addr).wrapping_add(1); mem.write(addr, v); self.sbc(v); 8 }

            // ---- unofficial: SLO ----
            0x07 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a |= r; self.set_zn(self.a); 5 }
            0x17 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a |= r; self.set_zn(self.a); 6 }
            0x0F => { let addr = self.addr_absolute(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a |= r; self.set_zn(self.a); 6 }
            0x1F => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a |= r; self.set_zn(self.a); 7 }
            0x1B => { let (addr, _) = self.addr_absolute_y(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a |= r; self.set_zn(self.a); 7 }
            0x03 => { let addr = self.addr_indirect_x(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a |= r; self.set_zn(self.a); 8 }
            0x13 => { let (addr, _) = self.addr_indirect_y(mem); let v = mem.read(addr); let c = v >> 7; let r = v << 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a |= r; self.set_zn(self.a); 8 }

            // ---- unofficial: RLA ----
            0x27 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a &= r; self.set_zn(self.a); 5 }
            0x37 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a &= r; self.set_zn(self.a); 6 }
            0x2F => { let addr = self.addr_absolute(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a &= r; self.set_zn(self.a); 6 }
            0x3F => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a &= r; self.set_zn(self.a); 7 }
            0x3B => { let (addr, _) = self.addr_absolute_y(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a &= r; self.set_zn(self.a); 7 }
            0x23 => { let addr = self.addr_indirect_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a &= r; self.set_zn(self.a); 8 }
            0x33 => { let (addr, _) = self.addr_indirect_y(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v >> 7; let r = (v << 1) | old_c; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a &= r; self.set_zn(self.a); 8 }

            // ---- unofficial: SRE ----
            0x47 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a ^= r; self.set_zn(self.a); 5 }
            0x57 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a ^= r; self.set_zn(self.a); 6 }
            0x4F => { let addr = self.addr_absolute(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a ^= r; self.set_zn(self.a); 6 }
            0x5F => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a ^= r; self.set_zn(self.a); 7 }
            0x5B => { let (addr, _) = self.addr_absolute_y(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a ^= r; self.set_zn(self.a); 7 }
            0x43 => { let addr = self.addr_indirect_x(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a ^= r; self.set_zn(self.a); 8 }
            0x53 => { let (addr, _) = self.addr_indirect_y(mem); let v = mem.read(addr); let c = v & 1; let r = v >> 1; mem.write(addr, r); self.set_flag(flags::C, c != 0); self.a ^= r; self.set_zn(self.a); 8 }

            // ---- unofficial: RRA ----
            0x67 => { let addr = self.addr_zeropage(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.adc(r); 5 }
            0x77 => { let addr = self.addr_zeropage_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.adc(r); 6 }
            0x6F => { let addr = self.addr_absolute(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.adc(r); 6 }
            0x7F => { let (addr, _) = self.addr_absolute_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.adc(r); 7 }
            0x7B => { let (addr, _) = self.addr_absolute_y(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.adc(r); 7 }
            0x63 => { let addr = self.addr_indirect_x(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.adc(r); 8 }
            0x73 => { let (addr, _) = self.addr_indirect_y(mem); let v = mem.read(addr); let old_c = self.flag(flags::C) as u8; let c = v & 1; let r = (v >> 1) | (old_c << 7); mem.write(addr, r); self.set_flag(flags::C, c != 0); self.adc(r); 8 }

            // その他 unofficial / undocumented (KIL 等は NOP 扱い)
            _ => {
                // 未実装命令: 2 サイクル NOP として扱う
                2
            }
        }
    }

    fn adc(&mut self, val: u8) {
        let a = self.a as u16;
        let v = val as u16;
        let c = self.flag(flags::C) as u16;
        let result = a + v + c;
        self.set_flag(flags::C, result > 0xFF);
        self.set_flag(flags::V, !(a ^ v) & (a ^ result) & 0x80 != 0);
        self.a = result as u8;
        self.set_zn(self.a);
    }

    fn sbc(&mut self, val: u8) {
        self.adc(!val);
    }

    fn cmp(&mut self, reg: u8, val: u8) {
        let result = reg.wrapping_sub(val);
        self.set_flag(flags::C, reg >= val);
        self.set_zn(result);
    }
}

impl Default for Cpu {
    fn default() -> Self {
        Self::new()
    }
}

// テスト用のシンプルな Memory 実装
#[cfg(test)]
pub struct TestMemory {
    pub data: [u8; 65536],
}

#[cfg(test)]
impl TestMemory {
    pub fn new() -> Self {
        Self { data: [0u8; 65536] }
    }

    pub fn load(&mut self, addr: u16, bytes: &[u8]) {
        for (i, &b) in bytes.iter().enumerate() {
            self.data[addr as usize + i] = b;
        }
    }
}

#[cfg(test)]
impl Memory for TestMemory {
    fn read(&mut self, addr: u16) -> u8 {
        self.data[addr as usize]
    }

    fn write(&mut self, addr: u16, val: u8) {
        self.data[addr as usize] = val;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reset_at(addr: u16) -> (Cpu, TestMemory) {
        let mut cpu = Cpu::new();
        let mut mem = TestMemory::new();
        // RESET ベクタを設定
        mem.data[0xFFFC] = (addr & 0xFF) as u8;
        mem.data[0xFFFD] = (addr >> 8) as u8;
        cpu.reset(&mut mem);
        (cpu, mem)
    }

    #[test]
    fn test_cpu_reset_vector() {
        let (cpu, _) = reset_at(0x8000);
        assert_eq!(cpu.pc, 0x8000, "PC should be set to RESET vector");
        assert_eq!(cpu.sp, 0xFD);
        assert_eq!(cpu.p & flags::I, flags::I, "I flag should be set after reset");
    }

    #[test]
    fn test_cpu_lda_immediate() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        mem.load(0x8000, &[0xA9, 0x42]); // LDA #$42
        cpu.step(&mut mem);
        assert_eq!(cpu.a, 0x42);
        assert_eq!(cpu.p & flags::Z, 0, "Z should be 0");
        assert_eq!(cpu.p & flags::N, 0, "N should be 0");
        assert_eq!(cpu.pc, 0x8002);
    }

    #[test]
    fn test_cpu_lda_zero_sets_z_flag() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        mem.load(0x8000, &[0xA9, 0x00]); // LDA #$00
        cpu.step(&mut mem);
        assert_eq!(cpu.a, 0x00);
        assert_ne!(cpu.p & flags::Z, 0, "Z should be set when A=0");
    }

    #[test]
    fn test_cpu_lda_negative_sets_n_flag() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        mem.load(0x8000, &[0xA9, 0x80]); // LDA #$80
        cpu.step(&mut mem);
        assert_ne!(cpu.p & flags::N, 0, "N should be set when bit7=1");
    }

    #[test]
    fn test_cpu_lda_zeropage() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        mem.data[0x42] = 0xFF;
        mem.load(0x8000, &[0xA5, 0x42]); // LDA $42
        cpu.step(&mut mem);
        assert_eq!(cpu.a, 0xFF);
    }

    #[test]
    fn test_cpu_sta_zeropage() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        cpu.a = 0x55;
        mem.load(0x8000, &[0x85, 0x10]); // STA $10
        cpu.step(&mut mem);
        assert_eq!(mem.data[0x10], 0x55);
    }

    #[test]
    fn test_cpu_jmp_absolute() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        mem.load(0x8000, &[0x4C, 0x00, 0x90]); // JMP $9000
        cpu.step(&mut mem);
        assert_eq!(cpu.pc, 0x9000);
    }

    #[test]
    fn test_cpu_beq_taken() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        cpu.p |= flags::Z; // Z=1
        mem.load(0x8000, &[0xF0, 0x05]); // BEQ +5
        cpu.step(&mut mem);
        assert_eq!(cpu.pc, 0x8007, "BEQ should branch when Z=1");
    }

    #[test]
    fn test_cpu_beq_not_taken() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        cpu.p &= !flags::Z; // Z=0
        mem.load(0x8000, &[0xF0, 0x05]); // BEQ +5
        cpu.step(&mut mem);
        assert_eq!(cpu.pc, 0x8002, "BEQ should not branch when Z=0");
    }

    #[test]
    fn test_cpu_bne_taken() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        cpu.p &= !flags::Z; // Z=0
        mem.load(0x8000, &[0xD0, 0x03]); // BNE +3
        cpu.step(&mut mem);
        assert_eq!(cpu.pc, 0x8005);
    }

    #[test]
    fn test_cpu_nmi() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        // NMI ベクタを $9000 に設定
        mem.data[0xFFFA] = 0x00;
        mem.data[0xFFFB] = 0x90;
        cpu.pc = 0x8010;
        cpu.nmi(&mut mem);
        assert_eq!(cpu.pc, 0x9000, "NMI should jump to NMI vector");
        assert_ne!(cpu.p & flags::I, 0, "I flag should be set after NMI");
    }

    #[test]
    fn test_cpu_lda_cycles() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        mem.load(0x8000, &[0xA9, 0x01]); // LDA #immediate = 2 cycles
        let c = cpu.step(&mut mem);
        assert_eq!(c, 2, "LDA immediate should take 2 cycles");
    }

    #[test]
    fn test_cpu_jmp_cycles() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        mem.load(0x8000, &[0x4C, 0x00, 0x90]); // JMP abs = 3 cycles
        let c = cpu.step(&mut mem);
        assert_eq!(c, 3, "JMP absolute should take 3 cycles");
    }

    #[test]
    fn test_cpu_sta_cycles() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        cpu.a = 0x01;
        mem.load(0x8000, &[0x85, 0x10]); // STA zp = 3 cycles
        let c = cpu.step(&mut mem);
        assert_eq!(c, 3, "STA zeropage should take 3 cycles");
    }

    #[test]
    fn test_cpu_adc() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        cpu.a = 0x10;
        cpu.p &= !flags::C; // C=0
        mem.load(0x8000, &[0x69, 0x05]); // ADC #$05
        cpu.step(&mut mem);
        assert_eq!(cpu.a, 0x15);
    }

    #[test]
    fn test_cpu_sec_clc() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        mem.load(0x8000, &[0x38, 0x18]); // SEC, CLC
        cpu.step(&mut mem);
        assert_ne!(cpu.p & flags::C, 0, "C should be set after SEC");
        cpu.step(&mut mem);
        assert_eq!(cpu.p & flags::C, 0, "C should be clear after CLC");
    }

    #[test]
    fn test_cpu_jsr_rts() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        mem.load(0x8000, &[0x20, 0x00, 0x90]); // JSR $9000
        mem.load(0x9000, &[0x60]);              // RTS
        cpu.step(&mut mem);
        assert_eq!(cpu.pc, 0x9000, "JSR should jump to subroutine");
        cpu.step(&mut mem);
        assert_eq!(cpu.pc, 0x8003, "RTS should return after JSR");
    }

    #[test]
    fn test_cpu_inx_dex() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        cpu.x = 0x00;
        mem.load(0x8000, &[0xE8, 0xCA]); // INX, DEX
        cpu.step(&mut mem);
        assert_eq!(cpu.x, 0x01);
        cpu.step(&mut mem);
        assert_eq!(cpu.x, 0x00);
    }

    #[test]
    fn test_cpu_pha_pla() {
        let (mut cpu, mut mem) = reset_at(0x8000);
        cpu.a = 0x77;
        mem.load(0x8000, &[0x48, 0xA9, 0x00, 0x68]); // PHA, LDA #0, PLA
        cpu.step(&mut mem); // PHA
        cpu.step(&mut mem); // LDA #0
        assert_eq!(cpu.a, 0x00);
        cpu.step(&mut mem); // PLA
        assert_eq!(cpu.a, 0x77, "PLA should restore pushed value");
    }
}
