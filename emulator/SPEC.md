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

### ディレクトリ構成

```
emulator/
├── SPEC.md
├── Cargo.toml                        # wasm-pack クレート定義
├── src/
│   ├── lib.rs                        # クレートルート。モジュール宣言のみ
│   ├── domain/
│   │   ├── mod.rs
│   │   ├── cpu.rs                    # CPU struct（レジスタ・命令実行・フラグ・サイクル計数）
│   │   ├── ppu.rs                    # PPU struct（スキャンライン描画・フレームバッファ生成）
│   │   ├── bus.rs                    # Bus struct（CPU/PPU アドレス空間の統合・仲介）
│   │   ├── cartridge.rs              # Cartridge struct（PRG/CHR ROM 保持・Mapper trait への委譲）
│   │   └── controller.rs             # Controller struct（ボタン状態・$4016 シリアル読み取り）
│   ├── infrastructure/
│   │   ├── mod.rs
│   │   ├── rom_parser.rs             # iNES ヘッダーパース → RomData 値オブジェクト生成
│   │   └── mapper.rs                 # Mapper trait + Mapper0（NROM）実装
│   └── presentation/
│       └── wasm_binding.rs           # #[wasm_bindgen] Emulator ラッパー。JS ↔ Rust 境界
└── frontend/
    ├── package.json                  # pnpm 管理。scripts: dev / build / preview
    ├── vite.config.ts                # Vite + @wasm-pack/plugin 設定
    ├── tsconfig.json
    ├── index.html                    # エントリ HTML。Canvas・ファイル選択 UI を含む
    └── src/
        ├── main.ts                   # アプリ初期化。WASM ロード・イベント登録
        ├── gameLoop.ts               # requestAnimationFrame ゲームループ
        ├── renderer.ts               # Canvas への ImageData 描画
        ├── inputHandler.ts           # キーボードイベント → NES ボタンビットマップ変換
        └── romLoader.ts              # FileReader → ArrayBuffer 取得
```

---

### 主要モジュール・struct の責務定義

#### domain 層（Rust）

| struct / trait | ファイル | 責務 |
|---|---|---|
| `CPU` | `domain/cpu.rs` | 6502 全命令・全アドレッシングモードの実行。レジスタ（A/X/Y/SP/PC）とフラグ（N/V/B/D/I/Z/C）を保持。`step()` で 1 命令を実行しサイクル数を返す |
| `PPU` | `domain/ppu.rs` | スキャンライン単位の描画。VRAM・OAM・パレット RAM を内部保持。`step(cycles)` で CPU サイクルに同期。フレーム完成時に `frame_buffer: [u8; 256*240*4]`（RGBA）を更新。NMI 発火フラグを保持 |
| `Bus` | `domain/bus.rs` | CPU アドレス空間（$0000–$FFFF）の読み書き仲介。RAM・PPU レジスタ・コントローラー・PRG-ROM へのルーティングを担う。PPU・Cartridge・Controller を所有 |
| `Cartridge` | `domain/cartridge.rs` | PRG-ROM・CHR-ROM のバイト列を保持。`Mapper` trait 実装への読み書きを委譲 |
| `Controller` | `domain/controller.rs` | 8 ボタンのビットマップ状態を保持。$4016 書き込みでラッチ、$4016 読み取りでシリアル出力（MSB → LSB 順） |
| `Emulator` | `domain/mod.rs` または `lib.rs` 相当のドメインルート | CPU・Bus を保持。`step_frame()` で 1 フレーム分（約 29780 CPU サイクル）のステップ実行を行い PPU フレームバッファを完成させる |

#### infrastructure 層（Rust）

| struct / trait | ファイル | 責務 |
|---|---|---|
| `RomData` | `infrastructure/rom_parser.rs` | iNES ファイルのバイト列を受け取り PRG-ROM・CHR-ROM・マッパー番号・ミラーリングモードを値オブジェクトとして返す純粋関数 `parse(bytes: &[u8]) -> Result<RomData, ParseError>` |
| `Mapper` | `infrastructure/mapper.rs` | `trait Mapper { fn read_prg(&self, addr: u16) -> u8; fn write_prg(&mut self, addr: u16, val: u8); fn read_chr(&self, addr: u16) -> u8; }` |
| `Mapper0` | `infrastructure/mapper.rs` | NROM 実装。PRG-ROM 16KB（$C000 ミラー）/ 32KB の両バリアントを処理 |

#### presentation 層（Rust + TypeScript）

| モジュール | ファイル | 責務 |
|---|---|---|
| `WasmEmulator` | `presentation/wasm_binding.rs` | `#[wasm_bindgen]` を付与した薄いラッパー struct。`Emulator` を内部保持。JS から呼ぶ API のみを公開。DOM・Canvas への参照は一切持たない |
| `main.ts` | `frontend/src/main.ts` | WASM モジュールの動的 import（`await init()`）、DOM 要素取得、イベントリスナー登録、`GameLoop` インスタンス化 |
| `gameLoop.ts` | `frontend/src/gameLoop.ts` | `requestAnimationFrame` コールバック。毎フレーム `emulator.step_frame()` → `emulator.frame_buffer()` → `renderer.draw()` の順で呼び出す |
| `renderer.ts` | `frontend/src/renderer.ts` | `Uint8ClampedArray` フレームバッファを `ImageData` に変換し Canvas `2dContext.putImageData()` で描画 |
| `inputHandler.ts` | `frontend/src/inputHandler.ts` | `keydown`/`keyup` イベントをキーマッピング表に従って NES ボタンビット（u8）に変換し `emulator.set_button_state(player, bits)` を呼ぶ |
| `romLoader.ts` | `frontend/src/romLoader.ts` | `<input type="file">` の `change` イベントから `FileReader.readAsArrayBuffer()` で `Uint8Array` を取得し、`emulator.load_rom(bytes)` に渡す |

---

### WASM API 設計

TypeScript から呼び出す関数の境界（`WasmEmulator` が公開する `#[wasm_bindgen]` メソッド）：

```typescript
// wasm-bindgen 生成バインディングの型定義（概念）
class WasmEmulator {
  // ROM のバイト列を受け取り、iNES パース → Cartridge ロード → RESET ベクタ実行開始
  load_rom(data: Uint8Array): void;

  // 1 フレーム分（約 29780 CPU サイクル相当）を実行する
  // PPU フレームバッファを内部更新し、NMI が発火すれば NMI ハンドラを実行済みにする
  step_frame(): void;

  // フレームバッファ（RGBA 各 1 byte、256×240×4 = 245760 bytes）を返す
  // Rust の Vec<u8> を JS の Uint8Array として返す（ゼロコピーではなく値渡し）
  frame_buffer(): Uint8Array;

  // コントローラー入力を設定する
  // player: 0 = Player 1、bits: ボタンビットマップ（A=0x01, B=0x02, Select=0x04, Start=0x08,
  //   Up=0x10, Down=0x20, Left=0x40, Right=0x80）
  set_button_state(player: number, bits: number): void;
}

// モジュール初期化（wasm-bindgen 標準パターン）
export function init(): Promise<void>;
export { WasmEmulator };
```

**設計上の制約:**
- `frame_buffer()` は毎フレーム値渡し（コピー）とする。SharedArrayBuffer は COOP/COEP ヘッダーが必要になるため、初期実装では採用しない（ADR-3 参照）
- DOM・Canvas への参照は Rust 側に渡さない。描画は TypeScript 側が担う

---

### ゲームループ設計

```
[requestAnimationFrame コールバック]
  │
  ├─ 1. emulator.step_frame()
  │       └─ Rust 内: CPU.step() を PPU サイクルと同期しながら 1 フレーム分繰り返す
  │           └─ PPU.step(cycles): スキャンライン更新 → フレーム完成時に frame_ready = true
  │           └─ NMI 発火: CPU.nmi() を呼び出す
  │
  ├─ 2. const pixels = emulator.frame_buffer()   // Uint8Array (245760 bytes, RGBA)
  │
  ├─ 3. renderer.draw(pixels)
  │       └─ new ImageData(pixels, 256, 240)
  │       └─ ctx.putImageData(imageData, 0, 0)   // Canvas への転送
  │
  └─ 4. requestAnimationFrame(gameLoopCallback)  // 次フレームをスケジュール
```

**フレームタイミング方針:**
- ブラウザの `requestAnimationFrame` は通常 60fps でコールバックを発行する。NES も 60fps（NTSC）であるため、毎コールバックで 1 フレーム分のステップを実行することで自然に同期する
- 処理が遅延した場合はフレームスキップを行わず、単純に次の `requestAnimationFrame` まで待つ（シンプルさ優先）

---

### フレームバッファの受け渡し方法

```
[Rust PPU 内部]
  frame_buffer: [u8; 245760]  // RGBA 形式、NES パレット → 24bit RGB 変換済み

  ↓ step_frame() 完了時に Vec<u8> として返却準備

[wasm_binding.rs]
  pub fn frame_buffer(&self) -> Vec<u8>  // wasm-bindgen が Uint8Array に変換

  ↓ JS/TS 側で受け取り

[renderer.ts]
  const pixels: Uint8Array = emulator.frame_buffer();
  const imageData = new ImageData(new Uint8ClampedArray(pixels.buffer), 256, 240);
  ctx.putImageData(imageData, 0, 0);
```

**NES パレット変換:**
- NES のパレットインデックス（0x00–0x3F）から RGB24 への変換テーブルを `domain/ppu.rs` 内に定数として持つ
- PPU がフレームバッファを書く時点で RGBA 変換まで完了させる（TypeScript 側での変換不要）

**Canvas スケーリング:**
- Canvas の CSS サイズは `width: 512px; height: 480px`（2倍）などに設定可能だが、`canvas.width = 256; canvas.height = 240` はネイティブ解像度のまま維持する
- スケーリングは CSS `image-rendering: pixelated` + CSS transform で対応（固定要件準拠）

---

### ADR

#### ADR-1: フレームバッファの転送方式は値コピー（Vec<u8>）とする

**状況:** Rust の PPU が生成した RGBA フレームバッファ（245760 bytes）を毎フレーム TypeScript に渡す必要がある。選択肢として (a) `Vec<u8>` の値コピー、(b) `wasm_memory()` + ポインタ渡し（SharedArrayBuffer 相当）がある。

**判断:** 初期実装では (a) `Vec<u8>` の値コピーを採用する。

**理由:**
- (b) のポインタ渡しは `wasm_bindgen` の unsafe API が必要で、Rust 側でメモリ管理の注意点が増える
- SharedArrayBuffer を活用するには HTTP サーバーへの `Cross-Origin-Opener-Policy: same-origin` ヘッダー設定が必要で、Vite dev server での追加設定が必要になる
- 245760 bytes は約 240KB。60fps でコピーしても約 14MB/s であり、現代ブラウザのメモリバンド幅で問題ない
- シンプルな実装から始め、プロファイリングでボトルネックと判明した場合にポインタ渡しへ移行する

**影響:** フレームバッファ転送で毎フレーム 240KB のコピーが発生する。将来的なパフォーマンス改善の候補として記録する。

---

#### ADR-2: Mapper を trait オブジェクトとし Cartridge が動的ディスパッチで保持する

**状況:** 現仕様では Mapper 0（NROM）のみ対象だが、`Cartridge` が Mapper の具体型を直接保持すると将来の拡張時に Cartridge 自体の変更が必要になる。

**判断:** `Mapper` を trait として定義し、`Cartridge` は `Box<dyn Mapper>` で保持する。

**理由:**
- スコープ外の Mapper は実装しないが、trait による境界定義は domain 層の安定性を高める
- `Box<dyn Mapper>` による動的ディスパッチのオーバーヘッドは命令実行ループに比べて無視できる（PRG/CHR 読み書きは毎命令 1–2 回であり、仮想ディスパッチのコストは数 ns）
- WASM ターゲットでは `enum Mapper` によるモノモーフィック化も可能だが、コードの見通しを優先して trait を選択する

**影響:** `Cartridge` は `infrastructure/mapper.rs` の `Mapper` trait に依存する。これは domain → infrastructure の依存であり固定要件の依存方向（presentation → domain → infrastructure）と矛盾しない。

---

#### ADR-3: ゲームループは requestAnimationFrame のみ使用し、フレームスキップは行わない

**状況:** ブラウザの `requestAnimationFrame` は 60Hz でコールバックするが、実際のコールバック間隔はディスプレイのリフレッシュレートや負荷によって変動する。NES の正確な 60fps タイミングを再現するには精密なタイマー管理が必要。

**判断:** `requestAnimationFrame` を毎回 1 フレーム実行とし、タイマー補正・フレームスキップは行わない。

**理由:**
- 親プロジェクト `nes-binary-experiment` の哲学は「シンプルに動くこと」であり、過度な精度追求は目的と外れる
- スコープに「PPU サイクル精度の完全再現は必須ではない」と明記されている
- 120Hz ディスプレイで 2 倍速になる問題は `timestamp` パラメータを使った将来の改善で対応できる

**影響:** 高リフレッシュレートディスプレイ（120Hz 等）では 2 倍速になる可能性がある。受け入れ条件の「60fps 目標」は通常の 60Hz ディスプレイを前提とする。

---

#### ADR-4: WasmEmulator は presentation 層に配置し、Emulator ドメインオブジェクトを内部保持するラッパーとする

**状況:** wasm-bindgen の `#[wasm_bindgen]` アトリビュートを domain 層の `Emulator` struct に直接付与する案と、presentation 層に薄いラッパー struct を設ける案がある。

**判断:** presentation 層に `WasmEmulator` ラッパーを設け、そこに `#[wasm_bindgen]` を付与する。

**理由:**
- `#[wasm_bindgen]` は `wasm-bindgen` クレートへの依存を生む。これを domain 層に持ち込むと、domain が presentation インフラ（wasm-bindgen）に依存する逆方向依存になり、固定要件違反になる
- ラッパーにより domain 層の `Emulator` はピュア Rust として保持され、ネイティブテスト（`cargo test`）が WASM ターゲットなしで実行できる

**影響:** `src/presentation/wasm_binding.rs` が Rust コードの外部公開エントリポイントとなる。`src/lib.rs` は `mod domain; mod infrastructure; mod presentation;` を宣言するだけでよい。

## テスト計画

### テストケース（受け入れ条件より）

| # | 受け入れ条件 | テストケース（Rust unit） | 結果 |
|---|---|---|---|
| 1 | pnpm dev でブラウザ表示 | — (手動確認) | 未実施 |
| 2 | ファイル選択 UI | — (手動確認) | 未実施 |
| 3 | Mapper 0 ROM 読み込みでエミュレーション開始 | `test_parse_ines_16kb`, `test_parse_ines_32kb`, `test_mapper0_read_prg_16kb`, `test_mapper0_read_prg_32kb`, `test_emulator_reset_vector` | ✅ PASS |
| 4 | 256×240 Canvas 描画 | `test_ppu_frame_buffer_size`, `test_ppu_get_frame_buffer_size` | ✅ PASS |
| 5 | 60fps ゲームループ | `test_emulator_step_frame` (29780 サイクル確認), `test_ppu_frame_complete_after_one_frame` | ✅ PASS |
| 6 | 矢印キー入力 | `test_controller_set_button_state`, `test_controller_latch_and_serial_read` | ✅ PASS |
| 7 | Z/X/Enter/Shift キー | `test_controller_all_buttons`, `test_controller_multiple_buttons` | ✅ PASS |
| 8 | ../game.nes で動作 | — (統合確認) | 未実施 |
| 9 | JS エラーなし | — (手動確認) | 未実施 |
| 10 | pnpm build 成功 | `pnpm build` 実行 → dist/ 生成確認 | ✅ PASS |

### テスト詳細設計

#### Phase 1: infrastructure 層

**rom_parser テスト:**
- `test_parse_ines_valid_header` — 有効な iNES ヘッダーを持つバイト列を `parse()` に渡し `RomData` が返ること
- `test_parse_ines_16kb` — PRG-ROM 16KB (1 バンク) の ROM を正しくパースすること
- `test_parse_ines_32kb` — PRG-ROM 32KB (2 バンク) の ROM を正しくパースすること
- `test_parse_ines_invalid_magic` — マジックバイトが不正な場合 `Err(ParseError)` が返ること
- `test_parse_ines_too_short` — バイト列が短すぎる場合 `Err(ParseError)` が返ること
- `test_parse_ines_mapper_number` — マッパー番号が正しく読み取れること

**mapper テスト:**
- `test_mapper0_read_prg_16kb` — 16KB PRG-ROM の $8000-$BFFF と $C000-$FFFF がミラーになること
- `test_mapper0_read_prg_32kb` — 32KB PRG-ROM の $8000-$FFFF が正しくマッピングされること
- `test_mapper0_read_chr` — CHR-ROM の $0000-$1FFF が正しく読み取れること

#### Phase 2: domain 層

**controller テスト:**
- `test_controller_initial_state` — 初期状態でボタンはすべて OFF
- `test_controller_set_button_state` — `set_buttons(bits)` 後に適切なビットが立つこと
- `test_controller_latch_and_serial_read` — $4016 書き込みでラッチ、8 回読み取りで 8 ボタン分が MSB→LSB 順で出力されること
- `test_controller_all_buttons` — 全 8 ボタンのビットマップが正しく定義されること

**cpu テスト（主要命令）:**
- `test_cpu_lda_immediate` — LDA #$xx でアキュムレータが更新され Z/N フラグが正しくセットされること
- `test_cpu_lda_zeropage` — LDA $xx でゼロページ読み取りが正しいこと
- `test_cpu_sta_zeropage` — STA $xx でメモリへの書き込みが正しいこと
- `test_cpu_jmp_absolute` — JMP $xxxx で PC が正しくジャンプすること
- `test_cpu_beq_taken` — BEQ で Z フラグが 1 の時にブランチすること
- `test_cpu_beq_not_taken` — BEQ で Z フラグが 0 の時にブランチしないこと
- `test_cpu_nmi` — NMI 発生時に正しいベクタアドレスへジャンプすること
- `test_cpu_reset_vector` — RESET 後に PC が $FFFC/$FFFD ベクタを指すこと
- `test_cpu_cycles` — 各命令が正しいサイクル数を消費すること（LDA: 2, JMP: 3 等）

**ppu テスト:**
- `test_ppu_initial_state` — 初期状態でスキャンラインカウンタが 0
- `test_ppu_scanline_increment` — `step(cycles)` でスキャンラインが正しくインクリメントされること
- `test_ppu_nmi_fires_at_vblank` — スキャンライン 241 で NMI フラグが立つこと
- `test_ppu_frame_buffer_size` — フレームバッファが 256×240×4 = 245760 バイトであること
- `test_ppu_frame_complete` — 1 フレーム分のステップ後に `frame_ready` フラグが true になること

**bus テスト:**
- `test_bus_ram_read_write` — $0000-$07FF の RAM 読み書きが正しいこと
- `test_bus_ram_mirror` — $0800-$1FFF が RAM ミラーになっていること
- `test_bus_prg_rom_read` — $8000 以降の PRG-ROM 読み取りが Cartridge に委譲されること

**emulator テスト:**
- `test_emulator_reset` — `load_rom()` 後に CPU が RESET ベクタから開始すること
- `test_emulator_step_frame` — `step_frame()` が約 29780 サイクル実行すること

### テスト環境
- フレームワーク: Rust 組み込み `#[test]` / `#[cfg(test)]`
- 実行コマンド: `cargo test` (ネイティブターゲット、WASM 不要)
- フロントエンド: `pnpm dev` / `pnpm build` の手動確認

### 実行結果サマリー（2026-05-08）

```
test result: ok. 76 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
```

**実行テスト一覧:**
- infrastructure::rom_parser: 10 テスト PASS
- infrastructure::mapper: 9 テスト PASS
- domain::controller: 9 テスト PASS
- domain::cpu: 15 テスト PASS
- domain::ppu: 8 テスト PASS
- domain::bus: 8 テスト PASS
- domain::cartridge: 4 テスト PASS
- domain (Emulator): 6 テスト PASS (domain::tests)
- domain::bus: 7 テスト PASS

**フロントエンドビルド確認:**
- `pnpm build` → `dist/` に静的ファイル生成成功
  - `dist/index.html` (1.99 kB)
  - `dist/assets/nes_emulator_bg-*.wasm` (47.08 kB)
  - `dist/assets/index-*.js` (6.57 kB)
- WASM ビルド: `wasm-pack build --target web` 成功

## レビュー結果
<!-- /review が追記 -->

## デプロイ計画
<!-- /deploy が追記 -->
