/// iNES ROM ファイルのパース結果
#[derive(Debug, Clone, PartialEq)]
pub struct RomData {
    pub prg_rom: Vec<u8>,
    pub chr_rom: Vec<u8>,
    pub mapper_number: u8,
    pub mirroring: Mirroring,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Mirroring {
    Horizontal,
    Vertical,
    FourScreen,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ParseError {
    InvalidMagic,
    TooShort,
    InvalidData(String),
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ParseError::InvalidMagic => write!(f, "Invalid iNES magic bytes"),
            ParseError::TooShort => write!(f, "ROM data too short"),
            ParseError::InvalidData(msg) => write!(f, "Invalid ROM data: {}", msg),
        }
    }
}

/// iNES ヘッダーをパースし RomData を返す純粋関数
pub fn parse(bytes: &[u8]) -> Result<RomData, ParseError> {
    // iNES ヘッダーは最低 16 バイト
    if bytes.len() < 16 {
        return Err(ParseError::TooShort);
    }

    // マジックバイト確認: "NES\x1A"
    if &bytes[0..4] != b"NES\x1A" {
        return Err(ParseError::InvalidMagic);
    }

    let prg_rom_banks = bytes[4] as usize; // 16KB 単位
    let chr_rom_banks = bytes[5] as usize; // 8KB 単位
    let flags6 = bytes[6];
    let flags7 = bytes[7];

    // マッパー番号: flags6 の上位 4bit + flags7 の上位 4bit
    let mapper_number = (flags7 & 0xF0) | (flags6 >> 4);

    // ミラーリング
    let mirroring = if flags6 & 0x08 != 0 {
        Mirroring::FourScreen
    } else if flags6 & 0x01 != 0 {
        Mirroring::Vertical
    } else {
        Mirroring::Horizontal
    };

    // トレーナーが存在する場合はスキップ（flags6 bit2）
    let trainer_size = if flags6 & 0x04 != 0 { 512 } else { 0 };

    let prg_rom_size = prg_rom_banks * 16384; // 16KB per bank
    let chr_rom_size = chr_rom_banks * 8192;  // 8KB per bank

    let prg_start = 16 + trainer_size;
    let chr_start = prg_start + prg_rom_size;

    if bytes.len() < chr_start + chr_rom_size {
        return Err(ParseError::TooShort);
    }

    let prg_rom = bytes[prg_start..prg_start + prg_rom_size].to_vec();
    let chr_rom = bytes[chr_start..chr_start + chr_rom_size].to_vec();

    Ok(RomData {
        prg_rom,
        chr_rom,
        mapper_number,
        mirroring,
    })
}

/// テスト用: 最小有効 iNES バイト列を生成する
#[cfg(test)]
pub fn make_test_rom(prg_banks: u8, chr_banks: u8, mapper: u8, flags6_extra: u8) -> Vec<u8> {
    let prg_size = prg_banks as usize * 16384;
    let chr_size = chr_banks as usize * 8192;
    let flags6 = (mapper << 4) | flags6_extra;
    let flags7 = mapper & 0xF0;

    let mut rom = vec![0u8; 16 + prg_size + chr_size];
    rom[0] = b'N';
    rom[1] = b'E';
    rom[2] = b'S';
    rom[3] = 0x1A;
    rom[4] = prg_banks;
    rom[5] = chr_banks;
    rom[6] = flags6;
    rom[7] = flags7;
    rom
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_ines_valid_header() {
        let rom = make_test_rom(1, 1, 0, 0);
        let result = parse(&rom);
        assert!(result.is_ok(), "Valid ROM should parse successfully");
    }

    #[test]
    fn test_parse_ines_16kb() {
        let rom = make_test_rom(1, 1, 0, 0);
        let data = parse(&rom).unwrap();
        assert_eq!(data.prg_rom.len(), 16384, "PRG-ROM should be 16KB");
        assert_eq!(data.chr_rom.len(), 8192, "CHR-ROM should be 8KB");
    }

    #[test]
    fn test_parse_ines_32kb() {
        let rom = make_test_rom(2, 1, 0, 0);
        let data = parse(&rom).unwrap();
        assert_eq!(data.prg_rom.len(), 32768, "PRG-ROM should be 32KB");
    }

    #[test]
    fn test_parse_ines_invalid_magic() {
        let mut rom = make_test_rom(1, 1, 0, 0);
        rom[0] = 0x00; // 不正なマジックバイト
        let result = parse(&rom);
        assert_eq!(result, Err(ParseError::InvalidMagic));
    }

    #[test]
    fn test_parse_ines_too_short() {
        let short = vec![0u8; 10];
        let result = parse(&short);
        assert_eq!(result, Err(ParseError::TooShort));
    }

    #[test]
    fn test_parse_ines_mapper_number() {
        // Mapper 1 (MMC1) のテスト
        let rom = make_test_rom(1, 1, 1, 0);
        let data = parse(&rom).unwrap();
        assert_eq!(data.mapper_number, 1);
    }

    #[test]
    fn test_parse_ines_mapper0() {
        let rom = make_test_rom(1, 1, 0, 0);
        let data = parse(&rom).unwrap();
        assert_eq!(data.mapper_number, 0);
    }

    #[test]
    fn test_parse_ines_mirroring_horizontal() {
        let rom = make_test_rom(1, 1, 0, 0x00); // bit0=0: horizontal
        let data = parse(&rom).unwrap();
        assert_eq!(data.mirroring, Mirroring::Horizontal);
    }

    #[test]
    fn test_parse_ines_mirroring_vertical() {
        let rom = make_test_rom(1, 1, 0, 0x01); // bit0=1: vertical
        let data = parse(&rom).unwrap();
        assert_eq!(data.mirroring, Mirroring::Vertical);
    }

    #[test]
    fn test_parse_ines_mirroring_four_screen() {
        let rom = make_test_rom(1, 1, 0, 0x08); // bit3=1: four-screen
        let data = parse(&rom).unwrap();
        assert_eq!(data.mirroring, Mirroring::FourScreen);
    }

    #[test]
    fn test_parse_prg_rom_content() {
        let mut rom = make_test_rom(1, 1, 0, 0);
        // PRG-ROM の先頭バイトに識別値を書き込む
        rom[16] = 0xAB;
        rom[17] = 0xCD;
        let data = parse(&rom).unwrap();
        assert_eq!(data.prg_rom[0], 0xAB);
        assert_eq!(data.prg_rom[1], 0xCD);
    }

    #[test]
    fn test_parse_chr_rom_content() {
        let mut rom = make_test_rom(1, 1, 0, 0);
        // CHR-ROM の先頭バイト (16 + 16384 = 16400)
        rom[16400] = 0x55;
        let data = parse(&rom).unwrap();
        assert_eq!(data.chr_rom[0], 0x55);
    }
}
