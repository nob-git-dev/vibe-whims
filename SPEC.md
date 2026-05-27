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

## レビュー結果
<!-- /review が追記 -->

## デプロイ計画
<!-- /deploy が追記 -->
