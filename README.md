# vibe-whims — macOS アプリ別 音声文字起こし（オンデバイス）

特定の macOS アプリ（会議アプリ・ブラウザの動画・ポッドキャストなど）が**出力する音声だけ**を選んで、
Apple のオンデバイス音声認識 **SpeechAnalyzer** でリアルタイムに文字起こしする常駐アプリです。
音声もテキストも一切クラウドに送信しません（オンデバイス完結）。

> 内部プロジェクト名は `speech-tap`。`swift` 製の macOS メニューバー常駐アプリです。

---

## 特徴

- 🎯 **アプリ単位で音声を選択** — 「このアプリの音声だけ」を文字化。他アプリ・マイク・システム音は混入しない
- 🧠 **完全オンデバイス** — Apple SpeechAnalyzer による音声認識。ネットワーク送信なし
- ⏱ **リアルタイム表示** — 暫定（volatile）結果を即時表示、確定（finalized）結果を保存
- 💾 **クラッシュ耐性のある保存** — 確定テキストを即座にファイルへ追記。アプリが落ちても確定済み分は残る
- 🌐 **オンデバイス翻訳** — 非日本語の音声を Apple Translation framework で日本語表示（保存は原文のまま）
- 🌍 **多言語認識** — メニューで認識言語を選択。SpeechTranscriber が会話中の言語切替に自動追従
- 🪟 **ピン留め** — 文字起こしウィンドウを常に最前面に固定
- 📤 **セッション書き出し** — 停止時にそのセッション分を Downloads へ独立ファイルとして保存

---

## 使用している Apple の新しい API

このプロジェクトは、macOS 26（Tahoe）世代で利用可能になった/拡張された Apple のオンデバイス API を組み合わせています。

### 1. SpeechAnalyzer / SpeechTranscriber（音声認識・**macOS 26+**）

WWDC25 で発表された Apple の新しいオンデバイス音声認識フレームワーク。従来の `SFSpeechRecognizer` を置き換える、
モジュール型・並行処理対応・完全オフラインの API です。

- `SpeechAnalyzer` に `SpeechTranscriber` モジュールを組み込み、解析セッションを管理
- 入力音声は `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` が示すフォーマットへ変換して `AnalyzerInput` として供給
- 結果は **volatile（暫定）** と **finalized（確定）** の 2 種が `AsyncStream` で流れる
- `AssetInventory.assetInstallationRequest(supporting:)` で言語モデル（言語パック）をオンデバイスに自動インストール
- 初期ロケールを与えると、**会話中の言語切替に自動追従**する
- 停止時は `finalizeAndFinishThroughEndOfInput()` で最後の確定結果まで流し切る

→ 実装: [`SpeechAnalyzerAdapter.swift`](Sources/SpeechTapInfrastructure/SpeechAnalyzerAdapter.swift)

### 2. Core Audio Process Tap（アプリ別オーディオ取得・**macOS 14.4+**）

「特定プロセスの音声出力だけ」をタップする Core Audio の API。本アプリの**最重要機能=非混入**を支えます。

- `kAudioHardwarePropertyTranslatePIDToProcessObject` で PID → `AudioObjectID`（オーディオプロセスオブジェクト）へ変換
- `CATapDescription(stereoMixdownOfProcesses:)` で**対象プロセスのみ**を含むタップを構成（グローバルタップ・除外タップは使わない＝構造的に非混入）
- `AudioHardwareCreateProcessTap` でタップを生成、`kAudioTapPropertyFormat` で native フォーマットを取得
- タップを内包した Aggregate Device（`AudioHardwareCreateAggregateDevice`、`kAudioAggregateDeviceIsPrivateKey`）を構成し、IOProc で PCM を受信
- I/O コールバック（リアルタイムスレッド）はサンプルをコピーして流すだけ。フォーマット変換は下流で実施

→ 実装: [`ProcessTapAudioSource.swift`](Sources/SpeechTapInfrastructure/ProcessTapAudioSource.swift)

### 3. マルチプロセス対応（ブラウザ捕捉）— `responsibility_get_pid_responsible_for_pid`

Chrome などのブラウザは、音声を**メインプロセスではなくレンダラー/ヘルパープロセス**から出力します。
これらは `NSRunningApplication` に登録されず bundleId も取れないため、メイン PID をタップしても無音になります。

- libproc の `responsibility_get_pid_responsible_for_pid(pid)` で各プロセスの「責任元 PID」を取得
- **責任元が対象アプリのメイン PID と一致するプロセスのみ**をタップ対象に追加（＝レンダラーを捕捉）
- 他アプリに責任を持つプロセス・取得失敗・曖昧なものは**除外**（非混入を厳守）
- 集めたプロセス群を `CATapDescription(stereoMixdownOfProcesses: [...])` に複数渡してまとめてタップ

> ⚠️ `responsibility_get_pid_responsible_for_pid` は公開ドキュメントの無い libproc シンボルです。
> App Store 配布アプリでの使用には注意が必要です（本アプリはローカル利用前提）。

→ 実装: [`ProcessMatcher.swift`](Sources/SpeechTapInfrastructure/ProcessMatcher.swift) / [`CProcResponsibility`](Sources/CProcResponsibility/)

### 4. Apple Translation framework（オンデバイス翻訳）

非日本語の認識結果を、クラウドに送らずオンデバイスで日本語へ翻訳して表示します。

- `Translation` モジュールで翻訳セッションを構成（言語パックはオンデバイス）
- **画面表示と保存の経路を分離**: 翻訳結果は表示にのみ使い、ファイルへは常に**原文**を保存
- 言語パック未取得・翻訳失敗時は原文表示にフォールバック

→ 実装: [`AppleTranslator.swift`](Sources/SpeechTapInfrastructure/AppleTranslator.swift)

> 注: Translation framework の macOS 26 向け正式 API 結線は一部スケルトン段階で、現状は原文フォールバックで動作します（[制限事項](#制限事項既知の制約)参照）。

### 5. NaturalLanguage（言語自動検出）

- `NLLanguageRecognizer` で認識結果テキストの言語を自動判定し、非日本語のときだけ翻訳パスを通します

→ 実装: [`AppleLanguageDetector.swift`](Sources/SpeechTapInfrastructure/AppleLanguageDetector.swift)

---

## アーキテクチャ

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

## 動作環境

- **macOS 26（Tahoe）以降**（SpeechAnalyzer の要件）
- **Swift 6.3 以降** / Apple Silicon（arm64）
- Xcode（macOS 26 SDK）

---

## ビルドと実行

```bash
# テスト（OS 非依存の domain ロジックを中心に検証）
swift test            # 59 tests / 11 suites

# 開発ビルド
swift build -c release

# .app バンドル化（ad-hoc 署名・音声キャプチャ entitlement 付き）して起動
bash scripts/make_app.sh
open build/SpeechTap.app
```

起動するとメニューバーに 🎙 アイコンが常駐します。アプリを選択 → 「文字化を開始」で、
初回は**音声キャプチャ許可**のダイアログが出ます（許可が必要）。

---

## 権限（TCC）

- 必要なのは **音声キャプチャ権限のみ**（`NSAudioCaptureUsageDescription`）
- **画面収録権限・マイク権限は不要**（ScreenCaptureKit ではなく Core Audio Process Tap を採用しているため）
- 未許可のまま音声取得を開始しません

---

## 設定

設定値はコードに直書きせず、外部ファイルに分離しています（[`config.example.conf`](config.example.conf) 参照）。

```conf
TARGET_APP_ID=            # 対象アプリの bundleId（未指定なら UI で選択）
LOCALE=ja-JP              # 認識言語（BCP-47）
OUTPUT_PATH=~/Documents/speech-tap/transcript.txt   # 確定文字起こしの出力先
```

実値は `~/.config/speech-tap/config.conf` に置くと優先されます（git 管理外）。

---

## 制限事項・既知の制約

- **Apple Translation framework の本結線が一部スケルトン**: 現状は翻訳に失敗すると原文表示にフォールバックします（macOS 26 実機での正式 API 確定が残作業）
- `responsibility_get_pid_responsible_for_pid` は非公開 libproc シンボル（ローカル利用前提）
- 話者分離（誰が話したか）は対象外（Apple のオンデバイス API に該当モジュールが無いため）
- 同時に文字化できる対象アプリは 1 つ

---

## ライセンス

[MIT License](LICENSE) で公開しています。
