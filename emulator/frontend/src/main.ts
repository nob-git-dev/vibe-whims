/**
 * main.ts
 * アプリ初期化: WASM ロード → DOM 要素取得 → イベント登録 → GameLoop 起動
 */

import init, { WasmEmulator } from "./wasm/nes_emulator.js";
import { Renderer } from "./renderer.js";
import { GameLoop } from "./gameLoop.js";
import { InputHandler } from "./inputHandler.js";
import { setupRomLoader } from "./romLoader.js";

async function main(): Promise<void> {
  // WASM モジュール初期化
  await init();

  // DOM 要素取得
  const canvas = document.getElementById("nes-canvas") as HTMLCanvasElement;
  const romInput = document.getElementById("rom-input") as HTMLInputElement;
  const status = document.getElementById("status") as HTMLSpanElement;

  if (!canvas || !romInput || !status) {
    console.error("必要な DOM 要素が見つかりません");
    return;
  }

  // エミュレーター・レンダラー・入力ハンドラーを生成
  const emulator = new WasmEmulator();
  const renderer = new Renderer(canvas);
  const inputHandler = new InputHandler();
  let gameLoop: GameLoop | null = null;

  // 入力ハンドラーにエミュレーターをアタッチ
  inputHandler.attach(emulator);
  inputHandler.register();

  // ROM ローダーをセットアップ
  setupRomLoader(
    romInput,
    (data: Uint8Array, filename: string) => {
      try {
        // 実行中のゲームループを停止
        gameLoop?.stop();

        // ROM をロード
        emulator.load_rom(data);
        status.textContent = `実行中: ${filename}`;
        status.style.color = "#7fff7f";

        // ゲームループを開始
        gameLoop = new GameLoop(emulator, renderer);
        gameLoop.start();
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        status.textContent = `エラー: ${msg}`;
        status.style.color = "#ff7f7f";
        console.error("ROM ロードエラー:", err);
      }
    },
    (errMsg: string) => {
      status.textContent = errMsg;
      status.style.color = "#ff7f7f";
      console.error(errMsg);
    }
  );

  status.textContent = "WASM ロード完了 - ROM を選択してください";
  console.log("NES エミュレーター初期化完了");
}

main().catch((err) => {
  console.error("初期化エラー:", err);
});
