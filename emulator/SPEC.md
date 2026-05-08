# NES エミュレータ（Rust → WebAssembly）仕様書

## 目的

親プロジェクト `nes-binary-experiment` が生成する `game.nes` を、ブラウザ上でそのまま実行できる環境を提供する。
アセンブラ・コンパイラを介さずにバイナリを直接生成するという親プロジェクトの哲学を補完し、「AI が書いた `.nes` が即座にブラウザで動く」というフィードバックループを実現する。

### 機能ごとの目的

<!-- 変更を評価する物差し。後続エージェントは作業前に必ずここを確認すること -->

| 機能・コンポーネント | 目的（この機能が存在する理由） | 変えてはならない本質 |
|---|---|---|
| 6502 CPU エミュレーション | NES ゲームロジックを実行する | 公式命令セット全命令・全アドレッシングモードの正確な動作。フラグ・サイクルカウントの仕様準拠 |
| PPU エミュレーション | スプライト・背景をスキャンライン単位で描画する | 1 フレームを 60Hz で描画すること。スプライトとパレットが仕様に従って表示されること |
| Mapper 0（NROM）サポート | 親プロジェクトが生成する NROM 形式の ROM を動かす | PRG-ROM 16KB/32KB・CHR-ROM 8KB の正確なメモリマッピング |
| コントローラー入力 | キーボードから NES ゲームパッドへのマッピング | ボタン状態が $4016 読み取りシーケンスで正確に反映されること |
| WASM バインディング | Rust ロジックをブラウザから呼び出せるようにする | wasm-bindgen を通じた安全な JS ↔ Rust 境界。DOM・Canvas への依存を presentation 層に閉じ込めること |
| フロントエンド（TypeScript/Vite） | ブラウザ UI・ゲームループ・入出力を担う | pnpm + TypeScript 必須。`pnpm dev` で即起動できること |
| ROM 読み込み UI | ユーザーが `.nes` ファイルをブラウザから選択して起動できる | ファイル選択 → iNES パース → エミュレータ起動のフローが途切れないこと |

---

## 振る舞い

1. ユーザーが `pnpm dev` を実行するとローカル開発サーバーが起動し、ブラウザで UI が表示される
2. ユーザーがファイル選択ボタンから `.nes` ファイルを選択する
3. TypeScript が ArrayBuffer を Rust WASM モジュールへ渡す
4. Rust 側で iNES ヘッダーをパースし、PRG-ROM・CHR-ROM を RAM にロードする
5. エミュレーション開始: CPU が RESET ベクタから実行を開始する
6. PPU がスキャンライン描画を行い、フレームバッファを生成する（60Hz）
7. TypeScript がフレームバッファを受け取り、HTML5 Canvas に描画する
8. キーボードイベントを受け取り、対応するコントローラーボタン状態を WASM に送る
9. NMI・IRQ 割り込みが適切なタイミングで発火する

### コントローラーキーマッピング

| キーボード | NES ボタン |
|---|---|
| 矢印キー（上下左右） | 十字キー（Up / Down / Left / Right） |
| Z | B ボタン |
| X | A ボタン |
| Shift | Select |
| Enter | Start |

---

## 受け入れ条件

- [ ] `pnpm dev` を実行するとブラウザでページが表示される（localhost でアクセス可能）
- [ ] ブラウザのファイル選択 UI から `.nes` ファイルを選択できる
- [ ] Mapper 0（NROM）形式の `.nes` ファイルが読み込まれ、エミュレーションが開始する
- [ ] HTML5 Canvas に NES の映像（256×240 ピクセル）が描画される
- [ ] 60fps 目標でゲームが動作する（requestAnimationFrame ベースのゲームループ）
- [ ] 矢印キー入力がスプライトの移動に反映される
- [ ] Z/X/Enter/Shift キーが NES ボタン（B/A/Start/Select）として機能する
- [ ] 親プロジェクトの `../game.nes` を読み込んだとき、スプライトが表示され移動・当たり判定が機能する
- [ ] ページ読み込み後にエラーなくコンソールが表示される（JS エラーなし）
- [ ] `pnpm build` が成功し、`dist/` 以下に配布可能な静的ファイルが生成される

---

## スコープ（やらないこと）

- Mapper 0 以外のカートリッジマッパー（MMC1, MMC3 等）は対象外
- APU（音声）は対象外（無音での動作を目標とする）
- ネットワーク対戦・セーブ機能は対象外
- NES 実機との互換性検証は対象外（エミュレータ上で動作すれば十分）
- デバッガ・ステップ実行等の開発支援機能は対象外
- ゲームパッド（USB コントローラー）サポートは対象外（キーボードのみ）
- PPU サイクル精度の完全再現（スプレート 0 ヒット・ラスタースクロール等の高度な機能）は必須ではない
- モバイル端末対応・タッチ入力は対象外

---

## 固定要件

<!-- 技術的判断で変更してはならない要件。後続エージェントはここを必ず読むこと -->
<!-- 逸脱する場合はユーザーに報告して承認を得ること -->

- **実装言語**: Rust + wasm-pack（変更禁止）
- **フロントエンド**: TypeScript 必須（`.ts` / `.tsx`）、pnpm 使用（npm 禁止）
- **ビルドツール**: Vite（フロントエンド）+ wasm-pack（WASM コンパイル）
- **パッケージ管理**: pnpm のみ（npm / yarn 禁止）
- **アセンブラ・コンパイラ使用禁止**: Rust コードで 6502 命令を直接バイト値として扱う（アセンブラへの外部呼び出し禁止）
- **3層アーキテクチャ**:
  - `src/domain/`: CPU・PPU・バス・カートリッジのロジック（Rust）。DOM・JS に依存しない
  - `src/infrastructure/`: ROM パース・メモリマップ（Rust）。domain の実装詳細
  - `src/presentation/`: WASM バインディング（wasm-bindgen）+ TypeScript/HTML。外部への唯一の出口
- **依存の方向**: presentation → domain → infrastructure（逆方向の依存禁止）
- **Canvas サイズ**: NES ネイティブ解像度 256×240 を基準とする（拡大スケールは presentation 側で調整可）

---

## システム構成（コンポーネント依存関係）

```
[フロントエンド: TypeScript / Vite]
  - 依存している: WASM モジュール（wasm-bindgen 生成バインディング）、HTML5 Canvas API、Keyboard API
  - 依存されている: ブラウザ（ユーザーが直接操作）

[WASM バインディング: wasm-bindgen (presentation/)]
  - 依存している: domain 層（Rust Emulator struct）
  - 依存されている: TypeScript フロントエンド

[Emulator struct / Bus (domain/)]
  - 依存している: CPU, PPU, Cartridge（同 domain 層）
  - 依存されている: WASM バインディング

[CPU (domain/cpu.rs)]
  - 依存している: Bus（メモリ読み書き）
  - 依存されている: Emulator（ステップ実行）

[PPU (domain/ppu.rs)]
  - 依存している: Bus 経由の VRAM・OAM・パレット
  - 依存されている: Emulator（スキャンライン実行）

[Cartridge (domain/cartridge.rs)]
  - 依存している: Mapper（infrastructure/mapper.rs）
  - 依存されている: Bus（PRG/CHR 読み取り）

[Mapper 0 / NROM (infrastructure/mapper.rs)]
  - 依存している: ROM バイト列
  - 依存されている: Cartridge

[ROM パーサー (infrastructure/rom_parser.rs)]
  - 依存している: なし（バイト列の純粋なパース）
  - 依存されている: Cartridge 初期化時

[親プロジェクトの game.nes]
  - 依存している: なし
  - 依存されている: フロントエンド（ファイル選択 UI から読み込み）
```

---

<!-- 以下は後続エージェントが追記するセクション -->

## アーキテクチャ設計
<!-- /architect が追記。ディレクトリ構成・モジュール境界・ADR を記録する -->

## テスト計画
<!-- /tdd が追記 -->

## レビュー結果
<!-- /review が追記 -->

## デプロイ計画
<!-- /deploy が追記 -->
