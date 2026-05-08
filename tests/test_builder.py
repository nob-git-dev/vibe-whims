"""tests/test_builder.py — builder.py のテスト (Red→Green)"""
import pytest
from domain.builder import build, BuildError

# テスト用の最小セクション辞書ヘルパー
VALID_HEADER = [0x4E, 0x45, 0x53, 0x1A, 0x01, 0x01, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
VALID_VECTORS = [0x50, 0x82, 0x00, 0x80, 0x80, 0x82]


def minimal_sections(
    header=None, prg_rom=None, chr_rom=None, vectors=None
) -> dict:
    return {
        "header": header if header is not None else VALID_HEADER[:],
        "prg_rom": prg_rom if prg_rom is not None else [0x78, 0xD8],
        "chr_rom": chr_rom if chr_rom is not None else [],
        "vectors": vectors if vectors is not None else VALID_VECTORS[:],
    }


# ---------------------------------------------------------------------------
# 正常系
# ---------------------------------------------------------------------------

class TestBuilderNormalCases:
    def test_builder_ines_magic(self):
        """生成バイナリの先頭 4 バイトが iNES マジック (4E 45 53 1A) であること"""
        result = build(minimal_sections())
        assert result[0:4] == bytes([0x4E, 0x45, 0x53, 0x1A])

    def test_builder_output_size(self):
        """生成バイナリが 24592 バイト (16 + 16384 + 8192) であること"""
        result = build(minimal_sections())
        assert len(result) == 16 + 16384 + 8192

    def test_builder_prg_padding(self):
        """prg_rom が 16384 バイトにゼロパディングされること"""
        sections = minimal_sections(prg_rom=[0x78, 0xD8])
        result = build(sections)
        prg = result[16:16 + 16384]
        assert len(prg) == 16384
        assert prg[0] == 0x78
        assert prg[1] == 0xD8
        # パディング部分はゼロ（ベクタで上書きされる末尾6バイト以外）
        assert all(b == 0x00 for b in prg[2:16378])

    def test_builder_chr_padding(self):
        """chr_rom が 8192 バイトにゼロパディングされること"""
        sections = minimal_sections(chr_rom=[0xFF, 0x00])
        result = build(sections)
        chr_data = result[16 + 16384:]
        assert len(chr_data) == 8192
        assert chr_data[0] == 0xFF
        assert chr_data[1] == 0x00
        assert all(b == 0x00 for b in chr_data[2:])

    def test_builder_vectors_placement(self):
        """vectors (6 バイト) が prg_rom 末尾 6 バイト（オフセット 16378〜16383）に配置されること"""
        vectors = [0x50, 0x82, 0x00, 0x80, 0x80, 0x82]
        sections = minimal_sections(vectors=vectors)
        result = build(sections)
        prg = result[16:16 + 16384]
        assert list(prg[16378:16384]) == vectors

    def test_builder_header_is_exact(self):
        """header バイト列がそのまま先頭 16 バイトに配置されること"""
        sections = minimal_sections()
        result = build(sections)
        assert list(result[0:16]) == VALID_HEADER

    def test_builder_deterministic(self):
        """同じ入力から毎回同一のバイト列が生成されること（再現性）"""
        sections = minimal_sections()
        result1 = build(sections)
        result2 = build(sections)
        assert result1 == result2

    def test_builder_prg_rom_full_size_no_padding(self):
        """prg_rom がちょうど 16384 バイトのときパディングなしで受け入れること"""
        prg = [0x00] * 16384
        sections = minimal_sections(prg_rom=prg)
        result = build(sections)
        assert len(result) == 24592

    def test_builder_vectors_overwrite_prg_tail(self):
        """prg_rom の末尾 6 バイトが vectors で上書きされること（prg に元の値があっても）"""
        prg = [0xEA] * 16384  # 全バイト NOP (0xEA)
        vectors = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66]
        sections = minimal_sections(prg_rom=prg, vectors=vectors)
        result = build(sections)
        prg_out = result[16:16 + 16384]
        # 末尾 6 バイトが vectors で上書きされていること
        assert list(prg_out[16378:16384]) == vectors
        # 末尾 6 バイト以外は元の NOP
        assert all(b == 0xEA for b in prg_out[:16378])


# ---------------------------------------------------------------------------
# エラー系
# ---------------------------------------------------------------------------

class TestBuilderErrorCases:
    def test_builder_invalid_header_length(self):
        """header が 16 バイト以外のとき BuildError が送出されること"""
        sections = minimal_sections(header=[0x4E, 0x45, 0x53, 0x1A])
        with pytest.raises(BuildError):
            build(sections)

    def test_builder_invalid_magic(self):
        """header のマジックバイトが不一致のとき BuildError が送出されること"""
        bad_header = [0xFF] * 16
        sections = minimal_sections(header=bad_header)
        with pytest.raises(BuildError):
            build(sections)

    def test_builder_prg_overflow(self):
        """prg_rom が 16384 バイト超のとき BuildError が送出されること"""
        prg = [0x00] * 16385
        sections = minimal_sections(prg_rom=prg)
        with pytest.raises(BuildError):
            build(sections)

    def test_builder_chr_overflow(self):
        """chr_rom が 8192 バイト超のとき BuildError が送出されること"""
        chr_data = [0x00] * 8193
        sections = minimal_sections(chr_rom=chr_data)
        with pytest.raises(BuildError):
            build(sections)

    def test_builder_invalid_vectors_length_short(self):
        """vectors が 6 バイト未満のとき BuildError が送出されること"""
        sections = minimal_sections(vectors=[0x00, 0x80])
        with pytest.raises(BuildError):
            build(sections)

    def test_builder_invalid_vectors_length_long(self):
        """vectors が 6 バイト超のとき BuildError が送出されること"""
        sections = minimal_sections(vectors=[0x00] * 7)
        with pytest.raises(BuildError):
            build(sections)

    def test_builder_missing_section_raises(self):
        """必須セクション欠損のとき BuildError が送出されること"""
        sections = {
            "header": VALID_HEADER[:],
            "prg_rom": [0x78],
            # chr_rom と vectors が欠落
        }
        with pytest.raises(BuildError):
            build(sections)
