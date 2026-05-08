/// NES PPU (Picture Processing Unit)
///
/// スキャンライン単位で描画を行い、フレームバッファ（256×240×4 RGBA）を生成する。
/// NMI 発火フラグを保持する。

/// NES システムパレット (64色 × RGB)
const NES_PALETTE: [(u8, u8, u8); 64] = [
    (84,  84,  84),  // 0x00
    (0,   30, 116),  // 0x01
    (8,   16, 144),  // 0x02
    (48,   0, 136),  // 0x03
    (68,   0, 100),  // 0x04
    (92,   0,  48),  // 0x05
    (84,   4,   0),  // 0x06
    (60,  24,   0),  // 0x07
    (32,  42,   0),  // 0x08
    (8,   58,   0),  // 0x09
    (0,   64,   0),  // 0x0A
    (0,   60,   0),  // 0x0B
    (0,   50,  60),  // 0x0C
    (0,    0,   0),  // 0x0D
    (0,    0,   0),  // 0x0E
    (0,    0,   0),  // 0x0F
    (152, 150, 152), // 0x10
    (8,   76, 196),  // 0x11
    (48,  50, 236),  // 0x12
    (92,  30, 228),  // 0x13
    (136,  20, 176), // 0x14
    (160,  20, 100), // 0x15
    (152,  34,  32), // 0x16
    (120,  60,   0), // 0x17
    (84,   90,   0), // 0x18
    (40,  114,   0), // 0x19
    (8,   124,   0), // 0x1A
    (0,   118,  40), // 0x1B
    (0,   102, 120), // 0x1C
    (0,    0,   0),  // 0x1D
    (0,    0,   0),  // 0x1E
    (0,    0,   0),  // 0x1F
    (236, 238, 236), // 0x20
    (76,  154, 236), // 0x21
    (120, 124, 236), // 0x22
    (176,  98, 236), // 0x23
    (228,  84, 236), // 0x24
    (236,  88, 180), // 0x25
    (236, 106, 100), // 0x26
    (212, 136,  32), // 0x27
    (160, 170,   0), // 0x28
    (116, 196,   0), // 0x29
    (76,  208,  32), // 0x2A
    (56,  204, 108), // 0x2B
    (56,  180, 204), // 0x2C
    (60,   60,  60), // 0x2D
    (0,    0,   0),  // 0x2E
    (0,    0,   0),  // 0x2F
    (236, 238, 236), // 0x30
    (168, 204, 236), // 0x31
    (188, 188, 236), // 0x32
    (212, 178, 236), // 0x33
    (236, 174, 236), // 0x34
    (236, 174, 212), // 0x35
    (236, 180, 176), // 0x36
    (228, 196, 144), // 0x37
    (204, 210, 120), // 0x38
    (180, 222, 120), // 0x39
    (168, 226, 144), // 0x3A
    (152, 226, 180), // 0x3B
    (160, 214, 228), // 0x3C
    (160, 162, 160), // 0x3D
    (0,    0,   0),  // 0x3E
    (0,    0,   0),  // 0x3F
];

/// PPU コントロールレジスタ $2000 のビット定義
pub mod ctrl_flags {
    pub const NAMETABLE_X: u8    = 0x01;
    pub const NAMETABLE_Y: u8    = 0x02;
    pub const VRAM_INCREMENT: u8 = 0x04;
    pub const SPRITE_TABLE: u8   = 0x08;
    pub const BG_TABLE: u8       = 0x10;
    pub const SPRITE_SIZE: u8    = 0x20;
    pub const MASTER_SLAVE: u8   = 0x40;
    pub const NMI_ENABLE: u8     = 0x80;
}

/// PPU マスクレジスタ $2001 のビット定義
pub mod mask_flags {
    pub const GREYSCALE: u8        = 0x01;
    pub const SHOW_BG_LEFT: u8     = 0x02;
    pub const SHOW_SPRITE_LEFT: u8 = 0x04;
    pub const SHOW_BG: u8          = 0x08;
    pub const SHOW_SPRITES: u8     = 0x10;
    pub const EMPHASIZE_R: u8      = 0x20;
    pub const EMPHASIZE_G: u8      = 0x40;
    pub const EMPHASIZE_B: u8      = 0x80;
}

/// PPU ステータスレジスタ $2002 のビット定義
pub mod status_flags {
    pub const SPRITE_OVERFLOW: u8 = 0x20;
    pub const SPRITE_ZERO_HIT: u8 = 0x40;
    pub const VBLANK: u8          = 0x80;
}

pub struct Ppu {
    // 内部レジスタ
    pub ctrl: u8,   // $2000
    pub mask: u8,   // $2001
    pub status: u8, // $2002
    pub oam_addr: u8, // $2003
    pub scroll_x: u8,
    pub scroll_y: u8,

    // VRAM (2KB ネームテーブル + パレット RAM)
    pub vram: [u8; 2048],
    pub palette: [u8; 32],
    pub oam: [u8; 256], // Object Attribute Memory

    // フレームバッファ (256×240×4 RGBA)
    pub frame_buffer: Box<[u8; 256 * 240 * 4]>,
    pub frame_ready: bool,

    // スキャンライン カウンター
    pub scanline: i32, // -1(プリレンダー)〜261
    pub dot: u32,      // 0〜340 (ピクセル位置)
    pub frame: u64,    // フレームカウンター

    // NMI 制御
    pub nmi_pending: bool,

    // 内部ラッチ
    vram_addr: u16,  // v レジスタ (現在の VRAM アドレス)
    temp_addr: u16,  // t レジスタ (一時 VRAM アドレス)
    fine_x: u8,      // X スクロールの下位 3bit
    write_latch: bool, // w レジスタ (2回書き込みラッチ)
    data_buffer: u8,   // 読み取りバッファ

    // CHR-ROM / CHR-RAM への参照（コールバック方式）
    // テスト・実装の単純化のため内部バッファとして保持する
    pub chr_data: Vec<u8>,
}

impl Ppu {
    pub fn new() -> Self {
        Self {
            ctrl: 0,
            mask: 0,
            status: 0,
            oam_addr: 0,
            scroll_x: 0,
            scroll_y: 0,
            vram: [0u8; 2048],
            palette: [0u8; 32],
            oam: [0u8; 256],
            frame_buffer: Box::new([0u8; 256 * 240 * 4]),
            frame_ready: false,
            scanline: -1,
            dot: 0,
            frame: 0,
            nmi_pending: false,
            vram_addr: 0,
            temp_addr: 0,
            fine_x: 0,
            write_latch: false,
            data_buffer: 0,
            chr_data: vec![0u8; 8192],
        }
    }

    /// CHR データを設定する
    pub fn load_chr(&mut self, data: &[u8]) {
        let len = data.len().min(self.chr_data.len());
        self.chr_data[..len].copy_from_slice(&data[..len]);
    }

    /// CPU からの PPU レジスタ読み取り
    pub fn read_register(&mut self, addr: u16) -> u8 {
        match addr {
            0x2002 => {
                let val = self.status;
                // VBlank フラグをクリア
                self.status &= !status_flags::VBLANK;
                self.write_latch = false;
                val
            }
            0x2004 => self.oam[self.oam_addr as usize],
            0x2007 => {
                let val = self.data_buffer;
                let vaddr = self.vram_addr & 0x3FFF;
                self.data_buffer = self.read_vram(vaddr);
                // パレット領域は遅延なし
                let result = if vaddr >= 0x3F00 { self.read_vram(vaddr) } else { val };
                // VRAM アドレスをインクリメント
                let inc = if self.ctrl & ctrl_flags::VRAM_INCREMENT != 0 { 32 } else { 1 };
                self.vram_addr = self.vram_addr.wrapping_add(inc);
                result
            }
            _ => 0,
        }
    }

    /// CPU からの PPU レジスタ書き込み
    pub fn write_register(&mut self, addr: u16, val: u8) {
        match addr {
            0x2000 => {
                self.ctrl = val;
                // t レジスタのネームテーブルビット更新
                self.temp_addr = (self.temp_addr & 0xF3FF) | (((val & 0x03) as u16) << 10);
            }
            0x2001 => {
                self.mask = val;
            }
            0x2003 => {
                self.oam_addr = val;
            }
            0x2004 => {
                self.oam[self.oam_addr as usize] = val;
                self.oam_addr = self.oam_addr.wrapping_add(1);
            }
            0x2005 => {
                if !self.write_latch {
                    // 1 回目: X スクロール
                    self.fine_x = val & 0x07;
                    self.temp_addr = (self.temp_addr & 0xFFE0) | ((val >> 3) as u16);
                } else {
                    // 2 回目: Y スクロール
                    self.temp_addr = (self.temp_addr & 0x8FFF) | (((val & 0x07) as u16) << 12);
                    self.temp_addr = (self.temp_addr & 0xFC1F) | (((val >> 3) as u16) << 5);
                }
                self.write_latch = !self.write_latch;
            }
            0x2006 => {
                if !self.write_latch {
                    // 1 回目: アドレス上位
                    self.temp_addr = (self.temp_addr & 0x00FF) | (((val & 0x3F) as u16) << 8);
                } else {
                    // 2 回目: アドレス下位
                    self.temp_addr = (self.temp_addr & 0xFF00) | (val as u16);
                    self.vram_addr = self.temp_addr;
                }
                self.write_latch = !self.write_latch;
            }
            0x2007 => {
                let vaddr = self.vram_addr & 0x3FFF;
                self.write_vram(vaddr, val);
                let inc = if self.ctrl & ctrl_flags::VRAM_INCREMENT != 0 { 32 } else { 1 };
                self.vram_addr = self.vram_addr.wrapping_add(inc);
            }
            0x4014 => {
                // OAM DMA は Bus 側で処理するためここでは何もしない
            }
            _ => {}
        }
    }

    /// VRAM 読み取り（ミラーリング考慮）
    fn read_vram(&self, addr: u16) -> u8 {
        let addr = addr & 0x3FFF;
        match addr {
            0x0000..=0x1FFF => {
                // CHR-ROM / CHR-RAM
                if (addr as usize) < self.chr_data.len() {
                    self.chr_data[addr as usize]
                } else {
                    0
                }
            }
            0x2000..=0x3EFF => {
                // ネームテーブル（水平ミラーリング想定）
                let mirrored = self.mirror_vram_addr(addr);
                self.vram[mirrored]
            }
            0x3F00..=0x3FFF => {
                // パレット RAM
                let mut idx = (addr - 0x3F00) as usize % 32;
                // スプライトパレット 0x10,0x14,0x18,0x1C はバックグラウンドにミラー
                if idx >= 16 && idx % 4 == 0 {
                    idx -= 16;
                }
                self.palette[idx]
            }
            _ => 0,
        }
    }

    /// VRAM 書き込み
    fn write_vram(&mut self, addr: u16, val: u8) {
        let addr = addr & 0x3FFF;
        match addr {
            0x0000..=0x1FFF => {
                // CHR-RAM への書き込み（CHR-ROM の場合は無視）
                if (addr as usize) < self.chr_data.len() {
                    self.chr_data[addr as usize] = val;
                }
            }
            0x2000..=0x3EFF => {
                let mirrored = self.mirror_vram_addr(addr);
                self.vram[mirrored] = val;
            }
            0x3F00..=0x3FFF => {
                let mut idx = (addr - 0x3F00) as usize % 32;
                if idx >= 16 && idx % 4 == 0 {
                    idx -= 16;
                }
                self.palette[idx] = val;
            }
            _ => {}
        }
    }

    /// ネームテーブルアドレスのミラーリング（水平ミラーリング）
    fn mirror_vram_addr(&self, addr: u16) -> usize {
        let addr = (addr & 0x0FFF) as usize;
        // 水平ミラー: NT0=$2000、NT1=$2400 → NT0 と同じ、NT2=$2800、NT3=$2C00 → NT1 と同じ
        // ここでは簡易実装（水平ミラーリング固定）
        if addr < 0x400 {
            addr
        } else if addr < 0x800 {
            addr - 0x400 // NT1 → NT0 にミラー
        } else if addr < 0xC00 {
            addr - 0x400 // NT2 → NT1 にミラー
        } else {
            addr - 0x800 // NT3 → NT0 にミラー
        }
    }

    /// CPU サイクル数を受け取り PPU を進める
    /// 1 CPU サイクル = 3 PPU ドット
    pub fn step(&mut self, cpu_cycles: u32) {
        let ppu_cycles = cpu_cycles * 3;
        for _ in 0..ppu_cycles {
            self.tick();
        }
    }

    /// PPU を 1 ドット進める
    fn tick(&mut self) {
        self.dot += 1;

        if self.dot > 340 {
            self.dot = 0;
            self.scanline += 1;

            if self.scanline > 261 {
                self.scanline = -1;
                self.frame += 1;
                // 奇数フレームではプリレンダースキャンラインが 1 ドット短い
                // （簡易実装では省略）
            }
        }

        match self.scanline {
            -1 => {
                // プリレンダースキャンライン
                if self.dot == 1 {
                    // VBlank フラグをクリア
                    self.status &= !(status_flags::VBLANK | status_flags::SPRITE_OVERFLOW | status_flags::SPRITE_ZERO_HIT);
                }
            }
            0..=239 => {
                // 可視スキャンライン
                if self.dot >= 1 && self.dot <= 256 {
                    self.render_pixel();
                }
            }
            241 => {
                // VBlank 開始
                if self.dot == 1 {
                    self.status |= status_flags::VBLANK;
                    if self.ctrl & ctrl_flags::NMI_ENABLE != 0 {
                        self.nmi_pending = true;
                    }
                    self.frame_ready = true;
                }
            }
            _ => {}
        }
    }

    /// 1 ピクセルをレンダリングしてフレームバッファに書き込む
    fn render_pixel(&mut self) {
        let x = (self.dot - 1) as usize;
        let y = self.scanline as usize;

        if x >= 256 || y >= 240 {
            return;
        }

        // 背景描画
        let bg_pixel = if self.mask & mask_flags::SHOW_BG != 0 {
            self.get_bg_pixel(x, y)
        } else {
            0
        };

        // スプライト描画
        let (sprite_pixel, sprite_priority) = if self.mask & mask_flags::SHOW_SPRITES != 0 {
            self.get_sprite_pixel(x, y)
        } else {
            (0, false)
        };

        // 最終ピクセル決定
        let palette_idx = if sprite_pixel != 0 && (bg_pixel == 0 || !sprite_priority) {
            // スプライト優先 (sprite_priority=true は背景の後ろに隠れる)
            sprite_pixel
        } else if bg_pixel != 0 {
            bg_pixel
        } else {
            0 // ユニバーサル背景色
        };

        let color = self.palette_to_rgb(palette_idx);
        let idx = (y * 256 + x) * 4;
        self.frame_buffer[idx]     = color.0; // R
        self.frame_buffer[idx + 1] = color.1; // G
        self.frame_buffer[idx + 2] = color.2; // B
        self.frame_buffer[idx + 3] = 255;     // A
    }

    /// 背景ピクセルのパレットインデックスを取得する
    fn get_bg_pixel(&self, x: usize, y: usize) -> u8 {
        // 簡易実装: ネームテーブル 0 を使用
        let tile_x = (x + self.scroll_x as usize) / 8 % 32;
        let tile_y = (y + self.scroll_y as usize) / 8 % 30;
        let tile_idx = tile_y * 32 + tile_x;

        if tile_idx >= self.vram.len() {
            return 0;
        }

        let tile_id = self.vram[tile_idx] as usize;
        let fine_x = (x + self.scroll_x as usize) % 8;
        let fine_y = (y + self.scroll_y as usize) % 8;

        // CHR データからパターンを取得
        let bg_table = if self.ctrl & ctrl_flags::BG_TABLE != 0 { 0x1000 } else { 0x0000 };
        let pattern_lo_addr = bg_table + tile_id * 16 + fine_y;
        let pattern_hi_addr = pattern_lo_addr + 8;

        let lo = if pattern_lo_addr < self.chr_data.len() { self.chr_data[pattern_lo_addr] } else { 0 };
        let hi = if pattern_hi_addr < self.chr_data.len() { self.chr_data[pattern_hi_addr] } else { 0 };

        let bit = 7 - fine_x;
        let pixel = ((lo >> bit) & 1) | (((hi >> bit) & 1) << 1);

        if pixel == 0 {
            return 0; // 透明
        }

        // アトリビュートテーブルからパレット番号を取得
        let attr_idx = (tile_y / 4) * 8 + (tile_x / 4) + 0x3C0;
        let attr = if attr_idx < self.vram.len() { self.vram[attr_idx] } else { 0 };
        let attr_shift = ((tile_y % 4) / 2) * 4 + ((tile_x % 4) / 2) * 2;
        let palette_num = (attr >> attr_shift) & 0x03;

        // パレット RAM インデックス: BG パレット $3F01 + palette_num*4 + pixel
        let palette_ram_idx = (palette_num * 4 + pixel) as usize;
        if palette_ram_idx < 16 {
            self.palette[palette_ram_idx]
        } else {
            0
        }
    }

    /// スプライトピクセルのパレットインデックスを取得する
    /// 返り値: (パレットインデックス, 後ろ優先フラグ)
    fn get_sprite_pixel(&self, x: usize, y: usize) -> (u8, bool) {
        let sprite_size = if self.ctrl & ctrl_flags::SPRITE_SIZE != 0 { 16 } else { 8 };
        let sprite_table = if self.ctrl & ctrl_flags::SPRITE_TABLE != 0 { 0x1000 } else { 0x0000 };

        for i in 0..64 {
            let sprite_y = self.oam[i * 4] as i32 + 1;
            let sprite_x = self.oam[i * 4 + 3] as usize;
            let tile_id = self.oam[i * 4 + 1] as usize;
            let attr = self.oam[i * 4 + 2];

            let y = y as i32;

            if y < sprite_y || y >= sprite_y + sprite_size {
                continue;
            }
            if x < sprite_x || x >= sprite_x + 8 {
                continue;
            }

            let flip_h = attr & 0x40 != 0;
            let flip_v = attr & 0x80 != 0;
            let priority = attr & 0x20 != 0; // true = 背景の後ろ

            let mut fine_y = (y - sprite_y) as usize;
            if flip_v {
                fine_y = (sprite_size as usize - 1) - fine_y;
            }

            let pattern_lo_addr = sprite_table + tile_id * 16 + fine_y;
            let pattern_hi_addr = pattern_lo_addr + 8;

            let lo = if pattern_lo_addr < self.chr_data.len() { self.chr_data[pattern_lo_addr] } else { 0 };
            let hi = if pattern_hi_addr < self.chr_data.len() { self.chr_data[pattern_hi_addr] } else { 0 };

            let bit = if flip_h { x - sprite_x } else { 7 - (x - sprite_x) };
            let pixel = ((lo >> bit) & 1) | (((hi >> bit) & 1) << 1);

            if pixel == 0 {
                continue; // 透明
            }

            let palette_num = (attr & 0x03) as usize;
            // スプライトパレット: $3F11 以降 (インデックス 16 以降)
            let palette_ram_idx = 16 + palette_num * 4 + pixel as usize;
            if palette_ram_idx < 32 {
                return (self.palette[palette_ram_idx], priority);
            }
        }

        (0, false)
    }

    /// パレットインデックスから RGB を取得する
    fn palette_to_rgb(&self, palette_idx: u8) -> (u8, u8, u8) {
        // パレット RAM にはシステムパレットのインデックスが格納されている
        // palette_idx 0 はユニバーサル背景色
        let sys_idx = (palette_idx & 0x3F) as usize;
        if sys_idx < NES_PALETTE.len() {
            NES_PALETTE[sys_idx]
        } else {
            (0, 0, 0)
        }
    }

    /// フレームバッファの RGBA データを Vec<u8> として返す
    pub fn get_frame_buffer(&self) -> Vec<u8> {
        self.frame_buffer.to_vec()
    }
}

impl Default for Ppu {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ppu_initial_state() {
        let ppu = Ppu::new();
        assert_eq!(ppu.scanline, -1, "Initial scanline should be -1 (pre-render)");
        assert_eq!(ppu.dot, 0, "Initial dot should be 0");
        assert!(!ppu.nmi_pending, "NMI should not be pending initially");
        assert!(!ppu.frame_ready, "Frame should not be ready initially");
    }

    #[test]
    fn test_ppu_frame_buffer_size() {
        let ppu = Ppu::new();
        assert_eq!(ppu.frame_buffer.len(), 256 * 240 * 4, "Frame buffer should be 256×240×4 bytes");
    }

    #[test]
    fn test_ppu_get_frame_buffer_size() {
        let ppu = Ppu::new();
        let fb = ppu.get_frame_buffer();
        assert_eq!(fb.len(), 245760, "get_frame_buffer() should return 245760 bytes");
    }

    #[test]
    fn test_ppu_scanline_increment() {
        let mut ppu = Ppu::new();
        // 341 ドット進めると 1 スキャンライン増加（scanline -1 → 0）
        ppu.step(114); // 114 CPU cycles * 3 = 342 PPU dots
        assert!(ppu.scanline >= 0, "After enough cycles, scanline should advance past -1");
    }

    #[test]
    fn test_ppu_nmi_fires_at_vblank() {
        let mut ppu = Ppu::new();
        ppu.ctrl = ctrl_flags::NMI_ENABLE; // NMI 有効化

        // スキャンライン 241, dot 1 に到達するまで進める
        // プリレンダー(-1): 341 dots
        // visible scanlines (0-239): 240 * 341 = 81840 dots
        // post-render (240): 341 dots
        // vblank start (241): at dot 1
        // Total: 341 + 81840 + 341 + 1 = 82523 PPU dots ≈ 27508 CPU cycles

        // 大まかに進める
        let target_cycles = (341 + 240 * 341 + 341 + 1 + 1) / 3 + 1;
        ppu.step(target_cycles as u32);

        assert!(ppu.nmi_pending, "NMI should fire at VBlank (scanline 241)");
    }

    #[test]
    fn test_ppu_frame_complete_after_one_frame() {
        let mut ppu = Ppu::new();
        ppu.ctrl = ctrl_flags::NMI_ENABLE;

        // 1 フレーム = 262 スキャンライン * 341 ドット = 89342 PPU dots
        // ≈ 29780 CPU サイクル
        ppu.step(29781);

        assert!(ppu.frame_ready, "frame_ready should be true after one frame");
    }

    #[test]
    fn test_ppu_vblank_flag_cleared_on_status_read() {
        let mut ppu = Ppu::new();
        ppu.ctrl = ctrl_flags::NMI_ENABLE;
        ppu.step(29781); // 1 フレーム

        // $2002 を読み取ると VBlank フラグがクリアされる
        let status = ppu.read_register(0x2002);
        assert_ne!(status & status_flags::VBLANK, 0, "VBlank flag should be set before read");
        let status2 = ppu.read_register(0x2002);
        assert_eq!(status2 & status_flags::VBLANK, 0, "VBlank flag should be cleared after read");
    }

    #[test]
    fn test_ppu_write_vram_via_2006_2007() {
        let mut ppu = Ppu::new();

        // $2006 に 2 回書いてアドレスを $2000 に設定
        ppu.write_register(0x2006, 0x20);
        ppu.write_register(0x2006, 0x00);

        // $2007 に書き込み
        ppu.write_register(0x2007, 0xAB);

        // VRAM[0] に書き込まれているはず
        assert_eq!(ppu.vram[0], 0xAB, "VRAM write via $2007 should work");
    }

    #[test]
    fn test_ppu_palette_to_rgb() {
        let ppu = Ppu::new();
        // パレット 0 は (84, 84, 84)
        let rgb = ppu.palette_to_rgb(0x00);
        assert_eq!(rgb, (84, 84, 84), "Palette 0x00 should be (84,84,84)");
    }
}
