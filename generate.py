#!/usr/bin/env python3
"""generate.py — CLI エントリポイント（presentation 層）

使い方:
    python3 generate.py [input] [output]

デフォルト:
    input:  game.rom.txt
    output: game.nes

エラー時は stderr に出力して exit(1)。
subprocess・アセンブラ・コンパイラは一切使用しない（固定要件）。
"""
import sys
from pathlib import Path

from domain.parser import parse, ParseError
from domain.builder import build, BuildError


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    input_path = Path(args[0]) if len(args) >= 1 else Path("game.rom.txt")
    output_path = Path(args[1]) if len(args) >= 2 else Path("game.nes")

    # 入力ファイルの読み込み
    try:
        text = input_path.read_text(encoding="utf-8")
    except FileNotFoundError:
        print(f"エラー: 入力ファイルが見つかりません: {input_path}", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"エラー: 入力ファイルを読めません: {e}", file=sys.stderr)
        return 1

    # パース（presentation → domain）
    try:
        sections = parse(text)
    except ParseError as e:
        print(f"パースエラー: {e}", file=sys.stderr)
        return 1

    # ビルド（domain のみ。ファイル I/O なし）
    try:
        rom_bytes = build(sections)
    except BuildError as e:
        print(f"ビルドエラー: {e}", file=sys.stderr)
        return 1

    # 出力ファイルの書き込み
    try:
        output_path.write_bytes(rom_bytes)
    except OSError as e:
        print(f"エラー: 出力ファイルを書けません: {e}", file=sys.stderr)
        return 1

    print(f"{input_path} → {output_path} ({len(rom_bytes)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
