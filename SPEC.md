# speech-tap 仕様書

macOS のアプリごとの音声をキャプチャし、Apple の SpeechAnalyzer フレームワークで
リアルタイムに文字起こしする常駐アプリ。

---

## 目的

オンライン会議・ブラウザ動画・他者の発話など、特定アプリから出力される音声を
ユーザーが手作業で記録することなく、リアルタイムにテキスト化したい。

既存の文字起こしツールはマイク入力（自分の発話）か、システム全体の音声を対象とすることが多く、
「このアプリの音声だけ」を選んで文字化することが難しい。本アプリは macOS のプロセス／アプリ単位の
音声タップと、オンデバイスで動作する Apple SpeechAnalyzer を組み合わせ、
クラウドに音声を送ることなく、選択したアプリの音声だけをローカルで文字化し続ける常駐アプリを実現する。

### 機能ごとの目的

| 機能・コンポーネント | 目的（この機能が存在する理由） | 変えてはならない本質 |
|---|---|---|
| メニューバー常駐 UI | ユーザーが他作業をしながら、最小の操作で文字化の開始・停止・対象選択ができるようにする | バックグラウンドで邪魔をせず常駐し続けること／いつでも素早く操作できること |
| 対象アプリ選択 | 「どのアプリの音声を文字化するか」をユーザーが明示的に選べるようにする | 選んだアプリ**だけ**が対象になること（他アプリ音声の非混入） |
| アプリ別オーディオ取得 | 選択したアプリの音声のみを PCM として取り込む | 対象アプリの音声のみを取得し、他アプリ・マイク・システム音を混入させないこと |
| リアルタイム文字化（SpeechAnalyzer） | 取り込んだ音声をオンデバイスで遅延少なく文字化する | オンデバイスで完結すること（音声を外部送信しない）／実用的な遅延でテキストが更新されること |
| 文字起こし表示・保存 | 文字化結果をユーザーが読め、後から参照できるようにする | 確定結果を取りこぼさず提示・保存できること |
| TCC 権限フロー | 必要な OS 権限が無いと音声取得・文字化が成立しないため、取得を案内する | 権限が無い状態を黙って失敗させず、ユーザーに分かる形で促すこと |

---

## 振る舞い

システム全体の入力 → 処理 → 出力:

1. **起動 / 常駐**
   - アプリを起動するとメニューバーに常駐する（Dock には常駐させない設計を基本とする）。
   - メニューバーのアイコン／メニューから状態確認・操作を行う。

2. **対象アプリの選択**
   - 入力: 現在音声を出力し得るアプリ（または起動中アプリ）の一覧から、ユーザーが対象を 1 つ選ぶ。
   - 処理: 選択されたアプリの識別子（bundle identifier / process ID 等、取得方式により決定）を保持する。
   - 出力: 選択中アプリが UI 上で識別できる。

3. **権限の確認・要求**
   - 入力: 文字化開始操作。
   - 処理: 必要な TCC 権限（後述）の付与状態を確認する。未許可なら要求フローを起動する。
   - 出力: 未許可時はユーザーに分かる形で許可を促し、許可されるまで音声取得を開始しない。

4. **文字化の開始**
   - 入力: 対象アプリ選択済み・権限許可済みの状態での開始操作。
   - 処理: アプリ別オーディオ取得を開始 → PCM バッファを SpeechAnalyzer に供給 → 認識結果を受け取る。
   - 出力: 認識結果（途中経過および確定テキスト）がリアルタイムに UI に表示される。

5. **文字化中**
   - 入力: 対象アプリから出力される音声ストリーム。
   - 処理: PCM バッファを連続的に SpeechAnalyzer へ供給し、結果を逐次反映する。
   - 出力: テキストが追記・更新され、必要に応じて保存先へ書き出される。

6. **文字化の停止 / 終了**
   - 入力: 停止操作またはアプリ終了。
   - 処理: オーディオ取得と SpeechAnalyzer を停止し、リソースを解放する。確定テキストを保存する。
   - 出力: 文字化が停止し、結果が保存される。

---

## 受け入れ条件

### 機能要件
- [ ] アプリを起動すると、メニューバーに常駐アイコンが表示される。
- [ ] メニューバーから、文字化の対象アプリを一覧から選択できる。
- [ ] 対象アプリを選択し開始すると、そのアプリの音声がリアルタイムで文字として表示される
      （発話からテキスト更新までの遅延が実用的な範囲に収まる）。
- [ ] 対象アプリ以外（他アプリの音声・マイク入力・システム音）の音声が文字化結果に混入しない。
- [ ] 文字化を停止できる。停止後は新たなテキストが追記されない。
- [ ] 確定した文字起こし結果が、設定された出力先に保存される。

### 権限要件
- [ ] 必要な TCC 権限が未許可の場合、ユーザーに分かる形（ダイアログ・メニュー表示など）で許可を促す。
- [ ] 権限が未許可のまま音声取得を開始しない（黙って無音・空結果にならない）。

### 設定要件
- [ ] 対象アプリ識別子・認識言語・出力先などの設定が config ファイルに分離されており、
      コードに直書きされていない。

### 非機能・アーキテクチャ要件
- [ ] 文字化エンジンが Apple SpeechAnalyzer であり、音声がデバイス外へ送信されない（オンデバイス完結）。
- [ ] 3層アーキテクチャ（presentation → domain → infrastructure）の一方向依存が守られている。
      domain は presentation / infrastructure を import しない。

---

## スコープ（やらないこと）

- 自分のマイク入力（発話）の文字起こしは対象外（対象アプリの出力音声のみを扱う）。
- 複数アプリの同時文字化は初期スコープ外（対象アプリは同時に 1 つ）。
- 話者分離（誰が話したかの識別）は初期スコープ外。
- 翻訳・要約などの後処理は初期スコープ外（文字化結果の生成・表示・保存までを範囲とする）。
- クラウド音声認識・外部 API 連携は行わない（オンデバイスのみ）。
- macOS 26 未満のサポートは行わない。
- iOS / iPadOS など macOS 以外のプラットフォーム対応は行わない。

---

## 固定要件
<!-- 技術的判断で変更してはならない要件。後続エージェントはここを必ず読むこと -->
<!-- 逸脱する場合はユーザーに報告して承認を得ること -->

- **文字化エンジン**: Apple SpeechAnalyzer を使用する（macOS 26+ を前提とする）。他の音声認識エンジンに置き換えない。
- **言語**: Swift を使用する。
- **対応 OS**: macOS 26（Tahoe）以降。
- **3層アーキテクチャを厳守する**:
  - `presentation/`（または `ui/`）: メニューバー UI など、入出力・表示のみ。ロジックを持たない。
  - `domain/`（または `logic/` / `service/`）: 文字化サービス・状態管理。
    UI にも OS API にも依存しない純粋なビジネスロジック。
  - `infrastructure/`（または `data/`）: オーディオ取得 Tap・SpeechAnalyzer アクセスなど OS API への接触のみ。
  - **依存方向は presentation → domain → infrastructure の一方向のみ。逆依存を禁止する**。
  - domain 層は presentation / infrastructure を import してはならない。
    OS API・UI フレームワークへの依存は protocol / 抽象を介して infrastructure 側に閉じ込める。
- **設定の外部化**: 対象アプリ識別子・認識言語・出力先などの設定値は config ファイル（`.env` / `config.yaml` 等）に分離する。
  機密値やパスをコードに直書きしない。
- **TCC 権限の取り扱い**: 必要な権限と取得フローを明記し、未許可時はユーザーに促す（後述「TCC 権限」参照）。

### TCC 権限（取得が必要な権限と取得フロー）

> **確定（音声取得方式 = 候補A: Core Audio Process Tap を採用、ADR-1 参照）。**

- **必要な権限: 音声キャプチャ（Audio Capture）系の TCC 権限。画面収録（Screen Recording）権限は不要。**
  - Info.plist に **`NSAudioCaptureUsageDescription`** キーを追加し、権限ダイアログに表示する説明文を設定する。
  - Core Audio Process Tap は、対象プロセスの音声出力をタップするために音声キャプチャ権限を要求する。
    候補B（ScreenCaptureKit）で必要となる画面収録権限は本方式では**不要**であり、UX 上のメリットがある（ADR-1 参照）。
  - マイク権限（`NSMicrophoneUsageDescription`）は**不要**。本アプリはマイク入力を扱わない（スコープ外）。
- **権限状態の確認方法（実機検証で最終確定する事項）**:
  - 権限の付与状態を読み取る公開 API は限定的なため、実装では以下のいずれかを採用する（/tdd・実装フェーズで実機確定）:
    - (a) タップ生成 / Aggregate Device 起動を試み、`AudioHardwareCreateProcessTap` 等の戻り値・エラーで未許可を検出する。
    - (b) 初回キャプチャ開始時に OS が表示する権限ダイアログ結果を待ち、拒否時はエラーとして扱う。
  - **私的 TCC API には依存しない**（将来の OS 更新で破綻するため）。公開 API とエラーハンドリングで未許可を検出する方針とする。
- 取得フロー（`PermissionGate` 抽象に閉じる）:
  - 文字化開始前に `PermissionGate.ensureGranted()` を呼び、権限状態を確認する。
  - 未許可の場合、OS の権限要求ダイアログを提示するか、システム設定（プライバシーとセキュリティ）への導線を UI で案内する。
  - 許可されるまで音声取得を開始しない（黙って無音・空結果にしない）。
- **デプロイ前提（/deploy への引き継ぎ）**: Process Tap の利用には適切な署名と Info.plist の `NSAudioCaptureUsageDescription` が必須。
  TCC ダイアログを正しく出すため、Hardened Runtime / 署名構成を実機で検証すること。

---

## 未確定事項（設計フェーズで決定する）
<!-- /architect が「## アーキテクチャ設計」で比較・決定し、本セクションを更新すること -->

- **音声取得方式（アプリ別オーディオ取得の実現手段）** — **決定済み（→「## アーキテクチャ設計」ADR-1 参照）。**
  **採用: 候補A: Core Audio Process Tap**（`AudioHardwareCreateProcessTap` + `CATapDescription` + Aggregate Device, macOS 14.4+）。
  理由・代替案・トレードオフは ADR-1 を参照。これに伴い必要 TCC 権限を「### TCC 権限」で確定済み（音声キャプチャ権限 / `NSAudioCaptureUsageDescription`、画面収録権限は不要）。

---

## システム構成（コンポーネント依存関係）
<!-- /architect が精緻化する。本セクションが影響範囲分析・テスト計画・デプロイチェックの根拠になる。 -->

3層の責務とコンポーネント:

- **presentation 層**
  - `MenuBarUI`（メニューバー常駐・対象アプリ選択 UI・文字起こし表示・権限案内 UI）
- **domain 層**
  - `TranscriptionService`（文字化のユースケース調整: 開始・停止・状態管理）
  - `TranscriptStore`（文字起こし結果の集約・保持）
  - `AudioSource` / `SpeechRecognizer` / `AppEnumerator` / `PermissionGate`（**protocol = 抽象**。OS 依存を隠蔽する境界）
- **infrastructure 層**
  - `AudioTapAdapter`（音声取得方式の実装。Core Audio Process Tap または ScreenCaptureKit を採用方式に応じて実装）
  - `SpeechAnalyzerAdapter`（Apple SpeechAnalyzer への接触）
  - `RunningAppProvider`（起動中／音声出力アプリの列挙）
  - `TCCPermissionAdapter`（マイク／画面収録等の権限確認・要求）
  - `ConfigLoader`（config ファイルの読み込み）

依存関係（テキスト形式・依存方向は上→下の一方向）:

```
[presentation] MenuBarUI
      │ 依存している（使う）
      ▼
[domain] TranscriptionService ── TranscriptStore
      │  （AudioSource / SpeechRecognizer / AppEnumerator / PermissionGate という protocol に依存）
      ▼ （protocol を実装するのは infrastructure。domain は実装を知らない＝逆依存なし）
[infrastructure]
      AudioTapAdapter ─────────▶ Core Audio Process Tap / ScreenCaptureKit（OS フレームワーク）
      SpeechAnalyzerAdapter ───▶ Apple SpeechAnalyzer（OS フレームワーク, macOS 26+）
      RunningAppProvider ──────▶ NSWorkspace / Core Audio process list（OS）
      TCCPermissionAdapter ────▶ TCC（マイク / 画面収録 権限）
      ConfigLoader ────────────▶ config ファイル（.env / config.yaml）
```

依存関係の要点:
- presentation は domain にのみ依存する。
- domain は infrastructure の **protocol（抽象）** にのみ依存し、具体実装（OS API）を知らない。
  具体 Adapter は起動時（composition root / presentation 起動部）で domain に注入する。
- infrastructure のみが OS フレームワーク（Core Audio / ScreenCaptureKit / SpeechAnalyzer / TCC）に接触する。

影響範囲の観点（変更時に確認すべき対象）:
- **音声取得方式の決定（候補A/B）** は `AudioTapAdapter` と、それが要求する **TCC 権限**、
  および `PermissionGate` の実装に影響する。domain（`TranscriptionService`）の interface は方式に依存させない。
- **SpeechAnalyzer の API 変更** は `SpeechAnalyzerAdapter` に閉じる。

---
<!-- 以下は後続エージェントが追記するセクション -->

## アーキテクチャ設計

### 0. 設計サマリ（結論）

- **音声取得方式 = Core Audio Process Tap（候補A）を採用**（ADR-1）。最重要本質「対象アプリ音声の非混入」をプロセス単位タップで満たし、かつ画面収録権限が不要で常駐アプリの UX が良いため。
- **3層一方向依存（presentation → domain → infrastructure）を厳守**。domain は OS API / UI に一切依存せず、protocol（`AudioSource` / `SpeechRecognizer` / `AppEnumerator` / `PermissionGate`）にのみ依存する。
- **Composition Root はアプリ起動部（presentation 層の `AppDelegate` / `@main` 相当）に 1 箇所だけ置く**。ここで具体 Adapter を生成し domain に注入する。
- **音声→文字化はストリーミング**。Process Tap の PCM を `bestAvailableAudioFormat` へ変換し、`AsyncStream<AnalyzerInput>` で SpeechAnalyzer に供給。途中経過（volatile）と確定結果（finalized）を区別し、確定結果は取りこぼさず保存する。

---

### 1. コンポーネント構成（精緻化版）

ディレクトリ構成（Swift Package / Xcode target いずれでも層を物理分離する）:

```
Sources/
  presentation/      ← UI・入出力のみ。ロジックを持たない
    MenuBarApp           （@main / AppDelegate 相当。= Composition Root）
    MenuBarController     （メニューバー常駐・メニュー構築）
    AppPickerView         （対象アプリ選択 UI）
    TranscriptView        （文字起こし表示）
    PermissionPromptView  （権限案内 UI）
    ViewModel             （domain の状態を UI へ橋渡し。@Observable 等）
  domain/            ← 純粋ロジック。OS API / UI を import しない
    TranscriptionService  （ユースケース調整: 開始・停止・状態遷移）
    TranscriptStore        （文字起こし結果の集約・保持）
    SessionState           （状態: idle / awaitingPermission / running / stopped / error）
    model/                 （TargetApp, TranscriptSegment, RecognitionResult, AppId 等の値型）
    ports/                 ← protocol（抽象 = 境界）。実装は infra 側
      AudioSource
      SpeechRecognizer
      AppEnumerator
      PermissionGate
      TranscriptSink       （確定結果の出力先。保存の抽象）
      Clock / Config       （任意: 時刻・設定の抽象）
  infrastructure/    ← OS API への接触のみ。domain の port を実装
    ProcessTapAudioSource     （AudioSource 実装: Core Audio Process Tap）
    SpeechAnalyzerAdapter     （SpeechRecognizer 実装: Apple SpeechAnalyzer）
    RunningAppProvider        （AppEnumerator 実装: NSWorkspace / Core Audio process list）
    AudioCapturePermission    （PermissionGate 実装: NSAudioCaptureUsageDescription / TCC）
    FileTranscriptSink        （TranscriptSink 実装: ファイル保存）
    ConfigLoader              （Config 実装: config.yaml / .env 読み込み）
    AudioFormatConverter      （AVAudioConverter による PCM → analyzer format 変換）
```

> 旧「`AudioTapAdapter`」は採用方式確定により **`ProcessTapAudioSource`** に具体化した（ScreenCaptureKit 実装は作らない）。

---

### 2. レイヤーと依存関係（一方向）

```
[presentation]  MenuBarApp(=Composition Root) → MenuBarController / *View / ViewModel
       │ 依存（domain の型・protocol・Service を使う）
       ▼
[domain]        TranscriptionService ── TranscriptStore ── SessionState
       │  ports（抽象）にのみ依存:
       │    AudioSource / SpeechRecognizer / AppEnumerator / PermissionGate / TranscriptSink
       ▼  （port を実装するのは infrastructure。domain は具体実装を知らない＝逆依存なし）
[infrastructure]
       ProcessTapAudioSource ───▶ Core Audio Process Tap（AudioHardwareCreateProcessTap / CATapDescription / Aggregate Device）
       SpeechAnalyzerAdapter ───▶ Apple SpeechAnalyzer / SpeechTranscriber（macOS 26+）
       RunningAppProvider ──────▶ NSWorkspace / kAudioHardwarePropertyProcessObjectList
       AudioCapturePermission ──▶ TCC（音声キャプチャ / NSAudioCaptureUsageDescription）
       FileTranscriptSink ──────▶ ファイルシステム（出力先パスは Config 由来）
       ConfigLoader ────────────▶ config.yaml / .env
       AudioFormatConverter ────▶ AVFoundation（AVAudioConverter）
```

依存ルールの担保（固定要件「3層一方向依存」「domain は OS/UI 非依存」）:
- **domain は `import AppKit` / `import CoreAudio` / `import Speech` / `import ScreenCaptureKit` を一切しない。** Foundation の純粋型（および自前の値型）のみ使用。
- domain は `ports/` の protocol を型として参照するだけで、実装クラスを `import` / 直接生成しない。
- 具体 Adapter の生成・注入は **Composition Root（presentation の `MenuBarApp`）でのみ**行う。
- 物理分離（別ディレクトリ／別モジュール）にし、可能なら **domain を独立 Swift Package target** にして `presentation`/`infrastructure` を依存に持たせないことでコンパイル時に逆依存を不可能にする（推奨。/tdd・実装フェーズで構成確定）。

---

### 3. port（protocol 境界）の責務とインターフェース概要

domain 側に定義し、infrastructure が実装する。OS 由来の型（AVAudioPCMBuffer 等）は **port シグネチャに出さない**よう、domain 中立の値型に正規化する。

| port | 責務 | インターフェース概要（擬似シグネチャ） |
|---|---|---|
| `AppEnumerator` | 音声を出力し得る／起動中アプリの列挙 | `func listAudioCapableApps() async throws -> [TargetApp]`（`TargetApp { id: AppId, name, bundleId, pid }`） |
| `PermissionGate` | 音声キャプチャ権限の状態確認・要求 | `func currentStatus() -> PermissionStatus` / `func request() async -> PermissionStatus`（status: `granted/denied/undetermined`） |
| `AudioSource` | 対象アプリの音声を PCM フレームのストリームとして供給 | `func start(app: AppId) async throws -> AsyncStream<AudioFrame>` / `func stop() async`（`AudioFrame { samples, format: AudioStreamFormat, timestamp }`。format はサンプルレート・チャンネル・ビット深度を表す domain 値型） |
| `SpeechRecognizer` | PCM ストリームをオンデバイス文字化し結果を返す | `func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncStream<RecognitionResult>`（`RecognitionResult { text, isFinal, range }`） |
| `TranscriptSink` | 確定テキストの永続化（出力先抽象） | `func append(_ segment: TranscriptSegment) async throws` / `func flush() async throws` |
| `Config`（任意） | 設定値の供給 | `var targetAppId: AppId?` / `var locale: Locale` / `var outputPath: String` |

> `AudioFrame` / `AudioStreamFormat` は domain 中立の値型。infrastructure 側で AVAudioPCMBuffer ⇔ AudioFrame を相互変換し、OS 型を domain に漏らさない。

---

### 4. SpeechAnalyzer への音声供給フロー（PCM・バッファリング・ストリーミング）

検証済みの SpeechAnalyzer 前提（WWDC25 / Apple Docs）:
- `SpeechTranscriber` は `bestAvailableAudioFormat(compatibleWith:)` で要求フォーマットを提示する。入力バッファはこのフォーマットへ**変換してから**供給する必要がある。
- 入力は `AnalyzerInput`（変換済み `AVAudioPCMBuffer` を内包）を `AsyncStream` で逐次 yield する。
- 結果は途中経過（volatile / 暫定）と確定（finalized）の 2 種が流れる。

フロー（infrastructure 内に閉じる。domain は `AudioFrame` / `RecognitionResult` の抽象しか見ない）:

```
ProcessTap (kAudioTapPropertyFormat: ASBD → AVAudioFormat)
   │ I/O コールバックで PCM 取得（タップ元の native format。例: 48kHz float など。実機で確定）
   ▼
AudioFormatConverter (AVAudioConverter)
   │ bestAvailableAudioFormat へ変換（サンプルレート/チャンネル/フォーマット差を吸収）
   ▼
AnalyzerInput を AsyncStream に yield
   ▼
SpeechAnalyzer / SpeechTranscriber（オンデバイス）
   ▼
RecognitionResult を AsyncStream で受信（volatile / finalized）
```

方針:
- **フォーマット変換は必須前提**として `AudioFormatConverter` を独立コンポーネント化する。タップの native format と analyzer の要求 format が一致する保証はないため。
- **バッファリング**: Process Tap の I/O コールバック（リアルタイムスレッド、ブロッキング禁止）では PCM をロックフリーリングバッファに積むだけにし、変換・stream への yield は別の async タスクで行う。リアルタイムスレッドで重い処理・メモリ確保をしない。
- **オンデバイス完結**: SpeechAnalyzer はオンデバイス動作。音声を外部送信しない（固定要件・受け入れ条件を満たす）。ネットワーク送信コードを一切持たないことで担保。

---

### 5. リアルタイム性と確定テキスト取りこぼし防止

- **リアルタイム性（発話→更新の遅延）**: volatile（暫定）結果を受信次第 UI に即時反映し、体感遅延を抑える。タップ I/O は小バッファ・低レイテンシ設定。重い処理をリアルタイムスレッドから分離（上記）。
- **取りこぼし防止**:
  - `TranscriptStore` は volatile を「上書き表示用」、finalized を「確定保存用」として分離管理する。**保存対象は finalized のみ**とし、確定結果が来たら順序を保って `TranscriptSink.append` する。
  - 停止／アプリ終了時は `SpeechAnalyzer` を `finalize` してから停止し、最後の確定結果まで `flush` する（途中で切らない）。
  - `AsyncStream` のバックプレッシャ・バッファ方針を明示（finalized は欠落させない、volatile は最新優先で間引き可）。
- **停止後の不追記**: 停止後は `AudioSource.stop()` → ストリーム終端 → `SessionState = stopped`。停止後に到着した遅延バッファは破棄し、UI へ追記しない（受け入れ条件「停止後は追記されない」）。

---

### 6. 状態遷移（TranscriptionService が管理）

```
idle ──(対象アプリ選択)──▶ selected
selected ──(開始)──▶ checkingPermission
checkingPermission ──(granted)──▶ running
checkingPermission ──(denied)──▶ awaitingPermission（UI で案内、開始しない）
running ──(停止 / アプリ終了)──▶ stopping ──(finalize+flush)──▶ stopped
running ──(タップ/認識エラー)──▶ error（UI に提示、リソース解放）
```

---

### 7. 移行影響マップ（音声取得方式の確定に伴う影響）

新規開発のためコード移行は無いが、方式確定により「## システム構成」の暫定記述から具体化される影響を記録する（/tdd・/deploy の根拠）。

| コンポーネント | 確定前の想定 | 確定後 | 対応方針 | 担当フェーズ |
|---|---|---|---|---|
| `AudioTapAdapter`（暫定名） | Core Audio Tap または ScreenCaptureKit のいずれか | `ProcessTapAudioSource`（Core Audio Process Tap 実装に確定） | 変更必要（候補B は実装しない） | /tdd, 実装 |
| `PermissionGate` 実装 | マイク or 画面収録権限（方式依存） | `AudioCapturePermission`（音声キャプチャ権限 / `NSAudioCaptureUsageDescription`）。画面収録権限不要 | 変更必要（権限種別確定） | /tdd, /deploy |
| `AppEnumerator` 実装 | NSWorkspace or SCShareableContent | `RunningAppProvider`（PID → AudioObjectID 変換に必要なため Core Audio process list を併用） | 変更必要 | /tdd, 実装 |
| `AudioFormatConverter` | （暗黙） | 独立コンポーネントとして明示追加（タップ native format → bestAvailableAudioFormat 変換が必須のため） | 追加必要 | /tdd, 実装 |
| Info.plist / 署名 | 方式により権限キー未定 | `NSAudioCaptureUsageDescription` 追加。Hardened Runtime / 署名を実機検証 | 追加必要 | /deploy |
| domain（`TranscriptionService` / ports） | 方式非依存で設計 | 方式に依存させない（port シグネチャ不変） | 変更不要（方式差は infra に閉じる） | — |
| `SpeechAnalyzerAdapter` | SpeechAnalyzer 接触 | 不変（方式に非依存） | 変更不要 | — |

---

### ADR

#### ADR-1: アプリ別オーディオ取得方式に Core Audio Process Tap を採用する

**状況:**
仕様の最重要本質は「**対象アプリの音声のみを取得し、他アプリ・マイク・システム音を混入させない**」こと。実機は macOS 26.5 / Swift 6.3.2 / arm64、SpeechAnalyzer 利用可能。候補は (A) Core Audio Process Tap（`AudioHardwareCreateProcessTap` + `CATapDescription`、macOS 14.4+）と (B) ScreenCaptureKit（`SCStream` のアプリ別オーディオ、macOS 13+）。常駐メニューバーアプリであり、起動・操作の軽さ（UX）も重視する。

**判断:**
**候補A: Core Audio Process Tap を採用する。** 対象プロセスの PID を `kAudioHardwarePropertyTranslatePIDToProcessObject` で `AudioObjectID` に変換し、`CATapDescription`（対象プロセス限定）から Aggregate Device を構成して当該アプリの出力音声のみをタップする。infrastructure の `ProcessTapAudioSource` に実装を閉じ込める。

**理由:**
- **分離精度（最重要本質）**: プロセス（オーディオプロセスオブジェクト）単位で「このプロセスだけ」を対象にタップを構成でき、他アプリ・マイク・システム音を構造的に除外しやすい。マイクは扱わず、システム音やシステム全体ミックスではなく対象プロセス出力のみを取れる点が本質に直結する。
- **権限 UX**: 必要権限は**音声キャプチャ権限（`NSAudioCaptureUsageDescription`）のみ**で、画面収録権限を要求しない。候補B は音声のみのキャプチャでも**画面収録権限が必須**で、常駐アプリとしては要求が重く、ユーザーの不信感も招きやすい。本質的に画面は不要なので、過剰権限を避ける A が適切。
- **SpeechAnalyzer 適合性**: タップは `kAudioTapPropertyFormat`（ASBD→AVAudioFormat）で native format を提供。SpeechAnalyzer 側は `bestAvailableAudioFormat` への変換が前提のため、どちらの方式でも `AVAudioConverter` による変換は必要。変換が必須である点は A/B 同条件で、A の不利にはならない。
- **将来性**: macOS 14.4 以降の標準 Core Audio API で、システム音声キャプチャの「正式な道」として位置づけられている。

**理由（検証根拠 / 公式・準公式ソース）:**
- Apple「Capturing system audio with Core Audio taps」（macOS 14.4+、`CATapDescription`/`AudioHardwareCreateProcessTap`/Aggregate Device、権限は `NSAudioCaptureUsageDescription`）。
- insidegui/AudioCap（PID→AudioObjectID→CATapDescription→Aggregate Device の手順、`NSAudioCaptureUsageDescription`、`kAudioTapPropertyFormat` から AVAudioFormat 取得を確認）。
- Apple/WWDC25 SpeechAnalyzer（`bestAvailableAudioFormat` への変換と `AnalyzerInput`/`AsyncStream` 供給を確認）。

**検討した代替案（候補B: ScreenCaptureKit）と棄却理由:**
- アプリ単位のオーディオ取得自体は可能で API は高レベル・ドキュメントも充実しているが、**音声のみでも画面収録（Screen Recording）権限が必須**。常駐文字起こしアプリに「画面収録」を要求するのは目的（音声のみ）に対し過剰で、UX・信頼性の観点で不利。本質（非混入）を満たす点では A と同等だが、権限 UX の差で棄却。

**トレードオフ・残るリスク（実機検証で確定する事項）:**
- **API のドキュメントが薄く低レベル**で実装コストが高い（AudioCap も「poorly documented」と明記）。→ infrastructure の `ProcessTapAudioSource` に複雑性を完全に閉じ込め、domain・テストを汚さない設計で吸収する。
- **権限状態の読み取り公開 API が限定的**。私的 TCC API には依存せず、タップ生成の戻り値・初回ダイアログ結果で未許可を検出する方針（「### TCC 権限」参照）。実機で挙動確定。
- **タップ native format（サンプルレート/チャンネル/float 等）は環境・アプリ依存**。`AudioFormatConverter` で吸収するが、具体値は実機で確定。
- **音量減衰など既知の癖**が報告されている（フォーラム）。実機検証で確認し、必要なら補正方針を実装フェーズで決める。
- **対象アプリが複数プロセスに分かれる場合**（例: ブラウザのヘルパープロセスが音を出す）の取り扱いは実機で確認し、必要なら関連プロセス群をまとめてタップする方針を検討（初期スコープは単一アプリ）。

**影響:**
- infrastructure に `ProcessTapAudioSource`・`AudioFormatConverter` を実装、`AudioCapturePermission` を音声キャプチャ権限で実装。Info.plist に `NSAudioCaptureUsageDescription` を追加。
- domain（`TranscriptionService` / ports）は方式非依存のまま不変。将来 ScreenCaptureKit へ切替が必要になっても `AudioSource` 実装の差し替えで済む（port が防波堤）。

#### ADR-2: domain を OS / UI 非依存に保つため Composition Root を presentation 起動部に集約する

**状況:**
固定要件で「domain は presentation / infrastructure を import してはならない」「OS API・UI 依存は protocol を介して infrastructure に閉じる」と定められている。DI の注入点（具体実装を組み立てる場所）を決める必要がある。

**判断:**
**Composition Root はアプリ起動部（presentation 層の `MenuBarApp` / `@main`・`AppDelegate` 相当）に 1 箇所だけ置く。** ここで infrastructure の具体 Adapter（`ProcessTapAudioSource` / `SpeechAnalyzerAdapter` / `RunningAppProvider` / `AudioCapturePermission` / `FileTranscriptSink` / `ConfigLoader`）を生成し、`TranscriptionService` のコンストラクタに port として注入する。domain は具体型を一切知らない。

**理由:**
- 具体実装の生成・結線を 1 箇所に集約することで、domain を純粋に保ち（OS/UI 非 import）、テストでは fake/stub の port を注入できる（テスト容易性）。
- presentation はもともと OS（AppKit/SwiftUI）に依存してよい層なので、ここで OS 依存の生成を行っても依存方向は外→内のまま保たれる。

**影響:**
- domain を独立モジュール化すれば、コンパイル時に逆依存（domain→infra/presentation）を不可能にできる（推奨構成）。
- /tdd は port の fake を注入して `TranscriptionService` を OS なしでテストできる。

#### ADR-3: 音声→文字化はストリーミング処理とし、確定結果のみを保存する

**状況:**
リアルタイム性（発話→更新の低遅延）と、確定テキストの取りこぼし防止という 2 つの受け入れ条件を同時に満たす必要がある。SpeechAnalyzer は volatile（暫定）と finalized（確定）の結果を流す。

**判断:**
PCM は `AsyncStream` でストリーミング供給し、Process Tap の I/O コールバックは積むだけ・変換と認識は別 async タスクで行う。`TranscriptStore` は volatile を表示用の上書きバッファ、finalized を確定列として分離。**保存（`TranscriptSink`）対象は finalized のみ**。停止時は `finalize` → `flush` してから停止する。

**理由:**
- volatile を即時表示することで体感遅延を抑えつつ、finalized のみ保存することで確定結果の重複・取りこぼしを防ぐ。
- リアルタイムスレッドでブロッキング・確保をしないことでオーディオドロップアウトを回避。

**影響:**
- `SpeechRecognizer` port は `RecognitionResult { text, isFinal }` を流す設計とする。
- 停止フローで「最後の finalized まで flush」を保証する責務を `TranscriptionService` が持つ。

## テスト計画
<!-- /tdd が追記 -->

### 方針（ユーザー合意済み）

OS 依存のない **domain 層を fake/stub port で厚く TDD** し、infrastructure の OS Adapter は
**薄いアダプタ + 手動検証**で補う。タップ生成・SpeechAnalyzer 文字化・TCC 権限ダイアログは
実機・権限・実音声があって初めて検証でき、ユニットテストで担保できないため。

### プロジェクト構成（3層を物理モジュール分離）

Swift Package Manager 構成（`Package.swift`）。固定要件「3層一方向依存」「domain は OS/UI 非依存」を
**コンパイル時に構造的に担保**する。

```
Sources/
  SpeechTapDomain/          ターゲット依存なし（Foundation のみ）。model/ ports/ TranscriptStore TranscriptionService
  SpeechTapInfrastructure/  依存: SpeechTapDomain。OS Adapter 群（薄いスケルトン + ConfigLoader/FileTranscriptSink は実装）
  presentation/             CompositionRoot.swift.txt（DI 結線スケッチ。実 @main アプリは /deploy で Xcode app target 化）
Tests/
  SpeechTapDomainTests/         domain のユニットテスト + アーキテクチャガード
  SpeechTapInfrastructureTests/ ConfigLoader（OS 非依存部）のユニットテスト
```

- 依存方向: presentation → SpeechTapInfrastructure → SpeechTapDomain の一方向のみ。
- **domain ターゲットは他ターゲットを依存に持たないため、domain から infrastructure/presentation を
  import するとコンパイルエラー（循環依存）になる**ことを実際に確認済み（逆依存を構造的に不可能化、ADR-2）。
- CoreAudio 等のシステムフレームワークは SPM ターゲット境界では弾けないため、後述の
  **アーキテクチャガードテスト**で domain ソースの禁止 import を走査して担保する。

### fake port 戦略（実機・OS API なしで domain を検証）

| fake/stub | 対象 port | 役割 |
|---|---|---|
| `FakePermissionGate` | PermissionGate | granted/denied/undetermined と request 後状態を指定して権限分岐を検証 |
| `FakeAudioSource` | AudioSource | 任意の AudioFrame を流す / start 失敗を再現 / **start 呼び出し回数（`startCalled`）と stop 呼び出しを記録**（denied 時に「音声取得を開始していない」を直接検証） |
| `FakeSpeechRecognizer` | SpeechRecognizer | 指定した RecognitionResult 列（volatile/finalized 混在）を流す。`finalize()` は no-op |
| `DeferredFinalizeRecognizer` | SpeechRecognizer | `finalize()` 呼び出しで**初めて**最後の finalized を流す実機相当の遅延配信を模す（Must-1 検証用） |
| `FailingSpeechRecognizer` | SpeechRecognizer | `transcribe` ストリームを error 終端させ、認識/タップ異常終了からの error 状態遷移を検証（Should-3 用） |
| `ManualSpeechRecognizer` | SpeechRecognizer | 外部から手動で結果を emit（停止後到着シナリオ用） |
| `SpyTranscriptSink` | TranscriptSink | append/flush を記録し、保存内容と flush 回数を検証（actor） |

### テストケース（受け入れ条件 → テスト）

| 受け入れ条件 / 本質 | テストケース | 結果 |
|---|---|---|
| 未許可のまま音声取得を開始しない（権限要件・最重要） | `権限 denied のとき running に進まず awaitingPermission になる`（**start が一度も呼ばれないことを `startCalled == false` で直接検証**） | PASS |
| 同上（undetermined→request→denied 経路） | `undetermined → request しても denied なら開始しない`（**`startCalled == false` を直接検証**） | PASS |
| 権限 granted で開始できる（undetermined→request→granted） | `undetermined のとき request して granted なら running になる` | PASS |
| 対象選択（idle→selected 遷移） | `対象選択で idle → selected に遷移する` | PASS |
| 確定結果が保存される / 保存対象は finalized のみ（ADR-3） | `granted で開始すると finalized のみが sink に保存され volatile は保存されない` | PASS |
| 停止でき、停止時 finalize→flush で最後の確定まで保存（取りこぼし防止） | `停止すると stopping → stopped に遷移し flush が呼ばれる` | PASS |
| **停止時 finalize で遅れて届く最後の finalized を取りこぼさず保存（Must-1・ADR-3）** | `停止時に finalize で遅れて届く最後の finalized が保存される` | PASS |
| 停止後は追記されない（停止後不追記・最重要） | `停止後に到着した結果は保存・追記されない` | PASS |
| タップ/認識エラーで error 状態（リソース解放・提示） | `AudioSource の start が失敗すると error 状態になる` | PASS |
| **認識/タップのストリーム異常終了 → error 状態・リソース解放（Should-3）** | `認識ストリームが error 終端すると error 状態になりリソース解放される`（`audioSource.stop()` 呼び出しを検証） | PASS |
| volatile/finalized 分離保持（ADR-3） | `volatile 結果は上書き表示用で finalized 列には積まれない` | PASS |
| 同上 | `finalized 結果は確定列に追加され volatile はクリアされる` | PASS |
| 確定の順序保持（取りこぼし・順序崩れ防止） | `複数の finalized は順序を保って確定列に積まれる` | PASS |
| domain が OS/UI 非依存（固定要件・構造担保） | `domain ソースは OS API / UI フレームワークを import していない` | PASS |
| 設定の外部化（targetAppId/locale/outputPath を config から） | `.env 風ファイルから targetAppId / locale / outputPath を読み込む` | PASS |
| 同上（locale 既定） | `LOCALE 省略時は ja-JP を既定にする` | PASS |
| 出力先必須（保存先が無いと確定結果を保存できない） | `OUTPUT_PATH が無いとエラー` | PASS |
| config ファイル不存在の扱い | `存在しないファイルはエラー` | PASS |
| **保存先の親ディレクトリが無くても作成して保存（取りこぼし防止・Should）** | `親ディレクトリが存在しなくても作成してから保存する` | PASS |
| **複数回 flush で既存内容に追記（停止時 flush で取りこぼさない）** | `flush を 2 回行うと既存内容に追記される` | PASS |
| **保存失敗を黙殺せずエラーを伝播（Should）** | `保存できない場合はエラーを伝播し黙殺しない` | PASS |
| **出力先パスの `~` 展開（Want）** | `出力先パスの ~ を展開して保存する` | PASS |

### テスト環境

- フレームワーク: Swift Testing（`import Testing`）
- 環境: 実機・OS API・権限なしで完結（fake port 注入のみ）。ConfigLoader / FileTranscriptSink テストは一時ディレクトリ（一部はホーム配下のユニーク一時ディレクトリ）にファイル生成→破棄。
- 実行コマンド: `swift test` / 警告ゼロ確認: `swift build -Xswiftc -strict-concurrency=complete`
- 結果: **22 tests / 5 suites すべて PASS**（macOS 26.5 / Swift 6.3.2）。`swift build -Xswiftc -strict-concurrency=complete` 警告ゼロ。
  - レビュー差し戻し対応で **+6 tests / +1 suite**（FileTranscriptSinkTests）を追加。Must-1（finalize 取りこぼし防止）・Should-2（start 直接検証）・Should-3（error 経路）・FileTranscriptSink 群を Red→Green で実装。

### カバー範囲

- **domain（TDD で厚く）**: 値型、port protocol、`TranscriptStore`（volatile/finalized 分離）、
  `TranscriptionService`（全状態遷移・権限分岐・取りこぼし防止・**停止時 finalize→drain→flush**・停止後不追記・**認識ストリーム error 終端からの error 遷移**）。
- **infrastructure（OS 非依存部のみテスト）**: `ConfigLoader`（設定外部化）、`FileTranscriptSink`（親ディレクトリ作成・追記・保存失敗のエラー伝播・`~` 展開）。
- **アーキテクチャ**: domain の OS/UI 非 import をソース走査でガード。逆依存はコンパイル時に不可能化（確認済み）。

### infrastructure 手動検証項目（ユニットテストで担保できない＝実機検証が必要）

以下は実機・権限・実音声がないと検証できないため、スケルトン（TODO 明記）に留め、実機で確認する。

- [ ] 権限ダイアログが実機で出るか（`AudioCapturePermission` / `NSAudioCaptureUsageDescription`）。未許可検出が公開 API・エラーで成立するか。
- [ ] タップの native format の実値（サンプルレート/チャンネル/float 等）。`AudioFormatConverter` が `bestAvailableAudioFormat` へ正しく変換するか。
- [ ] **【最重要】対象アプリの音声のみが取れるか（非混入の実機確認）**。他アプリ・マイク・システム音が混入しないこと（`ProcessTapAudioSource`）。
- [ ] 対象アプリが複数プロセスに分かれる場合（例: ブラウザのヘルパープロセス）の挙動。
- [ ] SpeechAnalyzer がオンデバイスで実際に文字化するか（`SpeechAnalyzerAdapter`）。volatile/finalized が想定通り流れるか。
- [ ] `RunningAppProvider` が PID→AudioObjectID 変換に必要な情報を含めて TargetApp を列挙できるか。
- [ ] I/O コールバックがリアルタイムスレッドでブロッキング・メモリ確保しない実装になっているか（オーディオドロップアウト確認）。
- [ ] 署名・Hardened Runtime・Info.plist（`NSAudioCaptureUsageDescription`）で TCC ダイアログが正しく出るか（→ /deploy）。

### 未実装（スケルトンのみ・実機検証フェーズで結線）

`ProcessTapAudioSource` / `SpeechAnalyzerAdapter` / `AudioCapturePermission` / `RunningAppProvider`
/ `AudioFormatConverter` は OS API 接触の実装を TODO とし、ビルドが通る最小スケルトンに留める。
`SpeechAnalyzerAdapter` は `finalize()` の protocol 適合を追加済み（実体は `SpeechAnalyzer.finalizeAndFinish(through:)` 等での実機結線 TODO。`transcribe` は `AsyncThrowingStream` 化し、異常終了は `finish(throwing:)` で domain へ伝播する旨を TODO コメントに明記）。
`FileTranscriptSink` / `ConfigLoader` は OS 非依存に近く実装済み・テスト済み（FileTranscriptSink は親ディレクトリ作成・保存失敗のエラー伝播・`~` 展開を含む）。
presentation の実 @main アプリ・メニューバー UI は /deploy フェーズで Xcode app target として構築する。

## レビュー結果
<!-- /review が追記 -->

### 判定: 修正依頼（Must 1 件 / Should 4 件 / Want 3 件）

> **対応状況（/tdd 差し戻し対応, 2026-05-27）: Must-1 + Should 4 件すべて Resolved。Want は容易な 2 件（`~` 展開・`NotImplemented` 配置）を対応。**
> Red→Green→Refactor で各修正に先立ち失敗するテストを追加。`swift test` で **22 tests / 5 suites 全 PASS**、`swift build -Xswiftc -strict-concurrency=complete` 警告ゼロを確認済み。各指摘の対応概要は「### 指摘事項」表の「対応状況」列を参照。

domain 層中心 TDD の構造・品質は総じて高い。3層一方向依存・port 境界の OS 型非漏洩・設定外部化・
状態遷移の本質テストは適切に担保されている。`swift test` も報告どおり **16 tests / 4 suites 全 PASS**
（macOS 26.5）、`swift build -Xswiftc -strict-concurrency=complete` も警告ゼロでビルド成功を確認済み。
ただし「停止時 finalize→flush で最後の確定まで保存（取りこぼし防止）」の本質が、現状の port 設計では
domain 境界で構造的に担保できない点を Must とする。

### 整合性チェック（SPEC の目的・本質との照合）

- 最重要本質「対象アプリ音声の非混入」は infrastructure（`ProcessTapAudioSource`）の実機検証項目で、
  domain ではテスト不能。これは「## テスト計画 / infrastructure 手動検証項目」に正しく未検証として
  記録されており、テスト済みと誤魔化していない。レビュー観点と SPEC 本質に矛盾なし。

### 固定要件の遵守確認

- [x] 文字化エンジン = Apple SpeechAnalyzer 固定: `SpeechAnalyzerAdapter` が `SpeechRecognizer` を実装（スケルトン）。他エンジン混入なし。
- [x] 言語 = Swift / 対応 OS = macOS 26+: Swift 6.1 ツールチェイン。`Package.swift` は SPM 下限を v15 とし、実コードで availability ガードする方針をコメントで明記。
- [x] 3層一方向依存: SPM ターゲット分離（domain は依存ゼロ）で逆 import をコンパイル時に不可能化。`ArchitectureGuardTests` が OS/UI フレームワーク import をソース走査で禁止（PASS）。
- [x] domain は OS/UI 非依存: domain 全ファイルが Foundation のみ。port シグネチャに OS 型（AVAudioPCMBuffer/pid_t 等）が漏れていない（`AudioFrame`/`AudioStreamFormat`/`AppId(String)`/`TargetApp.pid: Int` で正規化）。
- [x] 設定の外部化: `ConfigLoader` が TARGET_APP_ID/LOCALE/OUTPUT_PATH を外部ファイルから供給。コードに機密値・パスの直書きなし。`.gitignore` が `config.conf`/`*.env` を除外し `*.example.conf` のみコミット対象。
- [x] TCC = 音声キャプチャ権限のみ: `AudioCapturePermission` のコメントに画面収録・マイク権限不要を明記。私的 TCC API 非依存方針も記載。

### 受け入れ条件との整合性

- [x] 未許可のまま開始しない（最重要・権限要件）: denied / undetermined→denied の両経路で `awaitingPermission` に留まり running に進まないテストが PASS。
- [x] 停止後は追記されない（最重要）: 世代（generation）ガードで停止後到着結果を破棄。`resultsAfterStopAreDiscarded` で検証 PASS。
- [x] 確定結果のみ保存（取りこぼし防止・ADR-3）: `onlyFinalizedIsSaved` で finalized のみ sink に積まれることを検証 PASS。
- [x] 停止時 finalize→flush で最後の確定まで保存: **Must-1 対応で Resolved**。`SpeechRecognizer.finalize()` を port に追加し、`stop()` は finalize→残り finalized 取り込み→flush の順に変更。`stopFinalizesAndSavesLastFinalized` で finalize 後に遅れて届く最後の finalized が保存されることを検証 PASS。
- [x] エラーで error 状態: `audioStartFailureGoesError` PASS に加え、**Should-3 対応で**認識ストリーム error 終端 → `failed()` → error 遷移・`audioSource.stop()` 解放を `recognitionStreamErrorGoesError` で検証 PASS（`failed()` が実経路で使用される形に）。
- [-] 非混入・リアルタイム遅延・実保存: infrastructure 実機検証項目として正しく未検証扱い（誤魔化しなし）。

### 指摘事項

| 重要度 | 場所 | 内容 | 改善案 | 対応状況 |
|---|---|---|---|---|
| **Must** | `TranscriptionService.stop()` / `SpeechRecognizer` port | SPEC・ADR-3 は「停止時に `finalize` してから flush し、最後の確定結果まで取りこぼさない」ことを要求しているが、`stop()` は `audioSource.stop()` → `recognitionTask.cancel()` → `sink.flush()` の順で、**認識器を finalize していない**。`recognitionTask?.cancel()` は `for await` を即時に打ち切るため、認識器側に残っている「volatile を最終確定に昇格した finalized」や未配信の finalized が **domain に届く前に破棄され得る**。`SpeechRecognizer` port に finalize 手段が無く、この取りこぼし防止本質を境界で構造的に担保できない。fake は即時に全結果を流すため現テストでは露見しないが、実際の SpeechAnalyzer はストリーミングで遅れて finalized を流すため取りこぼしが起きる。 | `SpeechRecognizer` に `func finalize() async`（または stream を「最後まで読み切る」契約）を追加し、`stop()` で `cancel()` する前に「入力ストリーム終端→finalize→残りの finalized を全て handle→flush」の順を保証する。テストは「stop 後も in-flight の finalized が flush 前に保存される」ケースを追加する。 | **Resolved**: `SpeechRecognizer` port に `func finalize() async` を追加（残り volatile を確定へ昇格し未配信 finalized を流し切ってストリーム終端する契約をコメント明記）。`stop()` を「finalize → 認識タスクを drain（finalize で遅れて届く finalized を `.stopping` 中・同一世代で handle/append）→ 世代更新 → audioSource.stop → flush」の順に変更し、即時 cancel を廃止。drain は契約違反でハングしないよう有界（100ms でキャンセル fallback）。`handle()` は `.running`/`.stopping` の同一世代のみ受理。`DeferredFinalizeRecognizer`（finalize 後に最後の finalized を遅延配信）で `stopFinalizesAndSavesLastFinalized` を追加し、Must-1 修正前は Red（旧 stop では取りこぼし）→ 修正後 Green を確認。既存の停止後不追記テストも引き続き PASS（finalize で正規に流すものと停止後の不正追記を区別）。 |
| Should | `Tests/.../Fakes.swift` `FakeAudioSource` | `start` の呼び出しを記録するフラグが無く、denied テストの「音声取得を開始していない」検証が `stopCalled == false` の弱い間接確認に留まる（開始したが stop 未呼でも false になり得る）。受け入れ条件「未許可のまま音声取得を開始しない」の本質を直接担保できていない。 | `FakeAudioSource` に `startCalled`（または開始回数）を持たせ、denied/undetermined→denied テストで `#expect(audio.startCalled == false)` を直接アサートする。 | **Resolved**: `FakeAudioSource` に `startCount`/`startCalled` を追加し、`deniedDoesNotStartAndGoesAwaitingPermission` と `undeterminedRequestDeniedDoesNotStart` の両権限拒否経路で `#expect(audio.startCalled == false)` を直接アサート。 |
| Should | `TranscriptionService.failed()` | `public` だが呼び出し元・テストともに存在しない。状態遷移図の `running → error`（タップ/認識エラー時のリソース解放）を担保するメソッドが未テストで、`audioSource.stop()` が呼ばれること・error 状態化が未検証。デッドコード化のリスクもある。 | `failed()` を呼ぶテストを追加（`audioSource.stop()` 呼び出しと `.error` 遷移を検証）。あるいは認識ストリームのエラー終端から自動で `failed()` に至る結線を実装し、その経路をテストする。 | **Resolved**: `transcribe` を `AsyncThrowingStream` 化し、認識/タップのストリーム異常終了（`finish(throwing:)`）を認識タスクが catch して `failed(_:generation:)` を呼ぶ結線を実装（`CancellationError` は error 扱いしない）。`failed()` が実経路で使われる形になった。`FailingSpeechRecognizer` で `recognitionStreamErrorGoesError` を追加し、error 遷移と `audioSource.stop()` 呼び出し（リソース解放）を検証 PASS。 |
| Should | `TranscriptionService.handle()` の `weak self` | `recognitionTask` 内で `[weak self]` を使い `guard let self else { return }` しているが、`TranscriptionService` は actor であり、認識タスクが回っている間 service が解放される状況は通常ない。`weak` にすると、何らかの理由で service 参照が切れた際に「ストリーム消費が静かに止まる」挙動になり、意図が不明瞭。 | actor のライフサイクルとタスク所有関係を整理し、`weak` の必要性を判断。不要なら強参照にして意図を明確化（または `weak` を残す根拠をコメント化）。 | **Resolved**: `recognitionTask` は `self` が所有し `stop()`/`failed()` で nil 化して破棄するため、`[weak self]` を廃止し強参照に変更。意図（タスク完了 or nil 化で循環解消、weak だとストリーム消費が静かに止まり挙動が不明瞭になる点）をコメントで明記。 |
| Should | `FileTranscriptSink.flush()` | 親ディレクトリが存在しない場合（例: `~/Documents/speech-tap/`）`data.write` / `FileHandle` が失敗する。確定結果保存の本質に関わるが、`append`/`flush` の戻りエラーは `TranscriptionService` で `try?` で握り潰されており、保存失敗がユーザーに伝わらない。 | flush 前に出力先ディレクトリを `createDirectory(withIntermediateDirectories:)` で用意する。併せて domain 側で保存失敗時のエラー提示（error 状態 or UI 通知）方針を検討（現状 `try?` で黙殺は受け入れ条件「確定結果が保存される」と緊張関係）。 | **Resolved**: `FileTranscriptSink.flush()` で書き込み前に `FileManager.createDirectory(withIntermediateDirectories: true)` で親ディレクトリを用意。`TranscriptionService` の `try?` 握り潰しを廃止し、`sink.append` 失敗→`failed()`、`sink.flush` 失敗→`error` 状態へ遷移（保存失敗を黙殺しない）。一時ディレクトリで `createsParentDirectoryAndWrites`/`appendsAcrossFlushes`/`propagatesWriteError` を追加し PASS。 |
| Want | `config.example.conf` の `OUTPUT_PATH` | `~/Documents/...` のチルダ展開を `ConfigLoader` が行わない（`URL(fileURLWithPath:)` はチルダを展開しない）。設定例のままだとカレント配下に `~` という名のディレクトリを作る恐れ。 | `ConfigLoader` または `FileTranscriptSink` で `NSString(string:).expandingTildeInPath` を適用する。 | **Resolved**: `FileTranscriptSink.init` で `(outputPath as NSString).expandingTildeInPath` を適用。`expandsTilde` テストでホーム配下に展開され、カレント配下に `~` を作らないことを検証 PASS。 |
| Want | `TranscriptStore.finalizedText` | セパレータを半角スペース固定で結合しているが、日本語（既定 ja-JP）では不自然。表示用途に限るがロケール非考慮。 | 連結ポリシーをロケール/用途に応じて見直す（保存は `TranscriptSink` 側で区切り済みのため影響軽微）。 | 未対応（表示用途限定・影響軽微のため今回スコープ外。保存は `TranscriptSink` 側で改行区切り済み）。 |
| Want | `NotImplemented` enum の配置 | `ProcessTapAudioSource.swift` のファイル末尾に infra 共通のエラー型が定義されており発見しづらい。 | 専用ファイル（例: `InfraErrors.swift`）に切り出すと一貫性が上がる。 | **Resolved**: `Sources/SpeechTapInfrastructure/InfraErrors.swift` に切り出し。 |

### 良い点

- port シグネチャから OS 型を完全に排除（`AudioFrame`/`AudioStreamFormat` への正規化、`TargetApp.pid: Int`）し、ADR-1/ADR-2 の「OS 型を domain に漏らさない」を実コードで体現できている。
- 停止後不追記を「世代（generation）」というシンプルな単調増加ガードで実装し、actor のシリアライズと組み合わせてデータ競合なく担保している点は堅実。
- `ArchitectureGuardTests` が SPM ターゲット分離で弾けない OS フレームワーク import をソース走査で補完しており、固定要件を二重に担保している。
- 実機検証が必要な項目を「テスト済み」と偽らず、手動検証項目として漏れなく明記している（誠実なテスト範囲申告）。


## 実装メモ（walking skeleton）
<!-- /tdd（walking skeleton フェーズ）が追記。2026-05-27 -->

### 目的と性質

「対象アプリの音声をタップ → SpeechAnalyzer で文字化 → 表示」という最大リスク経路を
実機で早期に貫通・検証可能にするための最小 end-to-end 骨組み。
**Core Audio Process Tap と SpeechAnalyzer の実装は実機・権限・実音声がないと検証できない**ため、
本フェーズは「コンパイル成功 + 実機起動可能 + 手動検証チェックリスト」で担保する。
OS 実装部分を「テスト済み」とは扱わない（誠実なテスト範囲申告）。domain の既存 22 テストは引き続き全 PASS。

### 実装したコンポーネント

**presentation + Composition Root（新規 executable target `SpeechTapApp`）**
- `Sources/SpeechTapApp/main.swift`: `NSApplication.accessory` でメニューバー常駐（Dock 非表示）。
- `Sources/SpeechTapApp/AppDelegate.swift`: **Composition Root（ADR-2）**。
  config を外部ファイルから読み（`~/.config/speech-tap/config.conf` → バンドル同梱 `config.default.conf` の順）、
  infrastructure の具体 Adapter（`ProcessTapAudioSource` / `SpeechAnalyzerAdapter` / `AudioCapturePermission`
  / `FileTranscriptSink` / `RunningAppProvider`）を生成して `TranscriptionService` に port 注入する。
  メニューバー UI: (a) 対象アプリ選択（一覧）, (b) 開始/停止, (c) 文字起こし表示, (d) 権限未許可案内ダイアログ
  （`awaitingPermission` でシステム設定への導線を提示）。`@MainActor` 注釈で UI スレッド安全。
- `Sources/SpeechTapApp/TranscriptWindowController.swift`: 文字起こし表示ウィンドウ（finalized + volatile をグレー表示）。
- `Sources/SpeechTapApp/Resources/Info.plist`: `NSAudioCaptureUsageDescription` / `LSUIElement=true` を設定。
  `-sectcreate __TEXT __info_plist` リンカフラグでバイナリに埋め込み（`otool -P` で埋め込み確認済み）。

**infrastructure（実 OS 実装。最小だが実際に OS API を叩く）**
- `RunningAppProvider`(AppEnumerator): `NSWorkspace.runningApplications` で `.regular` アプリを列挙し、
  PID を持つ `TargetApp` に変換。`AppId.rawValue = bundleId`（config の TARGET_APP_ID と突き合わせ可能）。
- `AudioCapturePermission`(PermissionGate): **私的 TCC API 非依存**。グローバルタップ（mute・private）の
  `AudioHardwareCreateProcessTap` 試行の戻り値で granted/denied を判定（SPEC「### TCC 権限」(a)(b) 方針）。
  初回試行で OS が音声キャプチャ権限ダイアログを表示する想定。画面収録・マイク権限は要求しない。
- `ProcessTapAudioSource`(AudioSource): PID → `kAudioHardwarePropertyTranslatePIDToProcessObject` で AudioObjectID →
  **`CATapDescription(stereoMixdownOfProcesses: [対象のみ])`（= 非混入を構造的に担保）** → `AudioHardwareCreateProcessTap`
  → private Aggregate Device（対象タップのみを sub-tap に持つ）→ `AudioDeviceCreateIOProcIDWithBlock` で IOProc 登録。
  **I/O コールバック（リアルタイムスレッド）はサンプルをコピーして `AsyncStream` に yield するだけ**（確保・ロック・ブロッキングをしない）。
  native format は `kAudioTapPropertyFormat`（ASBD）→ `AudioStreamFormat` に正規化。stop でタップ/集約デバイス/IOProc を解放。
- `AudioFormatConverter`: `AVAudioConverter` で native format → analyzer の `bestAvailableAudioFormat` へ実変換。
  `AudioFrame ⇔ AVAudioPCMBuffer` の相互変換（OS 型を domain に漏らさない境界）。
- `SpeechAnalyzerAdapter`(SpeechRecognizer): macOS 26 の `SpeechTranscriber`（`reportingOptions: [.volatileResults]`）+
  `SpeechAnalyzer` を使用。`AssetInventory.assetInstallationRequest` で言語モデルを必要に応じ導入（オンデバイス）。
  `AudioFrame → AnalyzerInput` を `AsyncStream` で供給、`transcriber.results` の `isFinal` で volatile/finalized を区別し
  `RecognitionResult` に正規化して `AsyncThrowingStream` で流す。`finalize()` は入力終端 +
  `analyzer.finalizeAndFinishThroughEndOfInput()` で最後の確定まで流し切る（ADR-3）。
  異常終了は `continuation.finish(throwing:)` で domain に伝播（error 状態遷移を駆動）。**ネットワーク送信コードを持たない**。
- `InfraErrors.swift`: `NotImplemented` に加え、Process Tap 構成失敗を表す `AudioTapError`（OSStatus 保持）。

### ビルド / 起動手順

```sh
# domain ユニットテスト（22 tests / 5 suites 全 PASS を維持）
swift test

# 警告ゼロ確認（クリーンビルド）
swift build -Xswiftc -strict-concurrency=complete   # → Build complete!（警告ゼロ）

# walking skeleton 起動（メニューバー常駐。Dock には出ない）
swift build
.build/debug/SpeechTapApp
# メニューバーの 🎙 アイコンから: アプリ一覧更新 → 対象選択 → 「文字化を開始」。
# 設定は ~/.config/speech-tap/config.conf を作れば優先（無ければ同梱 config.default.conf を使用）。
```

> 注: SPM の bare executable では TCC ダイアログ・署名が不安定な場合がある。
> Hardened Runtime / 署名 / .app バンドル化は /deploy で詰める（Info.plist の `NSAudioCaptureUsageDescription` は埋め込み済み）。

### 実施した検証（このフェーズで確認できた範囲）

- `swift build` 成功 / `swift build -Xswiftc -strict-concurrency=complete` クリーンビルドで**警告ゼロ**。
- `swift test`: domain 既存 **22 tests / 5 suites 全 PASS**（macOS 26.5 / Swift 6.3.2）。`ArchitectureGuardTests` も PASS（domain は OS/UI 非 import を維持）。
- 実行ファイルに Info.plist（`NSAudioCaptureUsageDescription`）が埋め込まれていることを `otool -P` で確認。
- アプリを起動し、**メニューバー常駐プロセスとして起動・常駐し続ける**ことを確認（早期 exit / クラッシュ無し）。

### 手動検証チェックリスト（実機で人間が確認する。ユニットテスト不能）

実際に音声を出すアプリ（例: ブラウザで動画再生）を用意し、以下を順に確認する:

1. [ ] **メニューバー常駐**: 起動すると🎙アイコンがメニューバーに出る。Dock には出ない（`LSUIElement`/accessory）。
2. [ ] **アプリ一覧**: メニューの「アプリ一覧を更新」で起動中アプリが一覧表示され、選択でチェックが付く。
3. [ ] **権限ダイアログ**: 「文字化を開始」で音声キャプチャ権限ダイアログが出る（画面収録/マイクは要求されない）。
       拒否すると「権限未許可」案内ダイアログ + システム設定への導線が出て、**音声取得を開始しない**。
4. [ ] **文字化**: 対象アプリ（動画再生中のブラウザ等）を選び開始すると、「文字起こしを表示」ウィンドウに
       テキストがリアルタイム更新される（volatile はグレー、finalized は通常色）。
5. [ ] **【最重要】非混入**: 対象アプリ以外（別アプリの音声・マイク・システム音）が**文字化結果に混入しない**こと。
       例: 対象をブラウザにし、別アプリで音楽を鳴らしても、その音楽の内容は文字化されない。
6. [ ] **停止後不追記**: 「文字化を停止」後、対象アプリが音を出し続けても新たなテキストが追記されない。
7. [ ] **保存**: 停止後、`OUTPUT_PATH`（既定 `~/Documents/speech-tap/transcript.txt`）に確定テキストが保存される。

### 実機検証で未解決の事項（決め打ちせず実機で確定する）

- **権限ダイアログが SPM bare executable で正しく出るか**。`AudioCapturePermission` の granted/denied 判定が
  公開 API の戻り値だけで実用的に成立するか（undetermined と denied の厳密な区別は公開 API では困難。実機で挙動確定）。
  → 署名・Hardened Runtime・.app バンドル化が必要なら /deploy で対応。
- **タップ native format の実値**（サンプルレート/チャンネル/float/interleaved）。`AudioFormatConverter` の
  `bestAvailableAudioFormat` への変換が正しいか。フォーマット差で無音・歪みが出ないか。
- **【最重要】非混入の実機確認**（上記チェックリスト 5）。`CATapDescription(stereoMixdownOfProcesses:)` で
  対象プロセスのみがタップされ、他アプリ・マイク・システム音が混入しないこと。
- **対象アプリが複数プロセスに分かれる場合**（例: ブラウザのヘルパープロセスが音を出す）の挙動。
- **SpeechAnalyzer がオンデバイスで実際に文字化するか**。言語モデル導入フロー（`assetInstallationRequest`）の成否。
  volatile/finalized が想定通り流れるか。
- **I/O コールバックでのドロップアウト**（リアルタイムスレッドでの `Array` コピー・`continuation.yield` の負荷）。
  実機で長時間・高負荷時にオーディオドロップアウトが出ないか。出る場合はロックフリーリングバッファ化を検討。
- **音量減衰など Process Tap 既知の癖**（フォーラム報告）の有無。

## デプロイ計画
<!-- /deploy が追記。2026-05-28 -->

### 性質（このフェーズは何か）

外部サーバへの本番デプロイではなく、**ローカル macOS アプリのビルド・.app バンドル化・ad-hoc 署名・起動可能化**である。
目的は、ユーザーが実機で起動して TCC（音声キャプチャ）権限を付与し、手動検証（特に**最重要 = 非混入**）を実行できる状態にすること。
不可逆操作（`rm -rf` 等）はスクリプトの生成物 `build/SpeechTap.app` に限定し、ソース・ユーザーデータには触れない。

### ビルド / .app バンドル化 / 署名手順

成果物スクリプト: **`scripts/make_app.sh`**（リポジトリルートで実行）。

```sh
# domain ユニットテスト（22 tests / 5 suites 全 PASS を維持）
swift test

# release ビルド → build/SpeechTap.app 生成 → ad-hoc 署名 → 検証
scripts/make_app.sh
# 生成して即起動する場合:
OPEN=1 scripts/make_app.sh
```

`make_app.sh` の処理（5 ステップ）:
1. `swift build -c release`。`--show-bin-path` で実行ファイル `SpeechTapApp` を解決。
2. `.app` バンドル構造を構築:
   - `Contents/MacOS/SpeechTapApp`（実行ファイル）
   - `Contents/Info.plist`（`Sources/SpeechTapApp/Resources/Info.plist` を配置。**.app では Contents/Info.plist が正本**。
     バイナリの `-sectcreate __TEXT __info_plist` 埋め込みは bare executable 用の保険として併存）
   - `Contents/Resources/config.default.conf`（既定設定フォールバック。`Bundle.main.path(forResource:)` が
     .app では `Contents/Resources/` を探索するためここに配置。これにより config 解決が .app でも成立）
   - `Contents/PkgInfo`（`APPL????`）
3. entitlements 生成（`build/SpeechTap.entitlements`）: `com.apple.security.device.audio-input` のみ（音声キャプチャ最小）。
4. **ad-hoc 署名**: `codesign --force --sign - --entitlements ... --identifier com.example.speech-tap`。
   **Hardened Runtime は付けない**（`--options runtime` 不使用）。ローカル実機検証用には ad-hoc + バンドル識別で
   TCC の関連付けは成立する。Developer ID 配布する場合のみ runtime + notarization を将来検討。
5. 検証: `codesign --verify`、entitlements ダンプ、Info.plist 主要キー表示、
   **画面収録/マイク権限キーが Info.plist に無いことを明示チェック（固定要件・あれば exit 1）**。

#### Info.plist の主要キー（確認済み）

| キー | 値 | 目的 |
|---|---|---|
| `CFBundleIdentifier` | `com.example.speech-tap` | バンドル識別（TCC/LaunchServices の同一性） |
| `CFBundleExecutable` | `SpeechTapApp` | MacOS/ 配下の実行ファイル名と一致 |
| `LSUIElement` | `true` | メニューバー常駐・Dock 非表示 |
| `LSMinimumSystemVersion` | `26.0` | macOS 26+ 前提（固定要件） |
| `NSAudioCaptureUsageDescription` | （説明文あり） | 音声キャプチャ権限ダイアログの説明 |
| `NSScreenCaptureUsageDescription` | **未設定** | 画面収録権限を要求しない（固定要件） |
| `NSMicrophoneUsageDescription` | **未設定** | マイク権限を要求しない（固定要件・スコープ外） |

#### 機密情報の扱い

ad-hoc 署名は証明書・秘密鍵を一切使わない。`.gitignore` で `build/`・`*.app`・`*.entitlements` を除外し、
署名成果物・生成 entitlements をコミットしない。`config.conf`/`*.env`（実設定）も既存 `.gitignore` で除外済み。

### ロールバック / クリーンアップ手順

本フェーズはローカルビルドのため「ロールバック」は成果物の削除と権限リセットで原状復帰できる。

| 操作 | コマンド | 備考 |
|---|---|---|
| .app 成果物の削除 | `rm -rf build/SpeechTap.app build/SpeechTap.entitlements` | 生成物のみ。ソースに影響なし |
| ビルドディレクトリ削除 | `rm -rf .build build` | クリーンビルドへ戻す |
| TCC 権限のリセット（音声キャプチャ） | `tccutil reset AudioCapture com.example.speech-tap` | 次回起動時に再度ダイアログが出る状態へ |
| TCC 権限の全リセット（最終手段） | `tccutil reset AudioCapture` | 全アプリの音声キャプチャ許可をリセット（影響範囲大・要注意） |
| アプリ削除での原状復帰 | `build/SpeechTap.app` を削除 | 常駐プロセス・設定（`~/.config/speech-tap/`）・出力（`OUTPUT_PATH`）以外に OS 改変は無い |

> 不可逆操作（`rm -rf` / `tccutil reset`）はユーザーの明示同意のもとで実行する（自己判断で実行しない）。

### 実機検証 runbook（最重要の成果物・ユーザーが実機で実行）

事前準備: 音声を出すアプリ（例: ブラウザで動画再生）を 1 つ用意。別途「混入確認用」に音楽再生アプリ等をもう 1 つ用意。

| # | 手順 | 期待結果 | 失敗時の切り分け |
|---|---|---|---|
| 1 | `swift test` | 22 tests / 5 suites 全 PASS | 失敗時は domain 回帰。実装フェーズへ差し戻し |
| 2 | `scripts/make_app.sh` | `build/SpeechTap.app` 生成、`codesign --verify` valid、画面収録/マイクキー無し確認 | 署名失敗→codesign エラー文確認。Info.plist キー欠落→`Sources/.../Info.plist` 修正 |
| 3 | `open build/SpeechTap.app` | メニューバーに 🎙 アイコンが出る。**Dock には出ない**（`LSUIElement`/accessory） | アイコンが出ない→`Console.app` でクラッシュ/early exit 確認。config error ダイアログが出たら設定解決失敗 |
| 4 | メニュー →「アプリ一覧を更新」 | 起動中アプリが一覧表示される | 空のまま→`RunningAppProvider`（`NSWorkspace.runningApplications`）の挙動確認 |
| 5 | 一覧から対象アプリ（動画再生中のブラウザ等）を選択 | 選択にチェックが付く | — |
| 6 | 「文字化を開始」 | **音声キャプチャ権限ダイアログが出る**（画面収録/マイクは出ない）。許可で文字化開始 | **ダイアログが出ない**→未解決事項参照（.app+署名でも出ない場合は Hardened Runtime 付与や Developer ID 署名を検討）。`tccutil reset AudioCapture com.example.speech-tap` で再試行 |
| 7 | 権限を**拒否**して再度「文字化を開始」 | 「権限未許可」案内ダイアログ + システム設定への導線。**音声取得を開始しない**（黙って無音にならない） | 無音で進む→`AudioCapturePermission` の granted/denied 判定が公開 API で成立していない（未解決事項） |
| 8 | 権限許可後、対象アプリで動画を再生し「文字起こしを表示」 | テキストがリアルタイム更新（volatile=グレー、finalized=通常色） | 無音/文字化されない→native format 不一致（`AudioFormatConverter`）/ SpeechAnalyzer 言語モデル未導入（`assetInstallationRequest`） |
| 9 | **【最重要】非混入**: 対象=ブラウザのまま、別アプリで音楽を鳴らす | 別アプリ（音楽）の内容は**文字化結果に混入しない**。対象アプリの音声のみが文字化される | 混入する→`CATapDescription(stereoMixdownOfProcesses:)` が対象プロセスのみに限定できていない。ブラウザのヘルパープロセス分離も確認 |
| 10 | 「文字化を停止」後、対象アプリが音を出し続ける | **新たなテキストが追記されない**（停止後不追記） | 追記される→domain の世代ガード/stop フロー回帰（実装フェーズ差し戻し） |
| 11 | 停止後、`OUTPUT_PATH`（既定 `~/Documents/speech-tap/transcript.txt`）を確認 | 確定（finalized）テキストが保存されている | 保存されない→`FileTranscriptSink` の出力先・権限。親ディレクトリは自動作成される設計 |

### 受け入れ条件の照合結果

ビルド・バンドル・起動可能化フェーズで**自動/起動レベルで確認できたもの**と、**実機・人間の操作・実音声が必要で未確認のもの**を正直に分離する。

#### 自動/起動レベルで確認済み

- [x] **`swift test` 22 tests / 5 suites 全 PASS**（macOS 26.5 / Swift 6.3.2）— 確認済み（domain 回帰なし）。
- [x] **`swift build -c release` 成功** — `Build complete!` 確認済み。
- [x] **`scripts/make_app.sh` で `build/SpeechTap.app` 生成** — 確認済み。
- [x] **`codesign --verify` valid / Designated Requirement 充足** — 確認済み（ad-hoc 署名）。
- [x] **entitlements = `com.apple.security.device.audio-input` のみ** — `codesign -d --entitlements` で確認済み。
- [x] **Info.plist 主要キー**（`CFBundleIdentifier`/`CFBundleExecutable`/`LSUIElement=true`/`LSMinimumSystemVersion=26.0`/`NSAudioCaptureUsageDescription`）— 確認済み。
- [x] **画面収録/マイク権限キーが Info.plist に無い（固定要件）** — `NSScreenCaptureUsageDescription`・`NSMicrophoneUsageDescription` 未設定を明示チェック（make_app.sh が検証、あれば exit 1）。確認済み。
- [x] **メニューバー常駐プロセスとして起動・常駐（早期 exit/クラッシュ無し）** — 実行ファイルを起動し 5 秒間 resident を確認、エラー出力なし。
- [x] **設定の外部化（config 解決が .app で成立）** — `Contents/Resources/config.default.conf` を配置し `Bundle.main.path` で解決可能。起動時に config error ダイアログが出ないことを確認。
- [x] **オンデバイス完結（ネットワーク送信コードを持たない）** — 設計・実装方針で担保（infrastructure に送信コード無し）。実音声での最終確認は実機項目。

#### 実機・人間の操作が必要で未確認（runbook の手動検証で確定する）

- [ ] **メニューバーに 🎙 アイコンが表示され Dock に出ない**（GUI 目視。プロセス常駐は確認済みだがアイコン表示は実機目視が必要）— runbook #3。
- [ ] **対象アプリを一覧から選択できる** — runbook #4-5。
- [ ] **対象アプリの音声がリアルタイムで文字表示される（実用的遅延）** — runbook #8。実音声・SpeechAnalyzer 動作が必要。
- [ ] **【最重要】対象アプリ以外の音声が文字化結果に混入しない** — runbook #9。実音声・複数アプリが必要。**本仕様の最重要本質**。
- [ ] **停止でき、停止後は追記されない** — runbook #10（domain ロジックはテスト済みだが実音声経路での最終確認は実機）。
- [ ] **確定結果が `OUTPUT_PATH` に保存される** — runbook #11（`FileTranscriptSink` はテスト済みだが実経路での最終確認は実機）。
- [ ] **権限ダイアログが実機で出る/未許可時に開始しない** — runbook #6-7。**.app バンドル + ad-hoc 署名でダイアログが出るかは未解決事項（下記）**。

### 未解決の実機検証項目（決め打ちせず実機で確定する）

- **権限ダイアログが .app バンドル + ad-hoc 署名で正しく出るか**: skeleton では「SPM bare executable では TCC ダイアログが不安定」と未解決だった。
  本フェーズで .app バンドル化 + バンドル識別 + ad-hoc 署名（audio-input entitlement）まで整えたが、
  **実際にダイアログが表示されるかは実機・実権限フローでのみ確定できる**。出ない場合の対応候補:
  (a) Hardened Runtime を付けて再署名（`codesign --options runtime`）、(b) Developer ID 署名、
  (c) `tccutil reset AudioCapture com.example.speech-tap` 後に再試行。実機結果で確定する。
- **`AudioCapturePermission` の granted/denied 判定が公開 API の戻り値だけで実用的に成立するか**（undetermined と denied の厳密な区別は公開 API では困難。私的 TCC API 非依存方針を維持）。
- **タップ native format の実値**（サンプルレート/チャンネル/float/interleaved）と `AudioFormatConverter` の `bestAvailableAudioFormat` 変換の正しさ（無音・歪み・音量減衰）。
- **【最重要】非混入の実機確認**（runbook #9）。`CATapDescription(stereoMixdownOfProcesses:)` で対象プロセスのみがタップされること。
- **対象アプリが複数プロセスに分かれる場合**（ブラウザのヘルパープロセス）の挙動。
- **SpeechAnalyzer のオンデバイス文字化**（言語モデル導入 `assetInstallationRequest` の成否、volatile/finalized の流れ）。
- **I/O コールバックでのオーディオドロップアウト**（長時間・高負荷時）。

> 結論: ビルド・バンドル化・署名・起動可能化までは完了し、**ユーザーが実機で TCC 権限を付与して手動検証（特に最重要 = 非混入）を実行できる状態**になった。
> 実音声・実権限・GUI 目視が必要な受け入れ条件は runbook に沿って人間が確定する。目的・最重要本質「非混入」とのズレは無い（バンドル化は非混入の構造的担保 `stereoMixdownOfProcesses` をそのまま実機で検証可能にするもの）。
