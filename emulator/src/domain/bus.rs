use crate::domain::cartridge::Cartridge;
use crate::domain::controller::Controller;
use crate::domain::cpu::Memory;
use crate::domain::ppu::Ppu;

/// NES の CPU アドレス空間 ($0000–$FFFF) を管理するバス
pub struct Bus {
    pub ram: [u8; 2048],
    pub ppu: Ppu,
    pub cartridge: Option<Cartridge>,
    pub controller1: Controller,
    pub controller2: Controller,
    /// OAM DMA のスタールサイクル
    pub dma_stall: u32,
}

impl Bus {
    pub fn new() -> Self {
        Self {
            ram: [0u8; 2048],
            ppu: Ppu::new(),
            cartridge: None,
            controller1: Controller::new(),
            controller2: Controller::new(),
            dma_stall: 0,
        }
    }

    pub fn load_cartridge(&mut self, cart: Cartridge) {
        // CHR データを PPU にロード
        let chr = cart.rom_data.chr_rom.clone();
        self.ppu.load_chr(&chr);
        self.cartridge = Some(cart);
    }
}

impl Memory for Bus {
    fn read(&mut self, addr: u16) -> u8 {
        match addr {
            // RAM ($0000-$07FF, $0800-$1FFF はミラー)
            0x0000..=0x1FFF => self.ram[(addr & 0x07FF) as usize],

            // PPU レジスタ ($2000-$2007, $2008-$3FFF はミラー)
            0x2000..=0x3FFF => {
                let reg = 0x2000 | (addr & 0x0007);
                self.ppu.read_register(reg)
            }

            // APU / I/O ($4000-$401F)
            0x4000..=0x4013 => 0, // APU (未実装)
            0x4014 => 0,          // OAM DMA (書き込み専用)
            0x4015 => 0,          // APU ステータス (未実装)
            0x4016 => {
                // コントローラー 1
                self.controller1.read()
            }
            0x4017 => {
                // コントローラー 2
                self.controller2.read()
            }
            0x4018..=0x401F => 0,

            // カートリッジ空間 ($4020-$FFFF)
            0x4020..=0xFFFF => {
                if let Some(ref cart) = self.cartridge {
                    cart.read_prg(addr)
                } else {
                    0
                }
            }
        }
    }

    fn write(&mut self, addr: u16, val: u8) {
        match addr {
            0x0000..=0x1FFF => {
                self.ram[(addr & 0x07FF) as usize] = val;
            }
            0x2000..=0x3FFF => {
                let reg = 0x2000 | (addr & 0x0007);
                self.ppu.write_register(reg, val);
            }
            0x4000..=0x4013 => {} // APU (未実装)
            0x4014 => {
                // OAM DMA
                let page = (val as u16) << 8;
                for i in 0..256u16 {
                    let byte = self.read(page + i);
                    self.ppu.oam[self.ppu.oam_addr.wrapping_add(i as u8) as usize] = byte;
                }
                // DMA は 513 (または 514) サイクル消費
                self.dma_stall = 513;
            }
            0x4015 => {} // APU (未実装)
            0x4016 => {
                self.controller1.write(val);
                self.controller2.write(val);
            }
            0x4017 => {} // APU フレームカウンター (未実装)
            0x4018..=0x401F => {}
            0x4020..=0xFFFF => {
                if let Some(ref mut cart) = self.cartridge {
                    cart.write_prg(addr, val);
                }
            }
        }
    }
}

impl Default for Bus {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bus_ram_read_write() {
        let mut bus = Bus::new();
        bus.write(0x0010, 0xAB);
        assert_eq!(bus.read(0x0010), 0xAB);
    }

    #[test]
    fn test_bus_ram_write_read_boundary() {
        let mut bus = Bus::new();
        bus.write(0x0000, 0x11);
        bus.write(0x07FF, 0x22);
        assert_eq!(bus.read(0x0000), 0x11);
        assert_eq!(bus.read(0x07FF), 0x22);
    }

    #[test]
    fn test_bus_ram_mirror_0800() {
        let mut bus = Bus::new();
        bus.write(0x0010, 0x55);
        // $0810 は $0010 のミラー
        assert_eq!(bus.read(0x0810), 0x55, "$0810 should mirror $0010");
    }

    #[test]
    fn test_bus_ram_mirror_1000() {
        let mut bus = Bus::new();
        bus.write(0x0042, 0x77);
        // $1042 は $0042 のミラー
        assert_eq!(bus.read(0x1042), 0x77, "$1042 should mirror $0042");
    }

    #[test]
    fn test_bus_ram_mirror_1800() {
        let mut bus = Bus::new();
        bus.write(0x0100, 0x33);
        assert_eq!(bus.read(0x1900), 0x33, "$1900 should mirror $0100");
    }

    #[test]
    fn test_bus_controller1_read_write() {
        let mut bus = Bus::new();
        // A ボタンを押す
        bus.controller1.set_buttons(0x01); // A = bit0
        // ストローブ
        bus.write(0x4016, 0x01);
        bus.write(0x4016, 0x00);
        // 1 回目の読み取りは A ボタン (1)
        let bit = bus.read(0x4016);
        assert_eq!(bit, 1, "Controller1 A button should read as 1");
    }

    #[test]
    fn test_bus_prg_rom_read_with_cartridge() {
        use crate::infrastructure::rom_parser::make_test_rom;
        let mut rom = make_test_rom(1, 1, 0, 0);
        rom[16] = 0xEA; // PRG-ROM 先頭 = $8000
        let cart = Cartridge::from_bytes(&rom).unwrap();
        let mut bus = Bus::new();
        bus.load_cartridge(cart);
        assert_eq!(bus.read(0x8000), 0xEA, "$8000 should read from PRG-ROM");
    }

    #[test]
    fn test_bus_prg_rom_mirror_no_cartridge() {
        let mut bus = Bus::new();
        // カートリッジなし → 0 を返す
        assert_eq!(bus.read(0x8000), 0);
    }
}
