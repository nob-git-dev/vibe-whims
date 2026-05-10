"""tools/asm.py — MOS 6502 ミニアセンブラ

mos6502.py のオペコードテーブルを使い、Python DSL から
PRG-ROM バイト列を生成する。

特徴:
  - ラベルによる分岐先・JMP 先の自動計算（前方参照も可）
  - game.rom.txt 形式のアノテーション付きダンプを出力
  - 全オフセット計算を自動化 → 手計算ミスをゼロに

使い方:
    from tools.asm import Assembler, W

    a = Assembler(base=0x8000)
    a.label('RESET')
    a.SEI(); a.CLD()
    a.LDX(W(0xFF)); a.TXS()
    a.label('LOOP')
    a.DEX()
    a.BNE('LOOP')
    a.RTI()

    prg = a.build()   # bytes を返す
    a.print_txt()     # アノテーション付きダンプを stdout に
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Union
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mos6502 import OPCODES, branch_offset as calc_branch_offset

# ---------------------------------------------------------------------------
# オペランドヘルパー
# ---------------------------------------------------------------------------

def W(v: int) -> int:
    """Immediate / Absolute / ZP オペランド（値そのまま、型ヒント用）"""
    return v

# ---------------------------------------------------------------------------
# 内部命令表現
# ---------------------------------------------------------------------------

@dataclass
class Instr:
    mnemonic: str
    mode: str
    operand: Union[int, str, None]   # int=値, str=ラベル名, None=implied
    length: int   # バイト数
    addr: int = 0
    comment: str = ""

# ---------------------------------------------------------------------------
# アセンブラ本体
# ---------------------------------------------------------------------------

_BRANCH_MODES = {'BCC', 'BCS', 'BEQ', 'BMI', 'BNE', 'BPL', 'BVC', 'BVS'}

class Assembler:
    def __init__(self, base: int = 0x8000):
        self.base = base
        self._instrs: list[Instr] = []
        self._labels: dict[str, int] = {}  # label → CPU address
        self._sections: list[tuple[int, str]] = []  # (instr_index, section_name)

    # ---- アドレス管理 ----

    def _cur_addr(self) -> int:
        return self.base + sum(i.length for i in self._instrs)

    def label(self, name: str, comment: str = ""):
        self._labels[name] = self._cur_addr()

    def section(self, name: str):
        """セクション見出しコメントをマーク（出力にのみ影響）"""
        self._sections.append((len(self._instrs), name))

    # ---- 命令エミット ----

    def _emit(self, mn: str, mode: str, op=None, comment: str = ""):
        for byte, (m, md, length, _) in OPCODES.items():
            if m == mn and md == mode:
                instr = Instr(mn, mode, op, length, self._cur_addr(), comment)
                self._instrs.append(instr)
                return
        raise ValueError(f"未知の命令: {mn} {mode}")

    # ---- 命令セット ----

    # Implied / Register
    def SEI(self, c=""): self._emit('SEI', 'IMP', comment=c)
    def CLD(self, c=""): self._emit('CLD', 'IMP', comment=c)
    def CLC(self, c=""): self._emit('CLC', 'IMP', comment=c)
    def SEC(self, c=""): self._emit('SEC', 'IMP', comment=c)
    def CLI(self, c=""): self._emit('CLI', 'IMP', comment=c)
    def CLV(self, c=""): self._emit('CLV', 'IMP', comment=c)
    def NOP(self, c=""): self._emit('NOP', 'IMP', comment=c)
    def TXS(self, c=""): self._emit('TXS', 'IMP', comment=c)
    def TSX(self, c=""): self._emit('TSX', 'IMP', comment=c)
    def TAX(self, c=""): self._emit('TAX', 'IMP', comment=c)
    def TAY(self, c=""): self._emit('TAY', 'IMP', comment=c)
    def TXA(self, c=""): self._emit('TXA', 'IMP', comment=c)
    def TYA(self, c=""): self._emit('TYA', 'IMP', comment=c)
    def PHA(self, c=""): self._emit('PHA', 'IMP', comment=c)
    def PLA(self, c=""): self._emit('PLA', 'IMP', comment=c)
    def PHP(self, c=""): self._emit('PHP', 'IMP', comment=c)
    def PLP(self, c=""): self._emit('PLP', 'IMP', comment=c)
    def DEX(self, c=""): self._emit('DEX', 'IMP', comment=c)
    def DEY(self, c=""): self._emit('DEY', 'IMP', comment=c)
    def INX(self, c=""): self._emit('INX', 'IMP', comment=c)
    def INY(self, c=""): self._emit('INY', 'IMP', comment=c)
    def RTI(self, c=""): self._emit('RTI', 'IMP', comment=c)
    def RTS(self, c=""): self._emit('RTS', 'IMP', comment=c)
    def BRK(self, c=""): self._emit('BRK', 'IMP', comment=c)

    # LDA
    def LDA(self, op, mode_hint=None, c=""):
        if isinstance(op, str):
            self._emit('LDA', 'ZP' if mode_hint != 'ABS' else 'ABS', op, c)
        elif op < 0x100 and mode_hint != 'ABS':
            self._emit('LDA', 'IMM', op, c)  # default imm if fits
        else:
            self._emit('LDA', 'ABS', op, c)
    def LDA_IMM(self, v, c=""): self._emit('LDA', 'IMM', v, c)
    def LDA_ZP(self, v, c=""):  self._emit('LDA', 'ZP',  v, c)
    def LDA_ZPX(self, v, c=""): self._emit('LDA', 'ZPX', v, c)
    def LDA_ABS(self, v, c=""): self._emit('LDA', 'ABS', v, c)
    def LDA_ABX(self, v, c=""): self._emit('LDA', 'ABX', v, c)
    def LDA_ABY(self, v, c=""): self._emit('LDA', 'ABY', v, c)
    def LDA_IZX(self, v, c=""): self._emit('LDA', 'IZX', v, c)
    def LDA_IZY(self, v, c=""): self._emit('LDA', 'IZY', v, c)

    # LDX
    def LDX_IMM(self, v, c=""): self._emit('LDX', 'IMM', v, c)
    def LDX_ZP(self, v, c=""):  self._emit('LDX', 'ZP',  v, c)
    def LDX_ABS(self, v, c=""): self._emit('LDX', 'ABS', v, c)

    # LDY
    def LDY_IMM(self, v, c=""): self._emit('LDY', 'IMM', v, c)
    def LDY_ZP(self, v, c=""):  self._emit('LDY', 'ZP',  v, c)
    def LDY_ABS(self, v, c=""): self._emit('LDY', 'ABS', v, c)

    # STA
    def STA_ZP(self, v, c=""):  self._emit('STA', 'ZP',  v, c)
    def STA_ZPX(self, v, c=""): self._emit('STA', 'ZPX', v, c)
    def STA_ABS(self, v, c=""): self._emit('STA', 'ABS', v, c)
    def STA_ABX(self, v, c=""): self._emit('STA', 'ABX', v, c)
    def STA_ABY(self, v, c=""): self._emit('STA', 'ABY', v, c)
    def STA_IZY(self, v, c=""): self._emit('STA', 'IZY', v, c)

    # STX / STY
    def STX_ZP(self, v, c=""):  self._emit('STX', 'ZP',  v, c)
    def STX_ABS(self, v, c=""): self._emit('STX', 'ABS', v, c)
    def STY_ZP(self, v, c=""):  self._emit('STY', 'ZP',  v, c)
    def STY_ABS(self, v, c=""): self._emit('STY', 'ABS', v, c)

    # Arithmetic
    def ADC_IMM(self, v, c=""): self._emit('ADC', 'IMM', v, c)
    def ADC_ZP(self, v, c=""):  self._emit('ADC', 'ZP',  v, c)
    def SBC_IMM(self, v, c=""): self._emit('SBC', 'IMM', v, c)
    def SBC_ZP(self, v, c=""):  self._emit('SBC', 'ZP',  v, c)

    # Compare
    def CMP_IMM(self, v, c=""): self._emit('CMP', 'IMM', v, c)
    def CMP_ZP(self, v, c=""):  self._emit('CMP', 'ZP',  v, c)
    def CMP_ABS(self, v, c=""): self._emit('CMP', 'ABS', v, c)
    def CPX_IMM(self, v, c=""): self._emit('CPX', 'IMM', v, c)
    def CPY_IMM(self, v, c=""): self._emit('CPY', 'IMM', v, c)

    # Logic
    def AND_IMM(self, v, c=""): self._emit('AND', 'IMM', v, c)
    def AND_ZP(self, v, c=""):  self._emit('AND', 'ZP',  v, c)
    def ORA_IMM(self, v, c=""): self._emit('ORA', 'IMM', v, c)
    def ORA_ZP(self, v, c=""):  self._emit('ORA', 'ZP',  v, c)
    def EOR_IMM(self, v, c=""): self._emit('EOR', 'IMM', v, c)

    # Shift / Rotate
    def ASL_ACC(self, c=""): self._emit('ASL', 'ACC', comment=c)
    def LSR_ACC(self, c=""): self._emit('LSR', 'ACC', comment=c)
    def ROL_ZP(self, v, c=""): self._emit('ROL', 'ZP', v, c)

    # Inc / Dec
    def INC_ZP(self, v, c=""):  self._emit('INC', 'ZP',  v, c)
    def INC_ABS(self, v, c=""): self._emit('INC', 'ABS', v, c)
    def DEC_ZP(self, v, c=""):  self._emit('DEC', 'ZP',  v, c)

    # Bit test
    def BIT_ABS(self, v, c=""): self._emit('BIT', 'ABS', v, c)

    # Jump / Call
    def JMP(self, target, c=""):
        self._emit('JMP', 'ABS', target, c)
    def JSR(self, target, c=""):
        self._emit('JSR', 'ABS', target, c)

    # Branches (target = label str)
    def BEQ(self, t, c=""): self._emit('BEQ', 'REL', t, c)
    def BNE(self, t, c=""): self._emit('BNE', 'REL', t, c)
    def BCC(self, t, c=""): self._emit('BCC', 'REL', t, c)
    def BCS(self, t, c=""): self._emit('BCS', 'REL', t, c)
    def BPL(self, t, c=""): self._emit('BPL', 'REL', t, c)
    def BMI(self, t, c=""): self._emit('BMI', 'REL', t, c)

    # Raw bytes (data)
    def db(self, *vals, c=""):
        for v in vals:
            instr = Instr('.db', 'IMP', v, 1, self._cur_addr(), c)
            self._instrs.append(instr)
            c = ""  # only first byte gets the comment

    # ---- ビルド ----

    def build(self) -> bytes:
        """ラベルを解決してバイト列を返す。"""
        out = []
        for instr in self._instrs:
            if instr.mnemonic == '.db':
                out.append(instr.operand & 0xFF)
                continue

            # オペコードを検索
            opcode = None
            for byte, (mn, md, length, _) in OPCODES.items():
                if mn == instr.mnemonic and md == instr.mode:
                    opcode = byte
                    break
            if opcode is None:
                raise ValueError(f"オペコード未解決: {instr.mnemonic} {instr.mode} @ ${instr.addr:04X}")

            out.append(opcode)

            if instr.length == 1:
                pass
            elif instr.length == 2:
                op = instr.operand
                if instr.mode == 'REL':
                    if isinstance(op, str):
                        target = self._labels[op]
                        off = calc_branch_offset(instr.addr, target)
                    else:
                        off = op & 0xFF
                    out.append(off)
                else:
                    out.append(op & 0xFF)
            elif instr.length == 3:
                op = instr.operand
                if isinstance(op, str):
                    op = self._labels[op]
                out.append(op & 0xFF)
                out.append((op >> 8) & 0xFF)

        return bytes(out)

    # ---- テキスト出力 ----

    def print_txt(self, file=None):
        """アノテーション付きヘックスダンプを出力する。"""
        if file is None:
            file = sys.stdout

        sec_map = {idx: name for idx, name in self._sections}
        buf = self.build()
        pos = 0

        for i, instr in enumerate(self._instrs):
            if i in sec_map:
                print(f"\n# {'=' * 56}", file=file)
                print(f"# {sec_map[i]}", file=file)
                print(f"# {'=' * 56}", file=file)

            # ラベル表示
            for name, addr in self._labels.items():
                if addr == instr.addr:
                    print(f"# ${addr:04X} {name}:", file=file)

            raw_bytes = buf[pos:pos + instr.length]
            hex_str = ' '.join(f'{b:02X}' for b in raw_bytes)

            if instr.mnemonic == '.db':
                line = f"{hex_str:<9}   # .db ${instr.operand:02X}"
            elif instr.mode == 'REL':
                if isinstance(instr.operand, str):
                    target = self._labels[instr.operand]
                    off = buf[pos + 1]
                    signed = off if off < 0x80 else off - 0x100
                    line = f"{hex_str:<9}   # {instr.mnemonic} → ${target:04X}  ({signed:+d})"
                else:
                    line = f"{hex_str:<9}   # {instr.mnemonic} {instr.operand:+d}"
            elif instr.mode == 'IMP' or instr.mode == 'ACC':
                line = f"{hex_str:<9}   # {instr.mnemonic}"
            elif instr.mode == 'IMM':
                line = f"{hex_str:<9}   # {instr.mnemonic} #${instr.operand:02X}"
            elif instr.mode in ('ZP', 'ZPX', 'ZPY'):
                suffix = {'ZP': '', 'ZPX': ',X', 'ZPY': ',Y'}[instr.mode]
                line = f"{hex_str:<9}   # {instr.mnemonic} ${instr.operand:02X}{suffix}"
            elif instr.mode in ('ABS', 'ABX', 'ABY'):
                suffix = {'ABS': '', 'ABX': ',X', 'ABY': ',Y'}[instr.mode]
                op = self._labels.get(instr.operand, instr.operand) if isinstance(instr.operand, str) else instr.operand
                line = f"{hex_str:<9}   # {instr.mnemonic} ${op:04X}{suffix}"
            else:
                line = f"{hex_str:<9}   # {instr.mnemonic}"

            if instr.comment:
                line += f"   ({instr.comment})"
            print(line, file=file)
            pos += instr.length
