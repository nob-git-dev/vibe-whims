/**
 * gameLoop.ts
 * requestAnimationFrame ベースのゲームループ
 * 毎フレーム: emulator.step_frame() → emulator.frame_buffer() → renderer.draw()
 */

import { Renderer } from "./renderer.js";

export interface EmulatorFrame {
  step_frame(): void;
  frame_buffer(): Uint8Array;
}

export class GameLoop {
  private emulator: EmulatorFrame;
  private renderer: Renderer;
  private rafId: number | null = null;
  private running: boolean = false;

  constructor(emulator: EmulatorFrame, renderer: Renderer) {
    this.emulator = emulator;
    this.renderer = renderer;
    this.tick = this.tick.bind(this);
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.rafId = requestAnimationFrame(this.tick);
  }

  stop(): void {
    this.running = false;
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  }

  private tick(): void {
    if (!this.running) return;

    try {
      // 1. エミュレーター 1 フレーム実行
      this.emulator.step_frame();

      // 2. フレームバッファ取得
      const pixels = this.emulator.frame_buffer();

      // 3. Canvas に描画
      this.renderer.draw(pixels);
    } catch (err) {
      console.error("ゲームループエラー:", err);
      this.stop();
      return;
    }

    // 4. 次フレームをスケジュール
    this.rafId = requestAnimationFrame(this.tick);
  }
}
