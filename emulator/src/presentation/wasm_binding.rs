use wasm_bindgen::prelude::*;
use crate::domain::Emulator;

/// JS から呼び出す WASM バインディング
/// Emulator ドメインオブジェクトの薄いラッパー
/// DOM・Canvas への参照は一切持たない
#[wasm_bindgen]
pub struct WasmEmulator {
    emulator: Emulator,
}

#[wasm_bindgen]
impl WasmEmulator {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Self {
        // パニックをコンソールエラーに変換（デバッグ用）
        #[cfg(feature = "console_error_panic_hook")]
        console_error_panic_hook::set_once();

        Self {
            emulator: Emulator::new(),
        }
    }

    /// ROM のバイト列を受け取り、iNES パース → Cartridge ロード → RESET ベクタ実行開始
    pub fn load_rom(&mut self, data: &[u8]) -> Result<(), JsValue> {
        self.emulator
            .load_rom(data)
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }

    /// 1 フレーム分（約 29780 CPU サイクル相当）を実行する
    pub fn step_frame(&mut self) {
        self.emulator.step_frame();
    }

    /// フレームバッファ（RGBA 各 1 byte、256×240×4 = 245760 bytes）を返す
    pub fn frame_buffer(&self) -> Vec<u8> {
        self.emulator.frame_buffer()
    }

    /// コントローラー入力を設定する
    /// player: 0 = Player 1、bits: ボタンビットマップ
    /// A=0x01, B=0x02, Select=0x04, Start=0x08,
    /// Up=0x10, Down=0x20, Left=0x40, Right=0x80
    pub fn set_button_state(&mut self, player: u8, bits: u8) {
        self.emulator.set_button_state(player, bits);
    }
}
