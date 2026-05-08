"""domain/parser.py — game.rom.txt テキスト → セクション辞書 への変換

入力: game.rom.txt の内容（文字列）
出力: dict[str, list[int]]  { "header", "prg_rom", "chr_rom", "vectors" }

処理規則:
  - 空行・`#` で始まる行は無視
  - `[section_name]` でカレントセクションを切り替える
  - 未知のセクション名は ParseError
  - データ行: `#` 以前を取り出し空白区切りでトークン化、各トークンを 16 進数に変換
  - 変換失敗・範囲外は ParseError
  - セクション宣言前のデータ行は ParseError
"""

KNOWN_SECTIONS = {"header", "prg_rom", "chr_rom", "vectors"}


class ParseError(Exception):
    """game.rom.txt のパースに失敗したとき送出される例外"""


def parse(text: str) -> dict[str, list[int]]:
    """game.rom.txt のテキストを解析してセクション辞書を返す。

    Args:
        text: game.rom.txt の内容（文字列）

    Returns:
        dict[str, list[int]]: セクション名 → バイト列の辞書

    Raises:
        ParseError: 解析に失敗した場合
    """
    sections: dict[str, list[int]] = {
        "header": [],
        "prg_rom": [],
        "chr_rom": [],
        "vectors": [],
    }
    current_section: str | None = None

    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()

        # 空行を無視
        if not line:
            continue

        # コメント行（# で始まる行）を無視
        if line.startswith("#"):
            continue

        # セクションヘッダー
        if line.startswith("["):
            # `[section_name]` または `[section_name]  # comment` の形式
            section_part = line.split("#")[0].strip()
            if not section_part.endswith("]"):
                raise ParseError(
                    f"行 {lineno}: 不正なセクションヘッダー形式: {raw_line!r}"
                )
            section_name = section_part[1:-1].strip()
            if section_name not in KNOWN_SECTIONS:
                raise ParseError(
                    f"行 {lineno}: 未知のセクション名 [{section_name!r}]。"
                    f"認識されるセクション: {sorted(KNOWN_SECTIONS)}"
                )
            current_section = section_name
            continue

        # データ行
        if current_section is None:
            raise ParseError(
                f"行 {lineno}: セクション宣言の前にデータ行が出現しました: {raw_line!r}"
            )

        # `#` より前の部分だけを取り出す
        data_part = line.split("#")[0].strip()
        if not data_part:
            # `  # comment` のような行（実質コメント行）
            continue

        tokens = data_part.split()
        for token in tokens:
            try:
                value = int(token, 16)
            except ValueError:
                raise ParseError(
                    f"行 {lineno}: 不正な16進数トークン {token!r}: {raw_line!r}"
                )
            if not (0 <= value <= 255):
                raise ParseError(
                    f"行 {lineno}: バイト値 {value} (0x{value:X}) が範囲外 (0〜255): {raw_line!r}"
                )
            sections[current_section].append(value)

    return sections
