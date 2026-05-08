/**
 * inputHandler.ts
 * キーボードイベントを NES ボタンビットマップに変換し
 * emulator.set_button_state() を呼び出す
 */

/** NES ボタンビット定義 */
export const NES_BUTTON = {
  A:      0x01,
  B:      0x02,
  SELECT: 0x04,
  START:  0x08,
  UP:     0x10,
  DOWN:   0x20,
  LEFT:   0x40,
  RIGHT:  0x80,
} as const;

/** キーコード → NES ボタンビット マッピング */
const KEY_MAP: Record<string, number> = {
  ArrowUp:    NES_BUTTON.UP,
  ArrowDown:  NES_BUTTON.DOWN,
  ArrowLeft:  NES_BUTTON.LEFT,
  ArrowRight: NES_BUTTON.RIGHT,
  KeyZ:       NES_BUTTON.B,
  KeyX:       NES_BUTTON.A,
  ShiftLeft:  NES_BUTTON.SELECT,
  ShiftRight: NES_BUTTON.SELECT,
  Enter:      NES_BUTTON.START,
};

export interface EmulatorInput {
  set_button_state(player: number, bits: number): void;
}

export class InputHandler {
  private buttonState: number = 0;
  private emulator: EmulatorInput | null = null;

  constructor() {
    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.handleKeyUp   = this.handleKeyUp.bind(this);
  }

  /** エミュレーターをアタッチする */
  attach(emulator: EmulatorInput): void {
    this.emulator = emulator;
  }

  /** イベントリスナーを登録する */
  register(): void {
    window.addEventListener("keydown", this.handleKeyDown);
    window.addEventListener("keyup",   this.handleKeyUp);
  }

  /** イベントリスナーを解除する */
  unregister(): void {
    window.removeEventListener("keydown", this.handleKeyDown);
    window.removeEventListener("keyup",   this.handleKeyUp);
  }

  private handleKeyDown(event: KeyboardEvent): void {
    const bit = KEY_MAP[event.code];
    if (bit !== undefined) {
      event.preventDefault();
      this.buttonState |= bit;
      this.emulator?.set_button_state(0, this.buttonState);
    }
  }

  private handleKeyUp(event: KeyboardEvent): void {
    const bit = KEY_MAP[event.code];
    if (bit !== undefined) {
      event.preventDefault();
      this.buttonState &= ~bit;
      this.emulator?.set_button_state(0, this.buttonState);
    }
  }
}
