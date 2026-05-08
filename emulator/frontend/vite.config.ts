import { defineConfig } from "vite";
import wasm from "vite-plugin-wasm";
import topLevelAwait from "vite-plugin-top-level-await";

export default defineConfig({
  base: "/vibe-whims/",
  plugins: [wasm(), topLevelAwait()],
  build: {
    target: "esnext",
  },
  server: {
    headers: {
      // WASM ロードに必要なヘッダー（SharedArrayBuffer は不使用だが念のため設定）
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    },
  },
});
