"""domain/builder.py — セクション辞書 → iNES バイト列 への変換

入力: parser.parse() の出力 dict[str, list[int]]
出力: bytes（iNES 形式）

処理:
  1. header 16 バイトをそのまま先頭に配置
  2. prg_rom を 16384 バイトにゼロパディング（末尾）
  3. vectors 6 バイトを prg_rom 末尾 6 バイトに上書き
  4. chr_rom を 8192 バイトにゼロパディング（末尾）
  5. 結合: header(16) + prg_rom(16384) + chr_rom(8192) = 24592 バイト

アセンブラ・コンパイラ・subprocess の使用禁止（固定要件）
"""

INES_MAGIC = [0x4E, 0x45, 0x53, 0x1A]
PRG_ROM_SIZE = 16384   # NROM-128: 16KB
CHR_ROM_SIZE = 8192    # CHR: 8KB
HEADER_SIZE = 16
VECTORS_SIZE = 6
TOTAL_SIZE = HEADER_SIZE + PRG_ROM_SIZE + CHR_ROM_SIZE  # = 24592


class BuildError(Exception):
    """iNES バイナリ構築に失敗したとき送出される例外"""


def build(sections: dict) -> bytes:
    """セクション辞書から iNES バイト列を構築して返す。

    Args:
        sections: parser.parse() が返す辞書
                  { "header": list[int], "prg_rom": list[int],
                    "chr_rom": list[int], "vectors": list[int] }

    Returns:
        bytes: 24592 バイトの iNES 形式バイナリ

    Raises:
        BuildError: バリデーション失敗時
    """
    _validate(sections)

    header = sections["header"]
    prg_rom = list(sections["prg_rom"])
    chr_rom = list(sections["chr_rom"])
    vectors = sections["vectors"]

    # prg_rom を 16384 バイトにゼロパディング
    prg_padded = prg_rom + [0x00] * (PRG_ROM_SIZE - len(prg_rom))

    # vectors 6 バイトを prg_rom 末尾 6 バイトに上書き
    # prg_padded[16378:16384] = vectors
    for i, v in enumerate(vectors):
        prg_padded[PRG_ROM_SIZE - VECTORS_SIZE + i] = v

    # chr_rom を 8192 バイトにゼロパディング
    chr_padded = chr_rom + [0x00] * (CHR_ROM_SIZE - len(chr_rom))

    # 結合して bytes を返す
    raw = header + prg_padded + chr_padded
    assert len(raw) == TOTAL_SIZE, f"予期しないバイナリサイズ: {len(raw)}"
    return bytes(raw)


def _validate(sections: dict) -> None:
    """セクション辞書のバリデーションを行う。

    Raises:
        BuildError: バリデーション失敗時
    """
    required = {"header", "prg_rom", "chr_rom", "vectors"}
    missing = required - sections.keys()
    if missing:
        raise BuildError(f"必須セクションが欠落しています: {sorted(missing)}")

    header = sections["header"]
    if len(header) != HEADER_SIZE:
        raise BuildError(
            f"header は {HEADER_SIZE} バイトでなければなりません。実際: {len(header)} バイト"
        )

    if list(header[0:4]) != INES_MAGIC:
        raise BuildError(
            f"header の先頭 4 バイトが iNES マジック {INES_MAGIC!r} と一致しません。"
            f"実際: {list(header[0:4])!r}"
        )

    prg_rom = sections["prg_rom"]
    if len(prg_rom) > PRG_ROM_SIZE:
        raise BuildError(
            f"prg_rom が {PRG_ROM_SIZE} バイトを超えています。実際: {len(prg_rom)} バイト"
        )

    chr_rom = sections["chr_rom"]
    if len(chr_rom) > CHR_ROM_SIZE:
        raise BuildError(
            f"chr_rom が {CHR_ROM_SIZE} バイトを超えています。実際: {len(chr_rom)} バイト"
        )

    vectors = sections["vectors"]
    if len(vectors) != VECTORS_SIZE:
        raise BuildError(
            f"vectors は {VECTORS_SIZE} バイトでなければなりません。実際: {len(vectors)} バイト"
        )
