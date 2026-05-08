pub mod bus;
pub mod cartridge;
pub mod controller;
pub mod cpu;
pub mod ppu;

use bus::Bus;
use cartridge::{Cartridge, CartridgeError};
use cpu::Cpu;

/// NES エミュレーターのドメインルート
/// CPU + Bus を保持し、フレーム単位のステップ実行を行う
pub struct Emulator {
    pub cpu: Cpu,
    pub bus: Bus,
}

impl Emulator {
    pub fn new() -> Self {
        Self {
            cpu: Cpu::new(),
            bus: Bus::new(),
        }
    }

    /// iNES ROM バイト列を読み込み、エミュレーションを開始する
    pub fn load_rom(&mut self, data: &[u8]) -> Result<(), CartridgeError> {
        let cart = Cartridge::from_bytes(data)?;
        self.bus.load_cartridge(cart);
        self.cpu.reset(&mut self.bus);
        Ok(())
    }

    /// 1 フレーム分（約 29780 CPU サイクル）実行する
    /// PPU フレームバッファを更新する
    pub fn step_frame(&mut self) {
        const CYCLES_PER_FRAME: u32 = 29780;
        let target = self.cpu.cycles + CYCLES_PER_FRAME as u64;

        self.bus.ppu.frame_ready = false;

        while self.cpu.cycles < target {
            // OAM DMA スタール処理
            if self.bus.dma_stall > 0 {
                let stall = self.bus.dma_stall;
                self.bus.dma_stall = 0;
                self.cpu.cycles += stall as u64;
                self.bus.ppu.step(stall);
                continue;
            }

            let cpu_cycles = self.cpu.step(&mut self.bus) as u32;
            self.bus.ppu.step(cpu_cycles);

            // NMI チェック
            if self.bus.ppu.nmi_pending {
                self.bus.ppu.nmi_pending = false;
                self.cpu.nmi(&mut self.bus);
            }
        }
    }

    /// フレームバッファ（RGBA、256×240×4 = 245760 バイト）を返す
    pub fn frame_buffer(&self) -> Vec<u8> {
        self.bus.ppu.get_frame_buffer()
    }

    /// コントローラーボタン状態を設定する
    /// player: 0 = Player 1, 1 = Player 2
    /// bits: ボタンビットマップ
    pub fn set_button_state(&mut self, player: u8, bits: u8) {
        match player {
            0 => self.bus.controller1.set_buttons(bits),
            1 => self.bus.controller2.set_buttons(bits),
            _ => {}
        }
    }
}

impl Default for Emulator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infrastructure::rom_parser::make_test_rom;

    fn make_minimal_rom() -> Vec<u8> {
        let mut rom = make_test_rom(1, 1, 0, 0);
        // RESET ベクタ: $8000
        let reset_lo_offset = 16 + 0x3FFC;
        let reset_hi_offset = 16 + 0x3FFD;
        rom[reset_lo_offset] = 0x00;
        rom[reset_hi_offset] = 0x80;
        // $8000: JMP $8000 (無限ループ)
        rom[16] = 0x4C; // JMP
        rom[17] = 0x00;
        rom[18] = 0x80;
        rom
    }

    #[test]
    fn test_emulator_load_rom() {
        let mut emu = Emulator::new();
        let rom = make_minimal_rom();
        let result = emu.load_rom(&rom);
        assert!(result.is_ok(), "load_rom should succeed with valid ROM");
    }

    #[test]
    fn test_emulator_reset_vector() {
        let mut emu = Emulator::new();
        let rom = make_minimal_rom();
        emu.load_rom(&rom).unwrap();
        assert_eq!(emu.cpu.pc, 0x8000, "CPU PC should be at RESET vector $8000");
    }

    #[test]
    fn test_emulator_frame_buffer_size() {
        let emu = Emulator::new();
        let fb = emu.frame_buffer();
        assert_eq!(fb.len(), 245760, "Frame buffer should be 245760 bytes");
    }

    #[test]
    fn test_emulator_step_frame() {
        let mut emu = Emulator::new();
        let rom = make_minimal_rom();
        emu.load_rom(&rom).unwrap();
        let initial_cycles = emu.cpu.cycles;
        emu.step_frame();
        assert!(
            emu.cpu.cycles >= initial_cycles + 29780,
            "step_frame should advance at least 29780 CPU cycles"
        );
    }

    #[test]
    fn test_emulator_set_button_state() {
        let mut emu = Emulator::new();
        // ボタン設定がパニックしないこと
        emu.set_button_state(0, 0xFF); // Player 1 全ボタン
        emu.set_button_state(1, 0x00); // Player 2 なし
    }

    #[test]
    fn test_emulator_load_invalid_rom() {
        let mut emu = Emulator::new();
        let result = emu.load_rom(&[0u8; 5]);
        assert!(result.is_err(), "Invalid ROM should fail to load");
    }
}
