# NES ROM バイナリ直接生成 実験プロジェクト 仕様書

## 目的

生成 AI がテキスト（コード・アセンブリ）を経由せず、バイナリを直接出力できるかを検証する実験プロジェクト。  
「ソースコードは人間の読みやすさのために存在していた。AI が生成・管理するなら人間向けの読みやすさは不要。ただし AI が読める必要はある」という設計哲学に基づき、Claude が直接読み書きできるアノテーション付きヘックスダンプ形式（`game.rom.txt`）を唯一のソースとする。現在の AI はバイナリを直接読めないが、テキスト表現されたバイト列（アノテーション付きヘックス）は読める。将来 AI がバイナリを直接読めるようになれば `.nes` だけで完結する設計にしておく。アセンブラ・コンパイラ工程なし。

### 機能ごとの目的

<!-- 変更を評価する物差し。後続エージェントは作業前に必ずここを確認すること -->

| 機能・コンポーネント | 目的（この機能が存在する理由） | 変えてはならない本質 |
|---|---|---|
| `game.rom.txt`（アノテーション付きヘックス） | AI が直接読み書きできる形式でバイナリを定義する | アセンブラ・コンパイラを介さず、AI が直接読み書きできる形式でバイナリを定義すること |
| 変換スクリプト（`game.rom.txt` → `game.nes`） | ヘックスダンプをバイトへ機械的にパースして `.nes` を生成する | 翻訳・コンパイルではなく、16進数→バイトの純粋な変換のみであること |
| iNES ヘッダー（`[header]` セクション） | エミュレータが ROM を識別できるようにする | iNES 形式の 16 バイトヘッダー仕様に準拠すること |
| PRG-ROM（`[prg_rom]` セクション） | 6502 機械語命令列をバイト列として定義する | バイトはすべて `game.rom.txt` のヘックスリテラルとして記述されること（中間ファイルなし） |
| CHR-ROM（`[chr_rom]` セクション） | スプライト・タイルのビットマップデータを定義する | 同上（`game.rom.txt` 内のヘックスリテラル直接記述） |
| ゲームロジック（PRG 内） | コントローラー入力・移動・当たり判定を実現する | 動作するゲームとして最低限機能すること |

---

## 振る舞い

1. ユーザーが変換スクリプトを実行する
2. スクリプトが `game.rom.txt` を読み込み、ヘックス文字列を解析して iNES 形式の `game.nes` を書き出す（機械的なパースのみ。翻訳・コンパイルなし）
3. 生成された `game.nes` を FCEUX / Mesen 等の NES エミュレータで開く
4. ゲームが起動し、コントローラー（キーボード）でスプライトを操作できる
5. 障害物または敵との当たり判定が機能する

### ゲームの最小仕様

- コントローラー 1 の方向キーでスプライトが移動する
- 画面上に障害物または敵が存在する
- プレイヤースプライトと障害物・敵の当たり判定が機能する（接触時に何らかのリアクション）

---

## 受け入れ条件

- [ ] `game.rom.txt` が `[header]`, `[prg_rom]`, `[chr_rom]`, `[vectors]` セクションを持つ
- [ ] `game.rom.txt` の各行が「ヘックスバイト列  # コメント」または空行・コメント行（`#` 始まり）である
- [ ] `game.rom.txt` を変換スクリプトで処理すると毎回同一の `game.nes` が生成される（再現性）
- [ ] 変換スクリプトを実行すると `game.nes` が生成される
- [ ] 生成されたファイルが FCEUX または Mesen でエラーなく起動する
- [ ] ゲーム起動後、プレイヤースプライトが画面上に表示される
- [ ] コントローラー 1 の上下左右キー入力でスプライトが対応方向に移動する
- [ ] 画面上に障害物または敵が 1 つ以上表示される
- [ ] プレイヤースプライトが障害物・敵に接触すると当たり判定が発動する（スコア変化・スプライト点滅・位置リセット等）
- [ ] 変換スクリプトのソースコードに `.asm` / `.s` ファイルへの書き出し処理が存在しない
- [ ] 変換スクリプトのソースコードに `subprocess` 等でアセンブラ・コンパイラを呼び出す処理が存在しない
- [ ] iNES ヘッダーが 16 バイトの正規形式（マジック: `4E 45 53 1A`、PRG バンク数、CHR バンク数、フラグ等）を満たす
- [ ] RESET ベクタ・NMI ベクタ・IRQ ベクタが正しく設定されている

---

## スコープ（やらないこと）

- 高度なゲームプレイ機能（音楽・SE・スコア表示・スクロール・複数ステージ）は含まない
- マッパー 0（NROM）以外のカートリッジマッパーは対象外
- 32KB PRG-ROM（NROM-256）は必要に応じて採用するが、16KB（NROM-128）で収まる場合は 16KB を優先
- NES 実機での動作確認は対象外（エミュレータのみ）
- `game.rom.txt` の人間向けリーダビリティの最適化（AI が読めれば十分）

---

## 固定要件

<!-- 技術的判断で変更してはならない要件。後続エージェントはここを必ず読むこと -->
<!-- 逸脱する場合はユーザーに報告して承認を得ること -->

- **正本ファイル**: `game.rom.txt`（アノテーション付きヘックスダンプ形式）を唯一の「ソース」とする
- **変換**: `game.rom.txt → game.nes` の変換は機械的なパース（16進数→バイト）のみ。翻訳・コンパイルではない
- **AI の読み書き対象**: Claude が生成・分析・改善するのは `game.rom.txt`
- **配布物**: `game.nes`（バイナリ）のみ。変換スクリプトは開発補助ツール
- アセンブラ（ca65, asm6, nesasm 等）を使用しない
- C コンパイラ（cc65 等）を使用しない
- 中間アセンブリファイル（`.asm` / `.s`）を生成しない
- CPU: MOS 6502（NES 版）の命令セットのみ使用する
- マッパー: NROM（Mapper 0）固定
- CHR-ROM: 8KB（1 バンク）固定
- iNES ヘッダー: 16 バイト固定形式

### game.rom.txt フォーマット仕様

```
# NES ROM — game.nes
# このファイルが正本。AIが読み書きする。配布物は game.nes のみ。

[header]
4E 45 53 1A  # iNES magic
01           # PRG-ROM バンク数
01           # CHR-ROM バンク数
00           # フラグ6（Mapper下位4bit・ミラーリング等）
00 00 00 00 00 00 00 00 00  # padding (9バイト)

[prg_rom]  # $8000〜（最大32KB）
# セクション内は「HH [HH...]  # コメント」の形式
# アドレスはコメントで示す

[chr_rom]  # グラフィックタイルデータ（8KB固定）

[vectors]  # $FFFA〜$FFFF（NMI・RESET・IRQベクタ）
```

- セクションヘッダー: `[section_name]` （`header` / `prg_rom` / `chr_rom` / `vectors`）
- データ行: `HH [HH ...]  # コメント`（`#` 以降はコメントとして無視）
- 空行・`#` で始まる行は無視する
- バイト列は大文字・小文字どちらの16進数でも可

---

## システム構成（コンポーネント依存関係）

- [正本ソース: `game.rom.txt`]
  - 依存している（このコンポーネントが使う）: なし（テキストファイル）
  - 依存されている（このコンポーネントを使う）: 変換スクリプト

- [変換スクリプト（`generate.py` 等）]
  - 依存している: `game.rom.txt`、Python 標準ライブラリのみ（`pathlib` 等）
  - 依存されている: ユーザーが実行する

- [生成対象: `game.nes`]
  - 依存している（このコンポーネントが使う）: なし（スタンドアロン ROM）
  - 依存されている（このコンポーネントを使う）: NES エミュレータ（FCEUX / Mesen）

- [PRG-ROM バイト列（`game.rom.txt` `[prg_rom]` セクション内）]
  - RESET ハンドラ → ゲームメインループ → コントローラー読み取り → スプライト更新 → 当たり判定
  - NMI ハンドラ → PPU 更新（OAM DMA）
  - IRQ ハンドラ → RTI のみ

- [CHR-ROM バイト列（`game.rom.txt` `[chr_rom]` セクション内）]
  - タイル 0: プレイヤースプライト
  - タイル 1 以降: 障害物・敵・背景タイル

---

<!-- 以下は後続エージェントが追記するセクション -->

## アーキテクチャ設計

### 1. NES メモリマップ

#### CPU アドレス空間（$0000〜$FFFF）

```
$0000〜$00FF  Zero Page RAM（256B）     変数・作業領域。アドレッシングが高速
$0100〜$01FF  Stack（256B）             ハードウェア固定。JSR/RTS/割り込みで使用
$0200〜$02FF  OAM Shadow（256B）        スプライト属性バッファ。$4014 DMA で PPU へ転送
$0300〜$07FF  General RAM（残り）       スタック・OAM 以外の作業領域（本プロジェクトでは未使用）
$0800〜$1FFF  RAM Mirror（×3）          $0000〜$07FF の繰り返し（未使用）
$2000〜$2007  PPU レジスタ              PPUCTRL, PPUMASK, PPUSTATUS, OAMADDR, OAMDATA, PPUSCROLL, PPUADDR, PPUDATA
$2008〜$3FFF  PPU レジスタ Mirror       $2000〜$2007 の繰り返し（未使用）
$4000〜$4017  APU / I/O レジスタ        コントローラー: $4016（write: strobe / read: P1）$4017（read: P2）
$4014         OAM DMA レジスタ          書き込みで OAM Shadow → PPU OAM 転送
$4018〜$7FFF  Cartridge Space           本プロジェクトでは未使用（NROM に RAM なし）
$8000〜$BFFF  PRG-ROM Bank 0（16KB）    ゲームコード・データ（唯一の PRG バンク）
$C000〜$FFFF  PRG-ROM Mirror（16KB）    $8000〜$BFFF と同一内容（NROM-128 ミラー）
$FFFA〜$FFFF  ベクタテーブル            NMI(FA-FB), RESET(FC-FD), IRQ(FE-FF)
```

#### PPU アドレス空間（$0000〜$3FFF）

```
$0000〜$0FFF  Pattern Table 0（4KB）   CHR-ROM の前半。背景タイル
$1000〜$1FFF  Pattern Table 1（4KB）   CHR-ROM の後半。スプライトタイル（本プロジェクトで使用）
$2000〜$23FF  Nametable 0（1KB）       画面レイアウト（タイルインデックス配列）
$2400〜$27FF  Nametable 1             水平ミラー時は Nametable 0 のミラー（NROM 固定）
$3F00〜$3F0F  Background Palette      背景パレット 4×4 色
$3F10〜$3F1F  Sprite Palette          スプライトパレット 4×4 色
```

---

### 2. PRG-ROM レイアウト（$8000〜$BFFF = 16KB）

NROM-128 なので $8000〜$BFFF の 16KB が唯一の PRG バンク。$C000〜$FFFF は同一内容のミラー。
ベクタテーブル ($FFFA〜$FFFF) は $BFFA〜$BFFF に相当する。

```
オフセット    CPUアドレス    内容
$0000         $8000          RESET ハンドラ（初期化コード）
                               - PPU 安定待ち（2 Vblank 待機）
                               - RAM ゼロクリア（$00〜$FF）
                               - OAM Shadow ゼロクリア（$0200〜$02FF）
                               - PPU 設定（PPUCTRL: NMI 有効・スプライトパターン $1000）
                               - PPUMASK 設定（スプライト・背景表示有効）
                               - スプライト初期位置セット
                               - ゲームメインループへ JMP
$00xx         $80xx          ゲームメインループ
                               - NMI フラグ待機（フレーム同期）
                               - READ_CONTROLLER ルーチン呼び出し
                               - UPDATE_PLAYER ルーチン呼び出し
                               - CHECK_COLLISION ルーチン呼び出し
                               - 無限ループ
$0100 付近    $8100 付近     READ_CONTROLLER サブルーチン
                               - $4016 に 1 書き込み（ストローブ ON）
                               - $4016 に 0 書き込み（ストローブ OFF）
                               - 8 回ビットシフトで 8 ボタン読み取り
                               - ボタン状態を ZP $10 に格納
$0150 付近    $8150 付近     UPDATE_PLAYER サブルーチン
                               - ZP のコントローラー入力を読む
                               - 上下左右ビットを確認して X/Y 座標を加算/減算
                               - 画面端クランプ（$08〜$E8 X, $08〜$D8 Y）
                               - OAM Shadow ($0200) の Y/X バイトを更新
$0200 付近    $8200 付近     CHECK_COLLISION サブルーチン
                               - プレイヤーと敵の AABB 判定
                               - 衝突時: プレイヤー座標をリセット位置へ
$0250 付近    $8250 付近     NMI ハンドラ
                               - レジスタ退避（PHA / TXA,PHA / TYA,PHA）
                               - OAM DMA: LDA #$02 / STA $4014
                               - NMI フラグセット（ZP $01 に $01 を書き込み）
                               - レジスタ復帰（PLA,TAY / PLA,TAX / PLA）
                               - RTI
$0280 付近    $8280 付近     IRQ ハンドラ
                               - RTI のみ
$3FFA         $BFFA          NMI ベクタ（low: NMI ハンドラ先頭アドレス $80+offset の low byte）
$3FFC         $BFFC          RESET ベクタ（low: $80, high: $80 → $8000）
$3FFE         $BFFE          IRQ ベクタ（low: IRQ ハンドラ先頭アドレスの low byte）
```

**ベクタ計算補足**: ミラーにより $FFFA = $BFFA、$FFFC = $BFFC、$FFFE = $BFFE。
`[vectors]` セクションに 6 バイト記述すれば変換スクリプトが $BFFA〜$BFFF に配置する。

---

### 3. CHR-ROM タイルレイアウト（8KB = Pattern Table 0 + Pattern Table 1）

各タイルは 16 バイト（プレーン 0: 8B + プレーン 1: 8B = 8×8 ピクセル 2bpp）。

```
Pattern Table 0 ($0000〜$0FFF): 背景タイル（256 タイル）
  タイル $00: 空白タイル（全バイト $00）
  タイル $01: 障害物タイル（8×8 の塗りつぶし四角）
  タイル $02〜$FF: 将来拡張用（現在は空白）

Pattern Table 1 ($1000〜$1FFF): スプライトタイル（256 タイル）
  タイル $00: プレイヤースプライト（8×8 の十字形）
  タイル $01: 敵スプライト（8×8 の菱形）
  タイル $02〜$FF: 将来拡張用（現在は空白）
```

PPUCTRL の bit 3 = 1 を設定することでスプライトのパターンテーブルを $1000 に指定する。

---

### 4. RAM 使用計画（ゼロページ $0000〜$00FF）

```
アドレス    変数名           用途
$00         NMI_FLAG         NMI 発生フラグ（0=待機中, 1=NMI 発生済み）。メインループがこれをポーリング
$01         GAME_STATE       ゲーム状態（0=プレイ中, 1=ヒット演出中）
$02         HIT_TIMER        ヒット演出タイマー（0=演出なし, 非0=カウントダウン）
$03         (予約)
$04〜$07    (予約)

$10         PAD1_RAW         コントローラー 1 の生ビット入力（bit7=A, 6=B, 5=Select, 4=Start, 3=Up, 2=Down, 1=Left, 0=Right）
$11         (予約)

$20         PLAYER_X         プレイヤースプライト X 座標（0〜255）
$21         PLAYER_Y         プレイヤースプライト Y 座標（0〜239）

$30         ENEMY_X          敵スプライト X 座標
$31         ENEMY_Y          敵スプライト Y 座標

$40〜$4F    (作業用)          サブルーチン内の一時変数
```

**スタックについて**: $0100〜$01FF はハードウェア固定。JSR/RTS と割り込みで自動的に使用される。

---

### 5. NMI ハンドラ設計（Vblank 同期・OAM DMA）

```
NMI 発生タイミング: PPU がフレームの Vblank 期間（ライン 241）に入ったとき
NMI を有効化: PPUCTRL ($2000) の bit 7 = 1

NMI ハンドラ処理順序:
  1. レジスタ退避（A, X, Y をスタックに PHA / TXA+PHA / TYA+PHA）
  2. OAM DMA 実行:
       LDA #$02
       STA $4014      ; $0200〜$02FF の内容を PPU OAM へ転送（513 CPU サイクル消費）
  3. NMI_FLAG ($00) に $01 をセット（メインループへの同期シグナル）
  4. レジスタ復帰（PLA+TAY / PLA+TAX / PLA）
  5. RTI

OAM DMA の注意:
  - $4014 への書き込みは Vblank 中に行う（NMI 内なので安全）
  - DMA 転送中は CPU が 513/514 サイクル停止する
  - $0200 以外を使う場合は STA $4014 の引数を変更する
```

---

### 6. ゲームループ設計（フレーム処理の順序）

```
RESET:
  └─ 初期化（PPU 安定待ち → RAM クリア → レジスタ設定）
  └─ JMP MAIN_LOOP

MAIN_LOOP:（毎フレーム 60Hz）
  1. NMI_FLAG ($00) が $01 になるまでビジーウェイト
       WAIT: LDA $00 / BEQ WAIT
  2. NMI_FLAG をクリア（LDA #$00 / STA $00）
  3. READ_CONTROLLER 呼び出し
       → PAD1_RAW ($10) を更新
  4. UPDATE_PLAYER 呼び出し
       → PAD1_RAW を参照してプレイヤー座標を更新
       → OAM Shadow ($0200+0: Y, $0200+3: X) を書き込み
  5. CHECK_COLLISION 呼び出し
       → プレイヤー・敵の AABB 判定
       → ヒット時: PLAYER_X/Y をリセット位置へ変更, HIT_TIMER をセット
  6. HIT_TIMER 減算（非0なら -1）
  7. JMP MAIN_LOOP（無限ループ）

割り込み:
  NMI（毎フレーム）: OAM DMA → NMI_FLAG セット
  IRQ: RTI のみ（本プロジェクトでは未使用）
```

---

### 7. 当たり判定アルゴリズム（AABB）

6502 に乗算命令はないため、加算・減算・比較命令だけで AABB を実装する。

**各スプライトのバウンディングボックス（8×8 ピクセルとして定義）**:
```
Left   = X
Right  = X + 8   (= X に 8 を加算)
Top    = Y
Bottom = Y + 8   (= Y に 8 を加算)
```

**判定条件（非衝突 = OR 条件、衝突 = すべての逆）**:
```
非衝突 ⟺
  PLAYER_X + 8 < ENEMY_X      ; プレイヤーが敵の左
  OR ENEMY_X + 8 < PLAYER_X   ; プレイヤーが敵の右
  OR PLAYER_Y + 8 < ENEMY_Y   ; プレイヤーが敵の上
  OR ENEMY_Y + 8 < PLAYER_Y   ; プレイヤーが敵の下
```

**6502 実装（バイト列コメント付き）**:
```
; PLAYER_X + 8 < ENEMY_X ?
  LDA PLAYER_X   ; A = プレイヤーX
  CLC
  ADC #$08       ; A = プレイヤーX + 8
  CMP ENEMY_X    ; プレイヤー右端 - 敵左端
  BCC NO_HIT     ; キャリークリア = プレイヤーが左に離れている

; ENEMY_X + 8 < PLAYER_X ?
  LDA ENEMY_X
  CLC
  ADC #$08
  CMP PLAYER_X
  BCC NO_HIT

; PLAYER_Y + 8 < ENEMY_Y ?
  LDA PLAYER_Y
  CLC
  ADC #$08
  CMP ENEMY_Y
  BCC NO_HIT

; ENEMY_Y + 8 < PLAYER_Y ?
  LDA ENEMY_Y
  CLC
  ADC #$08
  CMP PLAYER_Y
  BCC NO_HIT

HIT:
  ; ヒット処理: プレイヤーを初期位置 (X=$80, Y=$80) にリセット
  LDA #$80
  STA PLAYER_X
  STA PLAYER_Y
  LDA #$1E       ; HIT_TIMER = 30 フレーム
  STA HIT_TIMER
NO_HIT:
  RTS
```

---

### 8. スプライトデータ構造（OAM: $0200〜$02FF）

NES OAM は最大 64 スプライトを保持する。各スプライト 4 バイト。

```
OAM エントリフォーマット（4 バイト）:
  Byte 0: Y 座標（0〜239。画面に表示するには実際の Y - 1 を書き込む）
  Byte 1: タイルインデックス（Pattern Table 1 内のタイル番号）
  Byte 2: 属性
            bit 7-6: フリップ（垂直/水平）
            bit 5:   優先度（0=前面, 1=背景の後ろ）
            bit 1-0: パレット番号（スプライトパレット 0〜3）
  Byte 3: X 座標（0〜255）
```

**本プロジェクトの OAM Shadow 割り当て（$0200〜$020F）**:

```
$0200  SPRITE_0_Y     プレイヤー Y（初期値 $80）
$0201  SPRITE_0_TILE  プレイヤータイルインデックス（= $00）
$0202  SPRITE_0_ATTR  プレイヤー属性（パレット 0）
$0203  SPRITE_0_X     プレイヤー X（初期値 $80）

$0204  SPRITE_1_Y     敵 Y（初期値 $40）
$0205  SPRITE_1_TILE  敵タイルインデックス（= $01）
$0206  SPRITE_1_ATTR  敵属性（パレット 1）
$0207  SPRITE_1_X     敵 X（初期値 $C0）

$0208〜$02FF  未使用スプライト（全バイト $FF で画面外）
```

---

### 9. 変換スクリプト設計（`game.rom.txt` → `game.nes`）

#### コンポーネント分割（3 層アーキテクチャ）

```
presentation/（CLI エントリポイント）
  generate.py     コマンドライン引数処理・エラー表示・ファイル入出力

domain/（パース・バイト列構築ロジック）
  parser.py       game.rom.txt のテキストをセクション辞書に変換する
  builder.py      セクション辞書から iNES バイト列を構築する

infrastructure/（ファイルアクセス）
  ← generate.py が直接 pathlib を使う（規模が小さいため）
```

#### パーサー仕様（`parser.py`）

```
入力: game.rom.txt のテキスト（文字列）
出力: dict[str, list[int]]
  {
    "header":  [バイト列（16 バイト）],
    "prg_rom": [バイト列（最大 16384 バイト）],
    "chr_rom": [バイト列（8192 バイト）],
    "vectors": [バイト列（6 バイト）],
  }

処理規則:
  1. 行単位で処理する
  2. `#` で始まる行・空行はスキップ
  3. `[section_name]` 行でカレントセクションを切り替える
     - 認識セクション: header / prg_rom / chr_rom / vectors
     - 未知のセクション名は ParseError を送出
  4. データ行: `#` より前の部分を取り出し、空白区切りでトークン化
     - 各トークンを int(token, 16) で整数変換
     - 変換失敗は ParseError を送出
  5. 変換した整数リストをカレントセクションのリストに append

バリデーション（builder.py が行う）:
  - header が 16 バイト以外 → BuildError
  - header[0:4] が [0x4E, 0x45, 0x53, 0x1A] 以外 → BuildError
  - prg_rom が 16384 バイト超（NROM-128 上限） → BuildError
  - chr_rom が 8192 バイト超 → BuildError
  - vectors が 6 バイト以外 → BuildError
  - 各バイト値が 0〜255 の範囲外 → ParseError
```

#### ビルダー仕様（`builder.py`）

```
入力: パーサー出力の dict
出力: bytes（iNES 形式のバイト列）

処理:
  1. header バイト列（16 バイト）をそのまま先頭に配置
  2. prg_rom バイト列を 16384 バイトに 0x00 パディング（末尾）
  3. vectors バイト列（6 バイト）を prg_rom の末尾 6 バイトに上書き
     - prg_rom[16378] = vectors[0]  ; NMI low
     - prg_rom[16379] = vectors[1]  ; NMI high
     - prg_rom[16380] = vectors[2]  ; RESET low
     - prg_rom[16381] = vectors[3]  ; RESET high
     - prg_rom[16382] = vectors[4]  ; IRQ low
     - prg_rom[16383] = vectors[5]  ; IRQ high
  4. chr_rom バイト列を 8192 バイトに 0x00 パディング（末尾）
  5. 結合: header + prg_rom + chr_rom = 16 + 16384 + 8192 = 24592 バイト
  6. bytes として返す

アセンブラ・コンパイラ呼び出しは一切行わない（固定要件）
subprocess の使用禁止（固定要件）
```

#### 処理フロー図

```
game.rom.txt (テキスト)
    │
    ▼
[parser.parse(text)] ── ParseError → エラー表示して終了
    │
    ▼
dict { header, prg_rom, chr_rom, vectors }
    │
    ▼
[builder.build(sections)] ── BuildError → エラー表示して終了
    │
    ▼
bytes（iNES バイナリ）
    │
    ▼
game.nes（ファイル書き出し）
```

---

### ADR

#### ADR-1: NROM-128（16KB PRG）採用

**状況:** NROM には 16KB（NROM-128）と 32KB（NROM-256）の 2 種類がある。
**判断:** NROM-128 を採用し、必要なら NROM-256 に切り替える。
**理由:** 最小ゲームのコードは数百バイト程度で収まる見込みであり、16KB で十分。$8000〜$BFFF と $C000〜$FFFF が同一内容ミラーになるため、ベクタテーブルは $BFFA〜$BFFF に配置される。これにより iNES ヘッダーの PRG バンク数は 1 のままで済む。
**影響:** ベクタアドレスの計算時に「$FFFA = $BFFA（PRG 先頭からの相対オフセット $3FFA）」を意識する必要がある。

#### ADR-2: OAM Shadow を $0200〜$02FF に固定

**状況:** OAM DMA（$4014 への書き込み）は RAM の 256 バイト境界から PPU OAM へ転送する。どのページを使うかを決める必要がある。
**判断:** $0200〜$02FF（RAM ページ 2）を OAM Shadow として使用する。
**理由:** NES 開発の慣習的な標準アドレスであり、エミュレータ・デバッガのデフォルト表示もこのアドレスを想定していることが多い。$4014 に書き込む値は `#$02` で固定。
**影響:** $0200〜$02FF を他の用途に使ってはならない。

#### ADR-3: NMI フラグによるフレーム同期

**状況:** メインループを 60Hz に同期させる方法を決める必要がある。
**判断:** ゼロページ $00（NMI_FLAG）を使ったビジーウェイト方式を採用する。NMI ハンドラが $01 をセット、メインループがポーリングして検出後 $00 にクリア。
**理由:** NES でもっとも一般的なフレーム同期パターン。簡潔で信頼性が高い。スピンウェイト中は他の処理が入らないが、このゲームでは問題にならない規模。
**影響:** NMI が発生しない状態（PPUCTRL の NMI ビット未設定）ではメインループが永久停止する。RESET ハンドラで PPUCTRL の bit7 を必ず 1 にセットすること。

#### ADR-4: 変換スクリプトを Python + 標準ライブラリのみで実装

**状況:** 変換スクリプトの実装言語と依存を決める必要がある。
**判断:** Python 3 の標準ライブラリ（`pathlib`, `sys`）のみを使用する。
**理由:** 外部依存ゼロにすることで「誰でも実行できる」要件を満たす。SPEC.md の固定要件「Python 標準ライブラリのみ」に合致する。`uv run generate.py` で実行できる。
**影響:** バリデーション・パースが複雑になっても外部ライブラリに頼れない。ただし本プロジェクトの規模では問題なし。

#### ADR-5: 3 層アーキテクチャ（presentation/domain/infrastructure）の適用

**状況:** 変換スクリプトは単一スクリプトで実現できる規模だが、テスト容易性と責務分離を考慮する必要がある。
**判断:** `generate.py`（CLI）/ `parser.py`（パース）/ `builder.py`（バイト列構築）に分割する。
**理由:** Global CLAUDE.md の 3 層アーキテクチャ原則に従う。パースロジックとバイト列構築ロジックを domain 層として分離することで、将来の単体テストが可能になる。CLI 部分（presentation）は domain に依存するが、domain は CLI に依存しない。
**影響:** ファイルが 3 つになるが、各ファイルの責務が明確になる。テストは `parser.py` と `builder.py` を直接 import してテストできる。

## テスト計画

### テストケース（受け入れ条件より）

| 受け入れ条件 | テストケース | 結果 |
|---|---|---|
| `game.rom.txt` が 4 セクションを持つ | test_parser_sections_present | ✅ PASS |
| 各行が正しい形式（ヘックスバイト列 # コメント） | test_parser_valid_line_format | ✅ PASS |
| 変換スクリプトで同一の `game.nes` が生成される（再現性） | test_builder_deterministic | ✅ PASS |
| 変換スクリプト実行で `game.nes` が生成される | generate.py で確認（24592 bytes 生成） | ✅ PASS |
| iNES ヘッダーマジック `4E 45 53 1A` が先頭 4 バイト | test_builder_ines_magic | ✅ PASS |
| iNES バイナリが 24592 バイト | test_builder_output_size | ✅ PASS |
| ベクタが prg_rom 末尾 6 バイトに正しく配置される | test_builder_vectors_placement | ✅ PASS |
| prg_rom が 16384 バイトにパディングされる | test_builder_prg_padding | ✅ PASS |
| chr_rom が 8192 バイトにパディングされる | test_builder_chr_padding | ✅ PASS |
| 不正なヘックス値で ParseError | test_parser_invalid_hex | ✅ PASS |
| 未知のセクション名で ParseError | test_parser_unknown_section | ✅ PASS |
| header が 16 バイト以外で BuildError | test_builder_invalid_header_length | ✅ PASS |
| header マジック不一致で BuildError | test_builder_invalid_magic | ✅ PASS |
| prg_rom が 16384 バイト超で BuildError | test_builder_prg_overflow | ✅ PASS |
| vectors が 6 バイト以外で BuildError | test_builder_invalid_vectors_length | ✅ PASS |
| `.asm`/`.s` 書き出し・アセンブラ呼び出しが存在しない | 静的確認（`import` なし・grep 確認） | ✅ PASS |
| subprocess を使用しない | 静的確認（`import subprocess` なし、コメントのみ） | ✅ PASS |
| iNES ヘッダー 16 バイト正規形式 | test_builder_ines_magic + test_builder_header_is_exact | ✅ PASS |
| RESET/NMI/IRQ ベクタ正しく設定 | test_builder_vectors_placement（NMI=$81B1, RESET=$8000, IRQ=$81C5 確認） | ✅ PASS |

**テスト実行結果: 28 tests passed in 0.02s（2026-05-08）**

### テスト環境
- フレームワーク: pytest 9.0.3
- Python: 3.11.4
- 実行コマンド: `uv run pytest`
- テストファイル: `tests/test_parser.py`（12テスト）, `tests/test_builder.py`（16テスト）
- 分離方針: 外部ファイル I/O は generate.py のみ。domain 層はすべてインメモリでテスト可能

### 実装ファイル
| ファイル | 役割 | 説明 |
|---|---|---|
| `game.rom.txt` | 正本ソース | アノテーション付きヘックスダンプ。6502 機械語バイト列直接記述 |
| `generate.py` | presentation 層 | CLI エントリポイント。`game.rom.txt` → `game.nes` |
| `domain/parser.py` | domain 層 | テキスト → セクション辞書 |
| `domain/builder.py` | domain 層 | セクション辞書 → iNES バイト列（24592 bytes） |
| `tests/test_parser.py` | テスト | parser.py の単体テスト（12 ケース） |
| `tests/test_builder.py` | テスト | builder.py の単体テスト（16 ケース） |

## レビュー結果
<!-- /review が追記 -->

## デプロイ計画
<!-- /deploy が追記 -->
