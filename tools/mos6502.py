"""tools/mos6502.py — MOS 6502 命令セットデータベース

各エントリ: opcode_byte -> (mnemonic, addressing_mode, byte_length, cycles)

アドレッシングモード略号:
  IMP = Implied       (例: SEI)
  ACC = Accumulator   (例: LSR A)
  IMM = Immediate     (例: LDA #$FF)
  ZP  = Zero Page     (例: LDA $00)
  ZPX = Zero Page,X   (例: LDA $00,X)
  ZPY = Zero Page,Y   (例: LDA $00,Y)
  ABS = Absolute      (例: LDA $2000)
  ABX = Absolute,X    (例: LDA $2000,X)
  ABY = Absolute,Y    (例: LDA $2000,Y)
  IND = Indirect      (例: JMP ($FFFC))
  IZX = (Indirect,X)  (例: LDA ($00,X))
  IZY = (Indirect),Y  (例: LDA ($00),Y)
  REL = Relative      (分岐命令: BEQ, BNE, ...)
"""

OPCODES: dict[int, tuple[str, str, int, int]] = {
    # ---- ADC ----
    0x69: ('ADC', 'IMM', 2, 2),
    0x65: ('ADC', 'ZP',  2, 3),
    0x75: ('ADC', 'ZPX', 2, 4),
    0x6D: ('ADC', 'ABS', 3, 4),
    0x7D: ('ADC', 'ABX', 3, 4),
    0x79: ('ADC', 'ABY', 3, 4),
    0x61: ('ADC', 'IZX', 2, 6),
    0x71: ('ADC', 'IZY', 2, 5),
    # ---- AND ----
    0x29: ('AND', 'IMM', 2, 2),
    0x25: ('AND', 'ZP',  2, 3),
    0x35: ('AND', 'ZPX', 2, 4),
    0x2D: ('AND', 'ABS', 3, 4),
    0x3D: ('AND', 'ABX', 3, 4),
    0x39: ('AND', 'ABY', 3, 4),
    0x21: ('AND', 'IZX', 2, 6),
    0x31: ('AND', 'IZY', 2, 5),
    # ---- ASL ----
    0x0A: ('ASL', 'ACC', 1, 2),
    0x06: ('ASL', 'ZP',  2, 5),
    0x16: ('ASL', 'ZPX', 2, 6),
    0x0E: ('ASL', 'ABS', 3, 6),
    0x1E: ('ASL', 'ABX', 3, 7),
    # ---- 分岐命令 (REL) ----
    0x90: ('BCC', 'REL', 2, 2),
    0xB0: ('BCS', 'REL', 2, 2),
    0xF0: ('BEQ', 'REL', 2, 2),
    0x30: ('BMI', 'REL', 2, 2),
    0xD0: ('BNE', 'REL', 2, 2),
    0x10: ('BPL', 'REL', 2, 2),
    0x50: ('BVC', 'REL', 2, 2),
    0x70: ('BVS', 'REL', 2, 2),
    # ---- BIT ----
    0x24: ('BIT', 'ZP',  2, 3),
    0x2C: ('BIT', 'ABS', 3, 4),
    # ---- BRK ----
    0x00: ('BRK', 'IMP', 1, 7),
    # ---- CLC/CLD/CLI/CLV ----
    0x18: ('CLC', 'IMP', 1, 2),
    0xD8: ('CLD', 'IMP', 1, 2),
    0x58: ('CLI', 'IMP', 1, 2),
    0xB8: ('CLV', 'IMP', 1, 2),
    # ---- CMP ----
    0xC9: ('CMP', 'IMM', 2, 2),
    0xC5: ('CMP', 'ZP',  2, 3),
    0xD5: ('CMP', 'ZPX', 2, 4),
    0xCD: ('CMP', 'ABS', 3, 4),
    0xDD: ('CMP', 'ABX', 3, 4),
    0xD9: ('CMP', 'ABY', 3, 4),
    0xC1: ('CMP', 'IZX', 2, 6),
    0xD1: ('CMP', 'IZY', 2, 5),
    # ---- CPX / CPY ----
    0xE0: ('CPX', 'IMM', 2, 2),
    0xE4: ('CPX', 'ZP',  2, 3),
    0xEC: ('CPX', 'ABS', 3, 4),
    0xC0: ('CPY', 'IMM', 2, 2),
    0xC4: ('CPY', 'ZP',  2, 3),
    0xCC: ('CPY', 'ABS', 3, 4),
    # ---- DEC / DEX / DEY ----
    0xC6: ('DEC', 'ZP',  2, 5),
    0xD6: ('DEC', 'ZPX', 2, 6),
    0xCE: ('DEC', 'ABS', 3, 6),
    0xDE: ('DEC', 'ABX', 3, 7),
    0xCA: ('DEX', 'IMP', 1, 2),
    0x88: ('DEY', 'IMP', 1, 2),
    # ---- EOR ----
    0x49: ('EOR', 'IMM', 2, 2),
    0x45: ('EOR', 'ZP',  2, 3),
    0x55: ('EOR', 'ZPX', 2, 4),
    0x4D: ('EOR', 'ABS', 3, 4),
    0x5D: ('EOR', 'ABX', 3, 4),
    0x59: ('EOR', 'ABY', 3, 4),
    0x41: ('EOR', 'IZX', 2, 6),
    0x51: ('EOR', 'IZY', 2, 5),
    # ---- INC / INX / INY ----
    0xE6: ('INC', 'ZP',  2, 5),
    0xF6: ('INC', 'ZPX', 2, 6),
    0xEE: ('INC', 'ABS', 3, 6),
    0xFE: ('INC', 'ABX', 3, 7),
    0xE8: ('INX', 'IMP', 1, 2),
    0xC8: ('INY', 'IMP', 1, 2),
    # ---- JMP / JSR ----
    0x4C: ('JMP', 'ABS', 3, 3),
    0x6C: ('JMP', 'IND', 3, 5),
    0x20: ('JSR', 'ABS', 3, 6),
    # ---- LDA ----
    0xA9: ('LDA', 'IMM', 2, 2),
    0xA5: ('LDA', 'ZP',  2, 3),
    0xB5: ('LDA', 'ZPX', 2, 4),
    0xAD: ('LDA', 'ABS', 3, 4),
    0xBD: ('LDA', 'ABX', 3, 4),
    0xB9: ('LDA', 'ABY', 3, 4),
    0xA1: ('LDA', 'IZX', 2, 6),
    0xB1: ('LDA', 'IZY', 2, 5),
    # ---- LDX ----
    0xA2: ('LDX', 'IMM', 2, 2),
    0xA6: ('LDX', 'ZP',  2, 3),
    0xB6: ('LDX', 'ZPY', 2, 4),
    0xAE: ('LDX', 'ABS', 3, 4),
    0xBE: ('LDX', 'ABY', 3, 4),
    # ---- LDY ----
    0xA0: ('LDY', 'IMM', 2, 2),
    0xA4: ('LDY', 'ZP',  2, 3),
    0xB4: ('LDY', 'ZPX', 2, 4),
    0xAC: ('LDY', 'ABS', 3, 4),
    0xBC: ('LDY', 'ABX', 3, 4),
    # ---- LSR ----
    0x4A: ('LSR', 'ACC', 1, 2),
    0x46: ('LSR', 'ZP',  2, 5),
    0x56: ('LSR', 'ZPX', 2, 6),
    0x4E: ('LSR', 'ABS', 3, 6),
    0x5E: ('LSR', 'ABX', 3, 7),
    # ---- NOP ----
    0xEA: ('NOP', 'IMP', 1, 2),
    # ---- ORA ----
    0x09: ('ORA', 'IMM', 2, 2),
    0x05: ('ORA', 'ZP',  2, 3),
    0x15: ('ORA', 'ZPX', 2, 4),
    0x0D: ('ORA', 'ABS', 3, 4),
    0x1D: ('ORA', 'ABX', 3, 4),
    0x19: ('ORA', 'ABY', 3, 4),
    0x01: ('ORA', 'IZX', 2, 6),
    0x11: ('ORA', 'IZY', 2, 5),
    # ---- スタック操作 ----
    0x48: ('PHA', 'IMP', 1, 3),
    0x08: ('PHP', 'IMP', 1, 3),
    0x68: ('PLA', 'IMP', 1, 4),
    0x28: ('PLP', 'IMP', 1, 4),
    # ---- ROL / ROR ----
    0x2A: ('ROL', 'ACC', 1, 2),
    0x26: ('ROL', 'ZP',  2, 5),
    0x36: ('ROL', 'ZPX', 2, 6),
    0x2E: ('ROL', 'ABS', 3, 6),
    0x3E: ('ROL', 'ABX', 3, 7),
    0x6A: ('ROR', 'ACC', 1, 2),
    0x66: ('ROR', 'ZP',  2, 5),
    0x76: ('ROR', 'ZPX', 2, 6),
    0x6E: ('ROR', 'ABS', 3, 6),
    0x7E: ('ROR', 'ABX', 3, 7),
    # ---- RTI / RTS ----
    0x40: ('RTI', 'IMP', 1, 6),
    0x60: ('RTS', 'IMP', 1, 6),
    # ---- SBC ----
    0xE9: ('SBC', 'IMM', 2, 2),
    0xE5: ('SBC', 'ZP',  2, 3),
    0xF5: ('SBC', 'ZPX', 2, 4),
    0xED: ('SBC', 'ABS', 3, 4),
    0xFD: ('SBC', 'ABX', 3, 4),
    0xF9: ('SBC', 'ABY', 3, 4),
    0xE1: ('SBC', 'IZX', 2, 6),
    0xF1: ('SBC', 'IZY', 2, 5),
    # ---- SEC / SED / SEI ----
    0x38: ('SEC', 'IMP', 1, 2),
    0xF8: ('SED', 'IMP', 1, 2),
    0x78: ('SEI', 'IMP', 1, 2),
    # ---- STA ----
    0x85: ('STA', 'ZP',  2, 3),
    0x95: ('STA', 'ZPX', 2, 4),
    0x8D: ('STA', 'ABS', 3, 4),
    0x9D: ('STA', 'ABX', 3, 5),
    0x99: ('STA', 'ABY', 3, 5),
    0x81: ('STA', 'IZX', 2, 6),
    0x91: ('STA', 'IZY', 2, 6),
    # ---- STX / STY ----
    0x86: ('STX', 'ZP',  2, 3),
    0x96: ('STX', 'ZPY', 2, 4),
    0x8E: ('STX', 'ABS', 3, 4),
    0x84: ('STY', 'ZP',  2, 3),
    0x94: ('STY', 'ZPX', 2, 4),
    0x8C: ('STY', 'ABS', 3, 4),
    # ---- レジスタ転送 ----
    0xAA: ('TAX', 'IMP', 1, 2),
    0xA8: ('TAY', 'IMP', 1, 2),
    0xBA: ('TSX', 'IMP', 1, 2),
    0x8A: ('TXA', 'IMP', 1, 2),
    0x9A: ('TXS', 'IMP', 1, 2),
    0x98: ('TYA', 'IMP', 1, 2),
}

BRANCH_MNEMONICS = {'BCC', 'BCS', 'BEQ', 'BMI', 'BNE', 'BPL', 'BVC', 'BVS'}


def lookup(opcode: int) -> tuple[str, str, int, int] | None:
    """オペコードを検索して (mnemonic, mode, bytes, cycles) を返す。未知なら None。"""
    return OPCODES.get(opcode)


def branch_offset(from_addr: int, to_addr: int) -> int:
    """分岐命令のオフセットバイトを計算する。

    from_addr: BEQ/BNE 等の命令アドレス（分岐命令の最初のバイトのアドレス）
    to_addr:   分岐先アドレス

    返値: 0x00〜0xFF の符号なしバイト値（2の補数エンコード）
    raises ValueError: 分岐範囲外の場合 (±127 バイトを超える)
    """
    next_pc = from_addr + 2   # 分岐命令は常に2バイト
    offset = to_addr - next_pc
    if not (-128 <= offset <= 127):
        raise ValueError(
            f"分岐範囲外: from ${from_addr:04X} to ${to_addr:04X} "
            f"= offset {offset:+d} (±127 の範囲外)"
        )
    return offset & 0xFF   # 負数は 2の補数 (例: -4 → 0xFC)


def branch_target(from_addr: int, offset_byte: int) -> int:
    """分岐命令アドレスとオフセットバイトから分岐先アドレスを計算する。

    from_addr:   BEQ 等の命令アドレス
    offset_byte: 命令の第2バイト（0x00〜0xFF）

    返値: 分岐先の CPU アドレス
    """
    next_pc = from_addr + 2
    # 符号付き解釈 (-128 〜 +127)
    signed = offset_byte if offset_byte < 0x80 else offset_byte - 0x100
    return next_pc + signed
