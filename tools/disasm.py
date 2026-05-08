#!/usr/bin/env python3
"""tools/disasm.py — NES ROM 逆アセンブラ + NES レジスタ解説ツール

使い方:
  python3 tools/disasm.py game.nes                        # PRG-ROM 全体を逆アセンブル
  python3 tools/disasm.py game.nes --from 0x80FF          # アドレス以降のみ
  python3 tools/disasm.py game.nes --from 0x80FF --to 0x8160
  python3 tools/disasm.py game.nes --branch 0x8103 0x8110 # 分岐オフセット計算
  python3 tools/disasm.py game.nes --ppuctrl 0x88        # PPUCTRL ビット解説
  python3 tools/disasm.py game.nes --ppumask 0x1E        # PPUMASK ビット解説
  python3 tools/disasm.py game.nes --chr                 # CHR-ROM タイルマップ表示
"""

import argparse
import sys
from pathlib import Path

# tools/ を import パスに追加
sys.path.insert(0, str(Path(__file__).parent))
from mos6502 import OPCODES, BRANCH_MNEMONICS, branch_offset, branch_target

# ============================================================
# NES メモリマップ・レジスタ解説
# ============================================================

NES_MEMMAP = {
    0x0000: "RAM (zero page)",
    0x0200: "OAM Shadow (sprite DMA buffer)",
    0x2000: "PPUCTRL",
    0x2001: "PPUMASK",
    0x2002: "PPUSTATUS",
    0x2003: "OAMADDR",
    0x2004: "OAMDATA",
    0x2005: "PPUSCROLL",
    0x2006: "PPUADDR",
    0x2007: "PPUDATA",
    0x4000: "APU Pulse1",
    0x4014: "OAMDMA",
    0x4015: "APU Status",
    0x4016: "JOY1 (Controller 1)",
    0x4017: "JOY2 (Controller 2)",
    0x8000: "PRG-ROM start",
}

PPUCTRL_BITS = [
    (7, "NMI enable",             {0: "disabled", 1: "enabled on vblank"}),
    (6, "Master/Slave",           {0: "read from EXT", 1: "output to EXT"}),
    (5, "Sprite size",            {0: "8x8", 1: "8x16"}),
    (4, "BG pattern table",       {0: "$0000 (PT0)", 1: "$1000 (PT1)"}),
    (3, "Sprite pattern table",   {0: "$0000 (PT0)", 1: "$1000 (PT1)"}),
    (2, "VRAM addr increment",    {0: "+1 (horizontal)", 1: "+32 (vertical)"}),
    (1, "Nametable Y",            {0: "$2000/$2400", 1: "$2800/$2C00"}),
    (0, "Nametable X",            {0: "$2000/$2800", 1: "$2400/$2C00"}),
]

PPUMASK_BITS = [
    (7, "Emphasize blue",         {0: "off", 1: "on"}),
    (6, "Emphasize green",        {0: "off", 1: "on"}),
    (5, "Emphasize red",          {0: "off", 1: "on"}),
    (4, "Show sprites",           {0: "hidden", 1: "visible"}),
    (3, "Show background",        {0: "hidden", 1: "visible"}),
    (2, "Show sprites left 8px",  {0: "hidden", 1: "visible"}),
    (1, "Show BG left 8px",       {0: "hidden", 1: "visible"}),
    (0, "Greyscale",              {0: "color", 1: "greyscale"}),
]

NES_PALETTE = {
    0x00: "Gray",     0x01: "Azure",    0x02: "Blue",     0x03: "Violet",
    0x04: "Magenta",  0x05: "Rose",     0x06: "Red-Org",  0x07: "Orange",
    0x08: "Yellow",   0x09: "Chartreu", 0x0A: "Green",    0x0B: "Spring",
    0x0C: "Cyan",     0x0D: "Black",    0x0E: "Black",    0x0F: "Black",
    0x10: "Lt.Gray",  0x11: "Lt.Azure", 0x12: "Lt.Blue",  0x13: "Lt.Violet",
    0x14: "Lt.Magnt", 0x15: "Lt.Rose",  0x16: "Lt.Red",   0x17: "Lt.Org",
    0x18: "Lt.Yello", 0x19: "Lt.Chart", 0x1A: "Lt.Green", 0x1B: "Lt.Spring",
    0x1C: "Lt.Cyan",  0x1D: "Dk.Gray",  0x1E: "Black",    0x1F: "Black",
    0x20: "White",    0x30: "White",
}

# ============================================================
# 逆アセンブラ
# ============================================================

def format_operand(mode: str, data: bytes, addr: int) -> str:
    """アドレッシングモードに合わせてオペランドを文字列化する。"""
    if mode == 'IMP':
        return ""
    if mode == 'ACC':
        return "A"
    if mode == 'IMM':
        return f"#${data[1]:02X}"
    if mode == 'ZP':
        return f"${data[1]:02X}"
    if mode == 'ZPX':
        return f"${data[1]:02X},X"
    if mode == 'ZPY':
        return f"${data[1]:02X},Y"
    if mode == 'ABS':
        target = data[1] | (data[2] << 8)
        label = NES_MEMMAP.get(target, "")
        suffix = f"  [{label}]" if label else ""
        return f"${target:04X}{suffix}"
    if mode == 'ABX':
        target = data[1] | (data[2] << 8)
        return f"${target:04X},X"
    if mode == 'ABY':
        target = data[1] | (data[2] << 8)
        return f"${target:04X},Y"
    if mode == 'IND':
        target = data[1] | (data[2] << 8)
        return f"(${target:04X})"
    if mode == 'IZX':
        return f"(${data[1]:02X},X)"
    if mode == 'IZY':
        return f"(${data[1]:02X}),Y"
    if mode == 'REL':
        target = branch_target(addr, data[1])
        signed = data[1] if data[1] < 0x80 else data[1] - 0x100
        sign = '+' if signed >= 0 else ''
        return f"${target:04X}  [{sign}{signed}]"
    return "?"


def disassemble(prg: bytes, start_cpu: int = 0x8000,
                addr_from: int | None = None,
                addr_to: int | None = None) -> list[str]:
    """PRG-ROM を逆アセンブルして行リストを返す。"""
    lines = []
    offset = (addr_from - start_cpu) if addr_from else 0
    end_offset = (addr_to - start_cpu) if addr_to else len(prg)
    end_offset = min(end_offset, len(prg))

    while offset < end_offset:
        cpu_addr = start_cpu + offset
        opcode = prg[offset]
        info = OPCODES.get(opcode)

        if info is None:
            # 未知オペコード: 1バイト .db として表示
            lines.append(f"${cpu_addr:04X}: {opcode:02X}           .db  ${opcode:02X}")
            offset += 1
            continue

        mnemonic, mode, length, cycles = info
        raw = prg[offset:offset + length]
        raw_str = ' '.join(f'{b:02X}' for b in raw).ljust(8)
        operand = format_operand(mode, raw, cpu_addr)

        line = f"${cpu_addr:04X}: {raw_str}  {mnemonic}  {operand}"
        lines.append(line)
        offset += length

    return lines


# ============================================================
# NES レジスタビット解説
# ============================================================

def decode_register(value: int, bit_defs: list) -> str:
    lines = [f"  ${value:02X} = {value:08b}b"]
    for bit, name, meanings in reversed(bit_defs):
        v = (value >> bit) & 1
        desc = meanings.get(v, str(v))
        lines.append(f"  bit{bit} [{v}]  {name:28s} → {desc}")
    return '\n'.join(lines)


# ============================================================
# CHR-ROM タイルマップ
# ============================================================

def show_chr(chr_data: bytes) -> list[str]:
    """CHR-ROM の各タイルをテキストで可視化する。"""
    lines = []
    n_tiles = len(chr_data) // 16
    for tile_idx in range(min(n_tiles, 512)):
        base = tile_idx * 16
        if all(b == 0 for b in chr_data[base:base + 16]):
            continue   # 空白タイルはスキップ

        pt = "PT0" if tile_idx < 256 else "PT1"
        pt_tile = tile_idx if tile_idx < 256 else tile_idx - 256
        chr_addr = tile_idx * 16
        lines.append(f"\n[Tile ${pt_tile:02X} in {pt}  CHR addr ${chr_addr:04X}]")

        plane0 = chr_data[base:base + 8]
        plane1 = chr_data[base + 8:base + 16]

        for row in range(8):
            p0 = plane0[row]
            p1 = plane1[row]
            pixels = ""
            for col in range(7, -1, -1):
                b0 = (p0 >> col) & 1
                b1 = (p1 >> col) & 1
                v = (b1 << 1) | b0
                pixels += ".░▒█"[v]
            lines.append(f"  row{row}: {p0:08b} | {p1:08b}  {pixels}")

    return lines


# ============================================================
# メインエントリ
# ============================================================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="NES ROM 逆アセンブラ + NES レジスタ解説ツール"
    )
    parser.add_argument("rom", help="iNES ROM ファイル (.nes)")
    parser.add_argument("--from", dest="addr_from", metavar="ADDR",
                        help="逆アセンブル開始 CPU アドレス (例: 0x80FF or $80FF)")
    parser.add_argument("--to", dest="addr_to", metavar="ADDR",
                        help="逆アセンブル終了 CPU アドレス（この番地は含まない）")
    parser.add_argument("--branch", nargs=2, metavar=("FROM", "TO"),
                        help="分岐オフセット計算: FROM アドレスから TO へ")
    parser.add_argument("--ppuctrl", metavar="VALUE",
                        help="PPUCTRL ($2000) のビット解説")
    parser.add_argument("--ppumask", metavar="VALUE",
                        help="PPUMASK ($2001) のビット解説")
    parser.add_argument("--chr", action="store_true",
                        help="CHR-ROM のタイルを ASCII アートで表示")
    args = parser.parse_args()

    # ROM 読み込み
    rom_path = Path(args.rom)
    if not rom_path.exists():
        print(f"Error: {rom_path} が見つかりません", file=sys.stderr)
        sys.exit(1)

    rom_data = rom_path.read_bytes()
    if len(rom_data) < 16 or rom_data[:4] != b'NES\x1a':
        print("Error: 有効な iNES ROM ではありません", file=sys.stderr)
        sys.exit(1)

    prg_banks = rom_data[4]
    chr_banks = rom_data[5]
    prg_size = prg_banks * 16384
    chr_size = chr_banks * 8192
    prg = rom_data[16:16 + prg_size]
    chr_data = rom_data[16 + prg_size:16 + prg_size + chr_size]

    print(f"ROM: {rom_path.name}  ({len(rom_data)} bytes)")
    print(f"PRG: {prg_size // 1024}KB  CHR: {chr_size // 1024}KB  Mapper: {(rom_data[6] >> 4) | (rom_data[7] & 0xF0)}")

    # ベクタテーブル
    nmi   = prg[-6] | (prg[-5] << 8)
    reset = prg[-4] | (prg[-3] << 8)
    irq   = prg[-2] | (prg[-1] << 8)
    print(f"Vectors: NMI=${nmi:04X}  RESET=${reset:04X}  IRQ=${irq:04X}\n")

    def parse_hex(s: str) -> int:
        s = s.strip()
        if s.startswith('$'):
            return int(s[1:], 16)
        return int(s, 0)

    # ---- 分岐オフセット計算 ----
    if args.branch:
        fa, ta = args.branch
        fa, ta = parse_hex(fa), parse_hex(ta)
        try:
            off = branch_offset(fa, ta)
            signed = off if off < 0x80 else off - 0x100
            print(f"分岐オフセット計算:")
            print(f"  from: ${fa:04X}")
            print(f"  to:   ${ta:04X}")
            print(f"  → オフセットバイト: ${off:02X}  ({signed:+d})")
            print(f"  → 命令例: BEQ ${off:02X}  (= BEQ → ${ta:04X})")
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        return

    # ---- PPUCTRL 解説 ----
    if args.ppuctrl:
        v = parse_hex(args.ppuctrl)
        print("PPUCTRL ($2000) ビット解説:")
        print(decode_register(v, PPUCTRL_BITS))
        return

    # ---- PPUMASK 解説 ----
    if args.ppumask:
        v = parse_hex(args.ppumask)
        print("PPUMASK ($2001) ビット解説:")
        print(decode_register(v, PPUMASK_BITS))
        return

    # ---- CHR タイル表示 ----
    if args.chr:
        if not chr_data:
            print("CHR-ROM が空です")
            return
        for line in show_chr(chr_data):
            print(line)
        return

    # ---- 逆アセンブル ----
    addr_from = parse_hex(args.addr_from) if args.addr_from else None
    addr_to   = parse_hex(args.addr_to)   if args.addr_to   else None

    # NROM-128: PRG-ROM は $8000〜$BFFF にマップ (16KB)
    # $C000〜$FFFF はミラー。逆アセンブルは $8000 からで十分。
    start_cpu = 0x8000

    lines = disassemble(prg, start_cpu, addr_from, addr_to)

    # NOP ランが続く場合は省略
    prev_nop = False
    nop_count = 0
    for line in lines:
        is_nop = '  NOP' in line
        if is_nop:
            nop_count += 1
            if nop_count == 1:
                print(line)
            elif nop_count == 2:
                print("  ... (NOP続く)")
        else:
            nop_count = 0
            print(line)


if __name__ == '__main__':
    main()
