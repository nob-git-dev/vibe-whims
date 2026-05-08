# ブラウザ NES プレイヤー 仕様書

## 目的

game.nes（AI が生成した NES ROM）をブラウザだけで動かせる最小限のプレイヤーを作る。
ユーザーが game.nes を入手すれば、ネイティブアプリ不要でゲームをプレイできる環境を提供し、
同時に AI 生成バイナリの動作検証（ゲームが正しく動くかの確認）を行う。

### 機能ごとの目的

| 機能・コンポーネント | 目的（この機能が存在する理由） | 変えてはならない本質 |
|---|---|---|
| Canvas 描画（256×240px） | NES の出力をブラウザ画面に正確に描画する | 解像度・アスペクト比を維持し、ピクセルを正確に表示すること |
| jsnes 統合 | NES ROM を CPU/PPU/APU レベルでエミュレートする | jsnes ライブラリのみを使用し、他のエミュレータに差し替えない |
| キーボード入力 | NES コントローラーをキーボードでエミュレートする | 定義されたキーマップを正確に実装すること |
| game.nes 静的配信 | ROM ファイルをブラウザから fetch 可能にする | public/game.nes として配置し、外部依存なしで動作すること |
| Vite 開発サーバー | HMR 付きのローカル開発環境を提供する | pnpm dev 一発で起動できること |

---

## 振る舞い

### 起動フロー
1. `pnpm dev` を実行、またはブラウザで `index.html` を直接開く
2. ブラウザが `public/game.nes` を fetch する
3. jsnes に ROM データを渡してエミュレーターを初期化する
4. Canvas（256×240px）に NES の映像が 60fps で描画される

### キーボード操作
| キー | NES コントローラー入力 |
|---|---|
| ArrowUp | 十字キー 上 |
| ArrowDown | 十字キー 下 |
| ArrowLeft | 十字キー 左 |
| ArrowRight | 十字キー 右 |
| Z | A ボタン |
| X | B ボタン |
| Enter | Start |
| Shift | Select |

### データフロー
```
fetch("game.nes") → ArrayBuffer → jsnes.loadROM() → フレーム毎の PPU 出力
→ ImageData → Canvas.putImageData() → 画面表示
```

---

## 受け入れ条件

- [ ] `pnpm dev` を実行するとローカルサーバーが起動し、ブラウザで NES 画面が表示される
- [ ] Canvas に 256×240px の NES 映像が描画される
- [ ] ArrowUp/Down/Left/Right キーで十字キー入力が機能し、スプライトが動く
- [ ] Z キーで A ボタン、X キーで B ボタンが機能する
- [ ] Enter キーで Start、Shift キーで Select が機能する
- [ ] `pnpm build` が TypeScript エラーなしで完了する
- [ ] `dist/` ディレクトリに静的ファイルが生成され、`dist/game.nes` が含まれる
- [ ] `public/game.nes` が存在し、fetch で取得できる

---

## スコープ（やらないこと）

- サウンド出力（音声対応は将来課題）
- セーブ・ロード機能
- ゲームパッド（GamePad API）対応
- ファイルアップロード（ROM を動的に変更する機能）
- モバイル対応・タッチ操作
- フルスクリーン表示
- ネットワーク対戦
- jsnes 以外のエミュレータライブラリの使用

---

## 固定要件

<!-- 技術的判断で変更してはならない要件。後続エージェントはここを必ず読むこと -->
<!-- 逸脱する場合はユーザーに報告して承認を得ること -->

- パッケージマネージャー: **pnpm のみ**（npm・yarn 禁止）
- エミュレータライブラリ: **jsnes のみ**（他の NES エミュレータライブラリ禁止）
- 言語: TypeScript（`.ts`）、JavaScript（`.js`）への書き換え禁止
- ビルドツール: Vite
- 描画: HTML5 Canvas
- ROM 配置: `public/game.nes`（`../game.nes` からコピーまたはシンボリックリンク）
- TypeScript コンパイルエラーなし（`pnpm build` が通ること）

---

## ファイル構成

```
player/
├── SPEC.md               ← この仕様書
├── package.json          ← pnpm 管理・スクリプト定義
├── tsconfig.json         ← TypeScript 設定
├── vite.config.ts        ← Vite 設定（public/ を静的配信）
├── index.html            ← エントリーポイント
├── public/
│   └── game.nes          ← ../game.nes からコピーまたはシンボリックリンク
└── src/
    └── main.ts           ← jsnes 初期化・Canvas 描画・キーボード入力
```

---

## システム構成（コンポーネント依存関係）

- [新規: player/ ブラウザプレイヤー]
  - 依存している（このコンポーネントが使う）:
    - `public/game.nes`（ROM ファイル。`../game.nes` からコピー）
    - `jsnes`（npm パッケージ、NES エミュレーション）
    - HTML5 Canvas API（ブラウザ標準）
    - Vite（開発サーバー・ビルドツール）
  - 依存されている（このコンポーネントを使う）:
    - なし（スタンドアロン。ブラウザユーザーが直接利用する）

---

## アーキテクチャ設計
<!-- /architect が追記 -->

## テスト計画

### テストケース（受け入れ条件より）

| 受け入れ条件 | テストケース | 種別 | 結果 |
|---|---|---|---|
| `public/game.nes` が存在し fetch で取得できる | game.nes が 24592 bytes で存在するか確認 | 静的 | ✅ PASS |
| `pnpm build` が TypeScript エラーなしで完了する | `pnpm build` コマンドが exit code 0 で終了する | 静的 | ✅ PASS |
| `dist/` に静的ファイルが生成され `dist/game.nes` が含まれる | ビルド後に dist/index.html と dist/game.nes が存在する | 静的 | ✅ PASS |
| Canvas に 256×240px の NES 映像が描画される | index.html に width="256" height="240" の canvas 要素が存在する | 静的 | ✅ PASS |
| キーボード入力が機能する（全キーマップ） | src/main.ts に 8 つすべてのキーマッピングが定義されている | 静的 | ✅ PASS |
| jsnes のみを使用している | package.json の dependencies に jsnes が含まれ、他の NES エミュレータがない | 静的 | ✅ PASS |
| `pnpm dev` でサーバーが起動する | pnpm dev コマンドが起動する（手動確認） | 手動 | 未確認 |
| ブラウザで NES 画面が表示される | `pnpm dev` 後ブラウザで映像が描画される（手動確認） | 手動 | 未確認 |
| スプライトが矢印キーで動く | ゲームプレイ中に移動が反映される（手動確認） | 手動 | 未確認 |

### テスト環境

- 静的テスト: Bash スクリプトによるファイル存在確認・`pnpm build` 実行
- 手動テスト: `pnpm dev` でサーバー起動後、ブラウザで動作確認
- 実行コマンド（静的）:
  ```bash
  # 1. ROM 存在確認
  ls -la player/public/game.nes
  # 2. ビルド確認
  cd player && pnpm build
  # 3. dist/ 確認
  ls player/dist/game.nes player/dist/index.html
  ```

## レビュー結果
<!-- /review が追記 -->

## デプロイ計画
<!-- /deploy が追記 -->
