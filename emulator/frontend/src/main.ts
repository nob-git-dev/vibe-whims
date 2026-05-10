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

  // ROM をロードしてゲームループを開始する共通処理
  function loadRom(data: Uint8Array, filename: string): void {
    try {
      gameLoop?.stop();
      emulator.load_rom(data);
      status.textContent = `▶ ${filename}`;
      status.style.color = "#7fff7f";
      gameLoop = new GameLoop(emulator, renderer);
      gameLoop.start();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      status.textContent = `エラー: ${msg}`;
      status.style.color = "#ff7f7f";
      console.error("ROM ロードエラー:", err);
    }
  }

  // 入力ハンドラーにエミュレーターをアタッチ
  inputHandler.attach(emulator);
  inputHandler.register();

  // ファイル選択 ROM ローダー
  setupRomLoader(
    romInput,
    (data, filename) => loadRom(data, filename),
    (errMsg) => {
      status.textContent = errMsg;
      status.style.color = "#ff7f7f";
      console.error(errMsg);
    }
  );

  // デフォルト ROM を自動ロード（public/game.nes）
  status.textContent = "Loading...";
  try {
    const url = `${import.meta.env.BASE_URL}game.nes`;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buf = await res.arrayBuffer();
    loadRom(new Uint8Array(buf), "game.nes");
  } catch (err) {
    console.warn("デフォルト ROM のロードに失敗:", err);
    status.textContent = "ROM を選択してください";
    status.style.color = "#aaa";
  }

  console.log("NES エミュレーター初期化完了");
}

main().catch((err) => {
  console.error("初期化エラー:", err);
});
