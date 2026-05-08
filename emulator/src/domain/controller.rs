/// NES コントローラーボタンのビットマップ定数
pub mod buttons {
    pub const A: u8      = 0x01;
    pub const B: u8      = 0x02;
    pub const SELECT: u8 = 0x04;
    pub const START: u8  = 0x08;
    pub const UP: u8     = 0x10;
    pub const DOWN: u8   = 0x20;
    pub const LEFT: u8   = 0x40;
    pub const RIGHT: u8  = 0x80;
}

/// NES コントローラー
/// $4016 書き込みでラッチ、$4016 読み取りでシリアル出力（MSB → LSB 順）
/// NES 標準ではシフトレジスタは A, B, Select, Start, Up, Down, Left, Right の順
/// ただしビットマップ定義に合わせて LSB=A, bit7=Right として扱う
pub struct Controller {
    /// 現在のボタン状態（ビットマップ）
    buttons: u8,
    /// ラッチされたボタン状態
    shift_register: u8,
    /// ラッチビット（1 の間はシフトレジスタを常に buttons でリロードする）
    strobe: bool,
    /// シフトカウント（0-7、8 以上は常に 1 を返す）
    shift_count: u8,
}

impl Controller {
    pub fn new() -> Self {
        Self {
            buttons: 0,
            shift_register: 0,
            strobe: false,
            shift_count: 0,
        }
    }

    /// ボタン状態を設定する（キーボードイベントハンドラから呼ばれる）
    pub fn set_buttons(&mut self, bits: u8) {
        self.buttons = bits;
        if self.strobe {
            self.shift_register = self.buttons;
        }
    }

    /// $4016 への書き込み（ストローブ制御）
    pub fn write(&mut self, val: u8) {
        self.strobe = val & 0x01 != 0;
        if self.strobe {
            // ストローブ中はシフトレジスタを buttons で更新し続ける
            self.shift_register = self.buttons;
            self.shift_count = 0;
        }
    }

    /// $4016 からの読み取り（シリアルビット出力）
    /// ストローブ OFF 後に 8 回読み取ると 8 ボタン分を返す
    /// 順序: A, B, Select, Start, Up, Down, Left, Right
    pub fn read(&mut self) -> u8 {
        if self.strobe {
            // ストローブ中は常に A ボタンの状態を返す
            return self.buttons & buttons::A;
        }

        if self.shift_count >= 8 {
            // 8 回読み終わった後は常に 1 を返す（NES 実機の挙動）
            return 1;
        }

        // NES コントローラーのシリアル順: A=LSB → Right=MSB の順でビットを出力
        // ビット 0 から順番にシフト
        let bit = (self.shift_register >> self.shift_count) & 0x01;
        self.shift_count += 1;
        bit
    }
}

impl Default for Controller {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::buttons::*;

    #[test]
    fn test_controller_initial_state() {
        let ctrl = Controller::new();
        assert_eq!(ctrl.buttons, 0, "Initial button state should be 0");
        assert!(!ctrl.strobe, "Initial strobe should be false");
    }

    #[test]
    fn test_controller_set_button_state() {
        let mut ctrl = Controller::new();
        ctrl.set_buttons(A | B);
        assert_eq!(ctrl.buttons, A | B);
    }

    #[test]
    fn test_controller_all_buttons() {
        // 全ボタンのビット定義が重複しないこと
        let all = A | B | SELECT | START | UP | DOWN | LEFT | RIGHT;
        assert_eq!(all, 0xFF, "All 8 buttons should cover all bits of a byte");
    }

    #[test]
    fn test_controller_latch_and_serial_read() {
        let mut ctrl = Controller::new();
        // A ボタンのみ押す
        ctrl.set_buttons(A);

        // $4016 に 1 を書いてラッチ
        ctrl.write(0x01);
        // $4016 に 0 を書いてストローブ解除
        ctrl.write(0x00);

        // 順番通りに読み取る: A=1, B=0, Select=0, Start=0, Up=0, Down=0, Left=0, Right=0
        assert_eq!(ctrl.read(), 1, "Read 1: A should be 1");
        assert_eq!(ctrl.read(), 0, "Read 2: B should be 0");
        assert_eq!(ctrl.read(), 0, "Read 3: Select should be 0");
        assert_eq!(ctrl.read(), 0, "Read 4: Start should be 0");
        assert_eq!(ctrl.read(), 0, "Read 5: Up should be 0");
        assert_eq!(ctrl.read(), 0, "Read 6: Down should be 0");
        assert_eq!(ctrl.read(), 0, "Read 7: Left should be 0");
        assert_eq!(ctrl.read(), 0, "Read 8: Right should be 0");
    }

    #[test]
    fn test_controller_read_after_8_returns_1() {
        let mut ctrl = Controller::new();
        ctrl.set_buttons(0x00);
        ctrl.write(0x01);
        ctrl.write(0x00);

        // 8 回読み取り
        for _ in 0..8 {
            ctrl.read();
        }
        // 9 回目以降は 1 を返す
        assert_eq!(ctrl.read(), 1, "Read after 8 should return 1");
        assert_eq!(ctrl.read(), 1, "Read after 9 should return 1");
    }

    #[test]
    fn test_controller_strobe_active_returns_a_button() {
        let mut ctrl = Controller::new();
        ctrl.set_buttons(A);
        ctrl.write(0x01); // ストローブ ON

        // ストローブ中は常に A ボタンの値を返す
        assert_eq!(ctrl.read(), 1, "Strobe active: A=1");
        assert_eq!(ctrl.read(), 1, "Strobe active: still A=1");
    }

    #[test]
    fn test_controller_strobe_active_no_a_button() {
        let mut ctrl = Controller::new();
        ctrl.set_buttons(B); // A は押していない
        ctrl.write(0x01);

        assert_eq!(ctrl.read(), 0, "Strobe active: A=0 when only B pressed");
    }

    #[test]
    fn test_controller_multiple_buttons() {
        let mut ctrl = Controller::new();
        // A + Start を押す
        ctrl.set_buttons(A | START);
        ctrl.write(0x01);
        ctrl.write(0x00);

        assert_eq!(ctrl.read(), 1, "A=1");
        assert_eq!(ctrl.read(), 0, "B=0");
        assert_eq!(ctrl.read(), 0, "Select=0");
        assert_eq!(ctrl.read(), 1, "Start=1");
    }

    #[test]
    fn test_controller_relatch_after_button_change() {
        let mut ctrl = Controller::new();
        ctrl.set_buttons(A);
        ctrl.write(0x01);
        ctrl.write(0x00);

        // 一度ラッチ後にボタン状態を変えても読み取り結果は変わらない
        ctrl.set_buttons(0x00);
        assert_eq!(ctrl.read(), 1, "Latched A should still be 1 after button change");
    }
}
