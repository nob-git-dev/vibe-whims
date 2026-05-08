/// カートリッジマッパーの共通インターフェース
pub trait Mapper: Send + Sync {
    fn read_prg(&self, addr: u16) -> u8;
    fn write_prg(&mut self, addr: u16, val: u8);
    fn read_chr(&self, addr: u16) -> u8;
    fn write_chr(&mut self, addr: u16, val: u8);
}

/// Mapper 0 (NROM)
/// - PRG-ROM 16KB: $8000-$BFFF にマップ、$C000-$FFFF はミラー
/// - PRG-ROM 32KB: $8000-$FFFF にマップ
/// - CHR-ROM 8KB: $0000-$1FFF にマップ
pub struct Mapper0 {
    prg_rom: Vec<u8>,
    chr_rom: Vec<u8>,
    chr_ram: Vec<u8>, // CHR-ROM が 0 の場合は CHR-RAM を使用
}

impl Mapper0 {
    pub fn new(prg_rom: Vec<u8>, chr_rom: Vec<u8>) -> Self {
        let chr_ram = if chr_rom.is_empty() {
            vec![0u8; 8192]
        } else {
            Vec::new()
        };
        Self {
            prg_rom,
            chr_rom,
            chr_ram,
        }
    }
}

impl Mapper for Mapper0 {
    fn read_prg(&self, addr: u16) -> u8 {
        if addr < 0x8000 {
            return 0;
        }
        let offset = (addr - 0x8000) as usize;
        if self.prg_rom.len() == 16384 {
            // 16KB: ミラー
            self.prg_rom[offset % 16384]
        } else {
            // 32KB
            let idx = offset % self.prg_rom.len();
            self.prg_rom[idx]
        }
    }

    fn write_prg(&mut self, _addr: u16, _val: u8) {
        // NROM は PRG-ROM への書き込みを無視する
    }

    fn read_chr(&self, addr: u16) -> u8 {
        let offset = addr as usize;
        if !self.chr_rom.is_empty() {
            if offset < self.chr_rom.len() {
                self.chr_rom[offset]
            } else {
                0
            }
        } else {
            if offset < self.chr_ram.len() {
                self.chr_ram[offset]
            } else {
                0
            }
        }
    }

    fn write_chr(&mut self, addr: u16, val: u8) {
        // CHR-RAM がある場合のみ書き込み可能
        if self.chr_rom.is_empty() {
            let offset = addr as usize;
            if offset < self.chr_ram.len() {
                self.chr_ram[offset] = val;
            }
        }
    }
}

/// マッパー番号からマッパーを生成するファクトリ
pub fn create_mapper(
    mapper_number: u8,
    prg_rom: Vec<u8>,
    chr_rom: Vec<u8>,
) -> Result<Box<dyn Mapper>, String> {
    match mapper_number {
        0 => Ok(Box::new(Mapper0::new(prg_rom, chr_rom))),
        n => Err(format!("Unsupported mapper: {}", n)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_prg_16kb() -> Vec<u8> {
        let mut prg = vec![0u8; 16384];
        // RESET ベクタを $8000 に設定
        prg[0x3FFC] = 0x00; // lo
        prg[0x3FFD] = 0x80; // hi -> $8000
        prg
    }

    fn make_prg_32kb() -> Vec<u8> {
        let mut prg = vec![0u8; 32768];
        prg[0x7FFC] = 0x00; // lo
        prg[0x7FFD] = 0x80; // hi -> $8000
        prg
    }

    fn make_chr_8kb() -> Vec<u8> {
        let mut chr = vec![0u8; 8192];
        chr[0] = 0xAA;
        chr[8191] = 0x55;
        chr
    }

    #[test]
    fn test_mapper0_read_prg_16kb() {
        let mut prg = make_prg_16kb();
        prg[0] = 0xAB; // $8000
        prg[0x3FFE] = 0xCD; // $BFFE
        let mapper = Mapper0::new(prg, make_chr_8kb());

        assert_eq!(mapper.read_prg(0x8000), 0xAB, "$8000 should read PRG[0]");
        assert_eq!(mapper.read_prg(0xBFFE), 0xCD, "$BFFE should read PRG[0x3FFE]");
    }

    #[test]
    fn test_mapper0_mirror_16kb() {
        let mut prg = make_prg_16kb();
        prg[0] = 0x42;
        let mapper = Mapper0::new(prg, make_chr_8kb());

        // $C000-$FFFF は $8000-$BFFF のミラー
        assert_eq!(mapper.read_prg(0x8000), mapper.read_prg(0xC000), "$8000 == $C000 (mirror)");
        assert_eq!(mapper.read_prg(0x8000), 0x42);
        assert_eq!(mapper.read_prg(0xC000), 0x42);
    }

    #[test]
    fn test_mapper0_read_prg_32kb() {
        let mut prg = make_prg_32kb();
        prg[0] = 0x11;      // $8000
        prg[0x4000] = 0x22; // $C000
        let mapper = Mapper0::new(prg, make_chr_8kb());

        assert_eq!(mapper.read_prg(0x8000), 0x11, "$8000 should read PRG[0]");
        assert_eq!(mapper.read_prg(0xC000), 0x22, "$C000 should read PRG[0x4000]");
    }

    #[test]
    fn test_mapper0_no_mirror_32kb() {
        let mut prg = make_prg_32kb();
        prg[0] = 0x11;
        prg[0x4000] = 0x22;
        let mapper = Mapper0::new(prg, make_chr_8kb());

        // 32KB では $8000 と $C000 は別アドレスを指す
        assert_ne!(mapper.read_prg(0x8000), mapper.read_prg(0xC000));
    }

    #[test]
    fn test_mapper0_read_chr() {
        let mapper = Mapper0::new(make_prg_16kb(), make_chr_8kb());
        assert_eq!(mapper.read_chr(0x0000), 0xAA, "CHR[0] should be 0xAA");
        assert_eq!(mapper.read_chr(0x1FFF), 0x55, "CHR[8191] should be 0x55");
    }

    #[test]
    fn test_mapper0_chr_ram_when_no_chr_rom() {
        let mut mapper = Mapper0::new(make_prg_16kb(), vec![]);
        // CHR-RAM への書き込みと読み取り
        mapper.write_chr(0x0010, 0x77);
        assert_eq!(mapper.read_chr(0x0010), 0x77, "CHR-RAM write/read should work");
    }

    #[test]
    fn test_mapper0_write_prg_noop() {
        let prg = make_prg_16kb();
        let original = prg[0];
        let mut mapper = Mapper0::new(prg, make_chr_8kb());
        mapper.write_prg(0x8000, 0xFF); // 書き込みは無視されるべき
        assert_eq!(mapper.read_prg(0x8000), original, "PRG-ROM write should be ignored");
    }

    #[test]
    fn test_create_mapper_mapper0() {
        let result = create_mapper(0, make_prg_16kb(), make_chr_8kb());
        assert!(result.is_ok(), "Mapper 0 should be supported");
    }

    #[test]
    fn test_create_mapper_unsupported() {
        let result = create_mapper(1, make_prg_16kb(), make_chr_8kb());
        assert!(result.is_err(), "Mapper 1 should not be supported");
    }
}
