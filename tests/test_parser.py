"""tests/test_parser.py — parser.py のテスト (Red→Green)"""
import pytest
from domain.parser import parse, ParseError


# ---------------------------------------------------------------------------
# 正常系
# ---------------------------------------------------------------------------

class TestParserNormalCases:
    def test_parser_sections_present(self):
        """4 セクションが正しく返ること"""
        text = """
[header]
4E 45 53 1A 01 01 00 00  # iNES magic + PRG/CHR banks
00 00 00 00 00 00 00 00  # padding

[prg_rom]
78 D8  # SEI / CLD

[chr_rom]
00 00  # blank tile data

[vectors]
50 82 00 80 80 82  # NMI / RESET / IRQ vectors
"""
        result = parse(text)
        assert "header" in result
        assert "prg_rom" in result
        assert "chr_rom" in result
        assert "vectors" in result

    def test_parser_valid_line_format(self):
        """コメント付き行が正しくパースされること"""
        text = """
[header]
4E 45 53 1A 01 01 00 00  # comment here
00 00 00 00 00 00 00 00  # more padding

[prg_rom]
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        result = parse(text)
        assert result["header"] == [
            0x4E, 0x45, 0x53, 0x1A, 0x01, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]

    def test_parser_ignores_empty_lines(self):
        """空行が無視されること"""
        text = """
[header]

4E 45 53 1A 01 01 00 00

00 00 00 00 00 00 00 00

[prg_rom]
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        result = parse(text)
        assert len(result["header"]) == 16

    def test_parser_ignores_comment_lines(self):
        """# で始まる行が無視されること"""
        text = """
# このファイルは正本です
[header]
# ヘッダーは16バイト
4E 45 53 1A 01 01 00 00
00 00 00 00 00 00 00 00
[prg_rom]
# PRG ROM セクション
78  # SEI
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        result = parse(text)
        assert result["header"][0] == 0x4E
        assert result["prg_rom"] == [0x78]

    def test_parser_lowercase_hex(self):
        """小文字16進数も受け付けること"""
        text = """
[header]
4e 45 53 1a 01 01 00 00
00 00 00 00 00 00 00 00
[prg_rom]
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        result = parse(text)
        assert result["header"][0] == 0x4E

    def test_parser_multiple_bytes_per_line(self):
        """1行に複数バイトを記述できること"""
        text = """
[header]
4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00
[prg_rom]
78 D8 A9 00  # SEI CLD LDA #$00
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        result = parse(text)
        assert result["prg_rom"] == [0x78, 0xD8, 0xA9, 0x00]

    def test_parser_empty_sections(self):
        """空セクションが空リストを返すこと"""
        text = """
[header]
4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00
[prg_rom]
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        result = parse(text)
        assert result["prg_rom"] == []
        assert result["chr_rom"] == []

    def test_parser_vectors_6bytes(self):
        """vectors セクションが正しく 6 バイトのリストとして返ること"""
        text = """
[header]
4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00
[prg_rom]
[chr_rom]
[vectors]
50 82 00 80 80 82  # NMI=8250, RESET=8000, IRQ=8280
"""
        result = parse(text)
        assert result["vectors"] == [0x50, 0x82, 0x00, 0x80, 0x80, 0x82]


# ---------------------------------------------------------------------------
# エラー系
# ---------------------------------------------------------------------------

class TestParserErrorCases:
    def test_parser_invalid_hex(self):
        """不正なヘックス値で ParseError が送出されること"""
        text = """
[header]
4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00
[prg_rom]
ZZ  # 不正な値
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        with pytest.raises(ParseError):
            parse(text)

    def test_parser_unknown_section(self):
        """未知のセクション名で ParseError が送出されること"""
        text = """
[header]
4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00
[unknown_section]
00 01 02
[prg_rom]
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        with pytest.raises(ParseError):
            parse(text)

    def test_parser_byte_out_of_range(self):
        """0〜255 範囲外のバイト値で ParseError が送出されること"""
        text = """
[header]
4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 FF
[prg_rom]
100  # 256 は範囲外（16進で 0x100 = 256）
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        with pytest.raises(ParseError):
            parse(text)

    def test_parser_data_before_any_section(self):
        """セクション宣言前にデータ行がある場合に ParseError が送出されること"""
        text = """
4E 45 53 1A  # セクションなしにデータ
[header]
4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00
[prg_rom]
[chr_rom]
[vectors]
00 00 00 00 00 00
"""
        with pytest.raises(ParseError):
            parse(text)
