# speech-tap

🌐 **English** | [日本語](#日本語)

> A macOS menu-bar app that transcribes the audio of a **single chosen app** in real time, fully **on-device**, using Apple's new **SpeechAnalyzer** (macOS 26).

It captures only the audio **a specific macOS app outputs** (a meeting app, a video in a browser, a podcast, …) and transcribes it live. Neither audio nor text ever leaves the device.

> Part of the [`vibe-whims`](https://github.com/nob-git-dev/vibe-whims) experiment repository. A Swift macOS menu-bar app.

---

## Features

- 🎯 **Per-app audio selection** — transcribe "only this app's audio." Other apps, the microphone, and system sounds never leak in.
- 🧠 **Fully on-device** — speech recognition via Apple SpeechAnalyzer. No network transmission.
- ⏱ **Real-time display** — volatile (tentative) results shown immediately; finalized results are persisted.
- 💾 **Crash-resilient saving** — finalized text is appended to a file immediately, so even if the app crashes, what was confirmed survives.
- 🌐 **On-device translation** — non-Japanese audio is shown in Japanese via the Apple Translation framework (the **original text** is what gets saved).
- 🌍 **Multilingual recognition** — pick the recognition language from the menu; SpeechTranscriber follows mid-conversation language switches automatically.
- 🪟 **Pin** — keep the transcript window always on top.
- 📤 **Session export** — on stop, the session's text is written to Downloads as an independent file.
- 🧹 **Optional LLM cleanup** — send the stopped session transcript to a configured OpenAI-compatible API and save a separate `*-corrected.txt` copy. Original transcript files remain unchanged.

---

## Apple APIs used

This project combines Apple on-device APIs with different availability floors. The effective runtime requirement is **macOS 26.0+** because `SpeechAnalyzer` / `SpeechTranscriber` are required for transcription.

### 1. SpeechAnalyzer / SpeechTranscriber (speech recognition · **macOS 26+**)

Apple's new on-device speech recognition framework announced at WWDC25 — a modular, concurrency-friendly, fully offline API that replaces `SFSpeechRecognizer`.

- Add a `SpeechTranscriber` module to a `SpeechAnalyzer` session to manage analysis.
- Input audio is converted to the format reported by `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` and fed as `AnalyzerInput`.
- Results flow over an `AsyncStream` in two kinds: **volatile** (tentative) and **finalized**.
- `AssetInventory.assetInstallationRequest(supporting:)` installs the language model (language pack) on-device automatically.
- Given an initial locale, the model **follows mid-conversation language switches** automatically.
- On stop, `finalizeAndFinishThroughEndOfInput()` flushes through the last finalized result.

→ Implementation: [`SpeechAnalyzerAdapter.swift`](Sources/SpeechTapInfrastructure/SpeechAnalyzerAdapter.swift)

### 2. Core Audio Process Tap (per-app audio capture · **macOS 14.2+**)

The Core Audio API that taps "only a specific process's audio output." It underpins this app's **most important property — non-mixing**.

- `kAudioHardwarePropertyTranslatePIDToProcessObject` converts a PID → `AudioObjectID` (audio process object).
- `CATapDescription(stereoMixdownOfProcesses:)` builds a tap containing **only the target processes** (no global/exclusion taps — non-mixing by construction).
- `AudioHardwareCreateProcessTap` creates the tap; `kAudioTapPropertyFormat` returns the native format.
- An Aggregate Device wrapping the tap (`AudioHardwareCreateAggregateDevice`, `kAudioAggregateDeviceIsPrivateKey`) receives PCM via an IOProc.
- The I/O callback (real-time thread) only copies samples and forwards them; format conversion happens downstream.

→ Implementation: [`ProcessTapAudioSource.swift`](Sources/SpeechTapInfrastructure/ProcessTapAudioSource.swift)

### 3. Multi-process capture (browsers) — `responsibility_get_pid_responsible_for_pid`

Browsers like Chrome emit audio from a **renderer/helper process, not the main process**. Those processes are not registered in `NSRunningApplication` and have no bundle id, so tapping the main PID yields silence.

- libproc's `responsibility_get_pid_responsible_for_pid(pid)` retrieves each process's "responsible PID."
- Only processes **whose responsible PID equals the target app's main PID** are added to the tap (i.e., the renderer is captured).
- Processes responsible to another app, lookups that fail, and ambiguous ones are **excluded** (non-mixing strictly preserved).
- The collected process group is passed together to `CATapDescription(stereoMixdownOfProcesses: [...])`.

> ⚠️ `responsibility_get_pid_responsible_for_pid` is an undocumented libproc symbol. Use with care in App Store apps (this app is intended for local use).

→ Implementation: [`ProcessMatcher.swift`](Sources/SpeechTapInfrastructure/ProcessMatcher.swift) / [`CProcResponsibility`](Sources/CProcResponsibility/)

### 4. Apple Translation framework (on-device translation)

Translates non-Japanese recognition results into Japanese on-device, without sending anything to the cloud.

- A translation session is built with the `Translation` module (language packs are on-device).
- **Display and storage paths are separated**: the translation is used only for display; the file always stores the **original text**.
- Falls back to original-text display when the language pack is missing or translation fails.

→ Implementation: [`AppleTranslator.swift`](Sources/SpeechTapInfrastructure/AppleTranslator.swift)

> Note: the macOS 26 production API wiring of the Translation framework is partly a skeleton; it currently operates via original-text fallback (see [Limitations](#limitations)).

### 5. NaturalLanguage (automatic language detection)

- `NLLanguageRecognizer` auto-detects the language of the recognized text and only routes through translation when it is non-Japanese.

→ Implementation: [`AppleLanguageDetector.swift`](Sources/SpeechTapInfrastructure/AppleLanguageDetector.swift)

### 6. OpenAI-compatible transcript correction (optional)

When explicitly enabled, the finalized session transcript is sent to a configured OpenAI-compatible `/chat/completions` API for conservative ASR cleanup.

- Disabled by default (`LLM_CORRECTION_ENABLED=false`).
- The original `transcript.txt` and regular Downloads session export stay untouched.
- The corrected text is written as `speech-tap-YYYYMMDD-HHmmss-corrected.txt`.
- Configure the API base URL, model, API key, temperature, timeout, and provider-specific thinking control in `config.conf`.

→ Implementation: [`OpenAICompatibleTranscriptCorrector.swift`](Sources/SpeechTapInfrastructure/OpenAICompatibleTranscriptCorrector.swift)

---

## Architecture

Strict **3-layer architecture** (dependencies flow one way only: presentation → domain → infrastructure).

```
presentation/   Menu-bar UI, windows, Composition Root (OS/UI dependencies allowed)
      │  ↓ depends on
domain/         Transcription service, state management, ports (protocols). Pure logic, no OS/UI dependency
      │  ↑ implements ports (no reverse dependency)
infrastructure/ Contact with OS APIs: Core Audio / SpeechAnalyzer / Translation / NaturalLanguage / files
```

- **The domain layer imports no OS/UI framework** (Foundation only). Swift Package target separation makes reverse dependencies impossible at compile time.
- All OS dependencies are hidden behind ports (`AudioSource` / `SpeechRecognizer` / `Translator` / `LanguageDetector` / `SessionExporter` / `PermissionGate`, …).
- Concrete implementations are injected at startup (Composition Root).

The design rationale and decisions (ADRs) are recorded in detail in [`SPEC.md`](SPEC.md).

---

## Requirements

- **macOS 26 (Tahoe) or later** (SpeechAnalyzer requirement)
- **Swift 6.3 or later** / Apple Silicon (arm64)
- Xcode (macOS 26 SDK)

The generated installer package checks **macOS 26.0+** and **Apple Silicon / arm64** before installation. If the target Mac does not satisfy those requirements, Installer stops before copying `SpeechTap.app`.

---

## Build & Run

```bash
# Tests (centered on OS-independent domain logic)
swift test            # 73 tests / 14 suites

# Dev build
swift build -c release

# Bundle as an arm64 .app, plus an installer pkg and .app zip
bash scripts/make_app.sh
open build/SpeechTap.app
```

The package script produces `build/SpeechTap.app`, `build/SpeechTap-arm64.pkg`, and `build/SpeechTap-arm64.app.zip`.
Install the pkg on another Apple Silicon Mac to place the app in `/Applications`, then launch `SpeechTap.app` by double-clicking it.
The pkg is a product archive with a Distribution check for macOS 26.0+ and arm64.

On launch, a mic icon appears in the menu bar. Pick an app → "Start transcription"; the first time, an **audio-capture permission** dialog appears (approval required). During recording, the menu-bar mic turns red.

---

## Permissions (TCC)

- Only the **audio-capture permission** is needed (`NSAudioCaptureUsageDescription`).
- **Screen-recording and microphone permissions are not needed** (it uses Core Audio Process Tap, not ScreenCaptureKit).
- Audio capture never starts while permission is not granted.

---

## Configuration

Settings are not hard-coded; they are separated into an external file (see [`config.example.conf`](config.example.conf)).

```conf
TARGET_APP_ID=            # target app's bundle id (chosen in the UI if unset)
LOCALE=ja-JP              # recognition language (BCP-47)
OUTPUT_PATH=~/Downloads/speech-tap/transcript.txt   # output path for finalized transcripts

# Optional LLM correction. Keep disabled unless you explicitly want transcript text
# to be sent to the configured OpenAI-compatible API.
LLM_CORRECTION_ENABLED=false
LLM_API_BASE_URL=http://192.168.3.18:30000/v1
LLM_API_KEY=
LLM_MODEL=qwen3.5-122b
LLM_TEMPERATURE=0
LLM_TIMEOUT_SECONDS=300
LLM_MAX_TOKENS=32768
LLM_DISABLE_THINKING=true
```

Real values placed at `~/.config/speech-tap/config.conf` take precedence (not tracked by git).

For the local GX10 `qwen3.5-122b` endpoint, keep `LLM_DISABLE_THINKING=true`; speech-tap sends top-level `chat_template_kwargs.enable_thinking=false` in the OpenAI-compatible JSON body to avoid reasoning-only output. `LLM_MAX_TOKENS=32768` follows the existing long-form Japanese benchmark settings. For other OpenAI-compatible APIs, leave `LLM_DISABLE_THINKING=false` and clear or lower `LLM_MAX_TOKENS` if the provider rejects those values.

---

## Limitations

- **Translation framework wiring is partly a skeleton**: it currently falls back to original-text display when translation fails (finalizing the production API on a real macOS 26 device is remaining work).
- LLM correction depends on the configured API returning `choices[].message.content`. Reasoning-only responses are rejected and do not create corrected files.
- `responsibility_get_pid_responsible_for_pid` is a private libproc symbol (intended for local use).
- Speaker diarization (who said what) is out of scope (Apple's on-device API has no such module).
- Only one target app can be transcribed at a time.

---

## License

Released under the [MIT License](LICENSE).

---

## 日本語

🌐 [English](#speech-tap) | **日本語**

> 特定の macOS アプリ（会議アプリ・ブラウザの動画・ポッドキャストなど）が**出力する音声だけ**を選んで、Apple のオンデバイス音声認識 **SpeechAnalyzer**（macOS 26）でリアルタイムに文字起こしする常駐アプリです。音声もテキストも一切クラウドに送信しません（オンデバイス完結）。

> 実験リポジトリ [`vibe-whims`](https://github.com/nob-git-dev/vibe-whims) の一部。`swift` 製の macOS メニューバー常駐アプリです。

---

### 特徴

- 🎯 **アプリ単位で音声を選択** — 「このアプリの音声だけ」を文字化。他アプリ・マイク・システム音は混入しない
- 🧠 **完全オンデバイス** — Apple SpeechAnalyzer による音声認識。ネットワーク送信なし
- ⏱ **リアルタイム表示** — 暫定（volatile）結果を即時表示、確定（finalized）結果を保存
- 💾 **クラッシュ耐性のある保存** — 確定テキストを即座にファイルへ追記。アプリが落ちても確定済み分は残る
- 🌐 **オンデバイス翻訳** — 非日本語の音声を Apple Translation framework で日本語表示（保存は原文のまま）
- 🌍 **多言語認識** — メニューで認識言語を選択。SpeechTranscriber が会話中の言語切替に自動追従
- 🪟 **ピン留め** — 文字起こしウィンドウを常に最前面に固定
- 📤 **セッション書き出し** — 停止時にそのセッション分を Downloads へ独立ファイルとして保存
- 🧹 **任意の LLM 校正** — 停止後のセッション原文を設定した OpenAI 互換 API に送り、別の `*-corrected.txt` として保存。原文ファイルは変更しない

---

### 使用している Apple の新しい API

このプロジェクトは、利用可能になる macOS バージョンが異なる Apple オンデバイス API を組み合わせています。文字起こしに必須の `SpeechAnalyzer` / `SpeechTranscriber` が必要なため、実効的な動作要件は **macOS 26.0 以降**です。

#### 1. SpeechAnalyzer / SpeechTranscriber（音声認識・**macOS 26+**）

WWDC25 で発表された Apple の新しいオンデバイス音声認識フレームワーク。従来の `SFSpeechRecognizer` を置き換える、モジュール型・並行処理対応・完全オフラインの API です。

- `SpeechAnalyzer` に `SpeechTranscriber` モジュールを組み込み、解析セッションを管理
- 入力音声は `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` が示すフォーマットへ変換して `AnalyzerInput` として供給
- 結果は **volatile（暫定）** と **finalized（確定）** の 2 種が `AsyncStream` で流れる
- `AssetInventory.assetInstallationRequest(supporting:)` で言語モデル（言語パック）をオンデバイスに自動インストール
- 初期ロケールを与えると、**会話中の言語切替に自動追従**する
- 停止時は `finalizeAndFinishThroughEndOfInput()` で最後の確定結果まで流し切る

→ 実装: [`SpeechAnalyzerAdapter.swift`](Sources/SpeechTapInfrastructure/SpeechAnalyzerAdapter.swift)

#### 2. Core Audio Process Tap（アプリ別オーディオ取得・**macOS 14.2+**）

「特定プロセスの音声出力だけ」をタップする Core Audio の API。本アプリの**最重要機能=非混入**を支えます。

- `kAudioHardwarePropertyTranslatePIDToProcessObject` で PID → `AudioObjectID`（オーディオプロセスオブジェクト）へ変換
- `CATapDescription(stereoMixdownOfProcesses:)` で**対象プロセスのみ**を含むタップを構成（グローバルタップ・除外タップは使わない＝構造的に非混入）
- `AudioHardwareCreateProcessTap` でタップを生成、`kAudioTapPropertyFormat` で native フォーマットを取得
- タップを内包した Aggregate Device（`AudioHardwareCreateAggregateDevice`、`kAudioAggregateDeviceIsPrivateKey`）を構成し、IOProc で PCM を受信
- I/O コールバック（リアルタイムスレッド）はサンプルをコピーして流すだけ。フォーマット変換は下流で実施

→ 実装: [`ProcessTapAudioSource.swift`](Sources/SpeechTapInfrastructure/ProcessTapAudioSource.swift)

#### 3. マルチプロセス対応（ブラウザ捕捉）— `responsibility_get_pid_responsible_for_pid`

Chrome などのブラウザは、音声を**メインプロセスではなくレンダラー/ヘルパープロセス**から出力します。これらは `NSRunningApplication` に登録されず bundleId も取れないため、メイン PID をタップしても無音になります。

- libproc の `responsibility_get_pid_responsible_for_pid(pid)` で各プロセスの「責任元 PID」を取得
- **責任元が対象アプリのメイン PID と一致するプロセスのみ**をタップ対象に追加（＝レンダラーを捕捉）
- 他アプリに責任を持つプロセス・取得失敗・曖昧なものは**除外**（非混入を厳守）
- 集めたプロセス群を `CATapDescription(stereoMixdownOfProcesses: [...])` に複数渡してまとめてタップ

> ⚠️ `responsibility_get_pid_responsible_for_pid` は公開ドキュメントの無い libproc シンボルです。App Store 配布アプリでの使用には注意が必要です（本アプリはローカル利用前提）。

→ 実装: [`ProcessMatcher.swift`](Sources/SpeechTapInfrastructure/ProcessMatcher.swift) / [`CProcResponsibility`](Sources/CProcResponsibility/)

#### 4. Apple Translation framework（オンデバイス翻訳）

非日本語の認識結果を、クラウドに送らずオンデバイスで日本語へ翻訳して表示します。

- `Translation` モジュールで翻訳セッションを構成（言語パックはオンデバイス）
- **画面表示と保存の経路を分離**: 翻訳結果は表示にのみ使い、ファイルへは常に**原文**を保存
- 言語パック未取得・翻訳失敗時は原文表示にフォールバック

→ 実装: [`AppleTranslator.swift`](Sources/SpeechTapInfrastructure/AppleTranslator.swift)

> 注: Translation framework の macOS 26 向け正式 API 結線は一部スケルトン段階で、現状は原文フォールバックで動作します（[制限事項](#制限事項既知の制約-1)参照）。

#### 5. NaturalLanguage（言語自動検出）

- `NLLanguageRecognizer` で認識結果テキストの言語を自動判定し、非日本語のときだけ翻訳パスを通します

→ 実装: [`AppleLanguageDetector.swift`](Sources/SpeechTapInfrastructure/AppleLanguageDetector.swift)

#### 6. OpenAI 互換 transcript 校正（任意）

明示的に有効化した場合だけ、確定済みセッション transcript を OpenAI 互換 `/chat/completions` API に送り、ASR 特有の誤変換や句読点不足を保守的に校正します。

- 既定は無効（`LLM_CORRECTION_ENABLED=false`）
- 通常の `transcript.txt` と Downloads の原文セッション複本は変更しない
- 校正結果は `speech-tap-YYYYMMDD-HHmmss-corrected.txt` として別保存
- API base URL、モデル、API key、temperature、timeout、provider 固有の thinking 制御は `config.conf` で設定

→ 実装: [`OpenAICompatibleTranscriptCorrector.swift`](Sources/SpeechTapInfrastructure/OpenAICompatibleTranscriptCorrector.swift)

---

### アーキテクチャ

厳格な **3層アーキテクチャ**（依存方向は presentation → domain → infrastructure の一方向のみ）で構成しています。

```
presentation/   メニューバー UI・ウィンドウ・Composition Root（OS/UI 依存可）
      │  ↓ 依存
domain/         文字化サービス・状態管理・port（protocol）。OS/UI に一切依存しない純粋ロジック
      │  ↑ port を実装（逆依存なし）
infrastructure/ Core Audio / SpeechAnalyzer / Translation / NaturalLanguage / ファイル等 OS API への接触
```

- **domain は OS/UI フレームワークを import しない**（Foundation のみ）。Swift Package のターゲット分離により、逆依存はコンパイル時に不可能
- OS 依存はすべて port（`AudioSource` / `SpeechRecognizer` / `Translator` / `LanguageDetector` / `SessionExporter` / `PermissionGate` など）の背後に隠蔽
- 具体実装は起動時（Composition Root）に注入

設計の経緯・意思決定（ADR）は [`SPEC.md`](SPEC.md) に詳細を記録しています。

---

### 動作環境

- **macOS 26（Tahoe）以降**（SpeechAnalyzer の要件）
- **Swift 6.3 以降** / Apple Silicon（arm64）
- Xcode（macOS 26 SDK）

生成されるインストーラ pkg は、インストール前に **macOS 26.0 以降** と **Apple Silicon / arm64** を確認します。条件を満たさない Mac では、`SpeechTap.app` をコピーする前にインストールを停止します。

---

### ビルドと実行

```bash
# テスト（OS 非依存の domain ロジックを中心に検証）
swift test            # 73 tests / 14 suites

# 開発ビルド
swift build -c release

# arm64 .app / インストーラ pkg / .app zip を生成して起動
bash scripts/make_app.sh
open build/SpeechTap.app
```

パッケージスクリプトは `build/SpeechTap.app`、`build/SpeechTap-arm64.pkg`、`build/SpeechTap-arm64.app.zip` を生成します。
別の Apple Silicon Mac では pkg をインストールすると `/Applications` に配置され、`SpeechTap.app` をダブルクリックして起動できます。
pkg は Distribution 付きの product archive として生成され、macOS 26.0 以降と arm64 をインストール時にチェックします。

起動するとメニューバーにマイクアイコンが常駐します。アプリを選択 → 「文字化を開始」で、初回は**音声キャプチャ許可**のダイアログが出ます（許可が必要）。録音中はメニューバーのマイクが赤くなります。

---

### 権限（TCC）

- 必要なのは **音声キャプチャ権限のみ**（`NSAudioCaptureUsageDescription`）
- **画面収録権限・マイク権限は不要**（ScreenCaptureKit ではなく Core Audio Process Tap を採用しているため）
- 未許可のまま音声取得を開始しません

---

### 設定

設定値はコードに直書きせず、外部ファイルに分離しています（[`config.example.conf`](config.example.conf) 参照）。

```conf
TARGET_APP_ID=            # 対象アプリの bundleId（未指定なら UI で選択）
LOCALE=ja-JP              # 認識言語（BCP-47）
OUTPUT_PATH=~/Downloads/speech-tap/transcript.txt   # 確定文字起こしの出力先

# 任意の LLM 校正。true にすると transcript text が設定 API に送信されます。
LLM_CORRECTION_ENABLED=false
LLM_API_BASE_URL=http://192.168.3.18:30000/v1
LLM_API_KEY=
LLM_MODEL=qwen3.5-122b
LLM_TEMPERATURE=0
LLM_TIMEOUT_SECONDS=300
LLM_MAX_TOKENS=32768
LLM_DISABLE_THINKING=true
```

実値は `~/.config/speech-tap/config.conf` に置くと優先されます（git 管理外）。

GX10 のローカル `qwen3.5-122b` endpoint では `LLM_DISABLE_THINKING=true` のまま使ってください。speech-tap は OpenAI 互換 JSON body のトップレベルに `chat_template_kwargs.enable_thinking=false` を送り、reasoning-only 応答を避けます。`LLM_MAX_TOKENS=32768` は既存の日本語長文ベンチマーク設定に合わせた推奨値です。他の OpenAI 互換 API では、未知パラメータを拒否する場合があるため `LLM_DISABLE_THINKING=false` にし、必要なら `LLM_MAX_TOKENS` を空または低い値にしてください。

---

### 制限事項・既知の制約

- **Apple Translation framework の本結線が一部スケルトン**: 現状は翻訳に失敗すると原文表示にフォールバックします（macOS 26 実機での正式 API 確定が残作業）
- LLM 校正は設定 API が `choices[].message.content` を返すことを前提にします。reasoning だけで本文が空の応答は校正失敗として扱い、corrected ファイルを作りません。
- `responsibility_get_pid_responsible_for_pid` は非公開 libproc シンボル（ローカル利用前提）
- 話者分離（誰が話したか）は対象外（Apple のオンデバイス API に該当モジュールが無いため）
- 同時に文字化できる対象アプリは 1 つ

---

### ライセンス

[MIT License](LICENSE) で公開しています。
