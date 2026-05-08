use crate::infrastructure::mapper::{create_mapper, Mapper};
use crate::infrastructure::rom_parser::{parse, ParseError, RomData};

pub struct Cartridge {
    mapper: Box<dyn Mapper>,
    pub rom_data: RomData,
}

impl Cartridge {
    /// iNES バイト列からカートリッジを構築する
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, CartridgeError> {
        let rom_data = parse(bytes).map_err(CartridgeError::ParseError)?;
        let mapper = create_mapper(
            rom_data.mapper_number,
            rom_data.prg_rom.clone(),
            rom_data.chr_rom.clone(),
        )
        .map_err(CartridgeError::UnsupportedMapper)?;

        Ok(Cartridge { mapper, rom_data })
    }

    pub fn read_prg(&self, addr: u16) -> u8 {
        self.mapper.read_prg(addr)
    }

    pub fn write_prg(&mut self, addr: u16, val: u8) {
        self.mapper.write_prg(addr, val);
    }

    pub fn read_chr(&self, addr: u16) -> u8 {
        self.mapper.read_chr(addr)
    }

    pub fn write_chr(&mut self, addr: u16, val: u8) {
        self.mapper.write_chr(addr, val);
    }
}

#[derive(Debug)]
pub enum CartridgeError {
    ParseError(ParseError),
    UnsupportedMapper(String),
}

impl std::fmt::Display for CartridgeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CartridgeError::ParseError(e) => write!(f, "ROM parse error: {}", e),
            CartridgeError::UnsupportedMapper(msg) => write!(f, "Unsupported mapper: {}", msg),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infrastructure::rom_parser::make_test_rom;

    #[test]
    fn test_cartridge_from_valid_rom() {
        let rom_bytes = make_test_rom(1, 1, 0, 0);
        let cart = Cartridge::from_bytes(&rom_bytes);
        assert!(cart.is_ok(), "Valid NROM should create Cartridge successfully");
    }

    #[test]
    fn test_cartridge_prg_read() {
        let mut rom_bytes = make_test_rom(1, 1, 0, 0);
        rom_bytes[16] = 0xEA; // PRG-ROM の先頭バイト
        let cart = Cartridge::from_bytes(&rom_bytes).unwrap();
        assert_eq!(cart.read_prg(0x8000), 0xEA);
    }

    #[test]
    fn test_cartridge_chr_read() {
        let mut rom_bytes = make_test_rom(1, 1, 0, 0);
        rom_bytes[16 + 16384] = 0x55; // CHR-ROM の先頭バイト
        let cart = Cartridge::from_bytes(&rom_bytes).unwrap();
        assert_eq!(cart.read_chr(0x0000), 0x55);
    }

    #[test]
    fn test_cartridge_invalid_rom() {
        let bad_bytes = vec![0u8; 5];
        let result = Cartridge::from_bytes(&bad_bytes);
        assert!(result.is_err(), "Invalid ROM should return error");
    }
}
