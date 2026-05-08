declare module 'jsnes' {
  export class NES {
    constructor(opts: { onFrame: (buf: number[]) => void; onAudioSample: (l: number, r: number) => void })
    loadROM(data: string): void
    frame(): void
    buttonDown(player: number, button: number): void
    buttonUp(player: number, button: number): void
  }
  export const Controller: {
    BUTTON_A: number
    BUTTON_B: number
    BUTTON_UP: number
    BUTTON_DOWN: number
    BUTTON_LEFT: number
    BUTTON_RIGHT: number
    BUTTON_START: number
    BUTTON_SELECT: number
  }
}
