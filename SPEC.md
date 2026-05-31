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
| 文字起こし表示・保存 | 文字化結果をユーザーが読め、後から参照できるようにする | 確定結果を取りこぼさず提示・保存できること（正常停止時に加え、**文字化中のクラッシュ・強制終了時にも確定済み分が失われない**こと。ADR-4） |
| TCC 権限フロー | 必要な OS 権限が無いと音声取得・文字化が成立しないため、取得を案内する | 権限が無い状態を黙って失敗させず、ユーザーに分かる形で促すこと |
| セッション複本エクスポート（機能A） | ユーザーがセッション単位でテキストを取り出し、共有・保存・再利用できるようにする | セッション分のテキストが Downloads に**独立した 1 ファイルとして残ること**／メインファイル（`transcript.txt`）の append 継続性を壊さないこと／停止操作の主経路（finalize → flush）を妨げないこと |
| オンデバイス翻訳表示（機能B） | 日本語話者が非日本語の音声でも内容をリアルタイムに理解できるようにする | **翻訳もオンデバイスで完結**すること（音声・テキストとも外部送信しない）／**保存は原文**（画面表示と保存の経路を分離）／言語を自動検出してユーザーに切替を意識させないこと／翻訳が使えない時も黙って空表示にせずユーザーに通知すること |
| 常時最前面表示（機能C） | 他アプリで作業中も文字起こしウィンドウが背面に隠れず、視聴・会議と同時参照できるようにする | ユーザーが意図して ON/OFF できること／他アプリの作業を阻害しないこと／状態はセッション内に閉じ（再起動でリセット）、勝手に最前面に戻らないこと |

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
   - **確定（finalized）結果が SpeechAnalyzer から流れてくるたびに、`TranscriptSink.append` を呼び、即座にファイル末尾へ追記する（メモリバッファに溜めない）。これにより文字化中のクラッシュ時にも確定済み分が失われない。**
   - 出力: テキストが追記・更新され、確定結果は受信のたびに即時保存先へ追記される。

5.5 **翻訳（非日本語音声のとき / 機能B）**
   - 入力: SpeechAnalyzer から受け取った認識結果（volatile / finalized）。
   - 処理: 各結果に対し `LanguageDetector`（NLLanguageRecognizer 想定）で言語を判定する。
     日本語と判定された場合は翻訳せずそのまま表示に回す。
     日本語以外と判定された場合は `Translator`（Apple Translation framework 想定）でオンデバイス翻訳し、日本語へ変換する。
     **翻訳結果は表示用パスにのみ流し、保存パス（`TranscriptSink`）には常に原文を渡す**（画面表示と永続保存の経路分離）。
   - フォールバック: 翻訳パック未インストール / 翻訳不可な場合は、表示も原文のままにフォールバックし、ユーザーに通知する（ダイアログ / メニュー表示 / 状態行など。具体 UI は /architect で確定）。黙って空表示・クラッシュにしない。
   - オンデバイス完結: 翻訳エンジンは Apple Translation framework（オンデバイス）に固定し、音声・テキストとも外部送信しない（固定要件）。初回利用時にユーザーが言語パックのダウンロードを許諾するフローを通る点も要件として明記する。
   - 出力: **画面表示は日本語訳のみ**（原文は画面に出さない）。volatile / finalized の区別は維持し、確定済み訳を順次表示する（volatile を末尾にグレー表示してよい）。
   - **保存への波及はゼロ**: メインファイル（`transcript.txt`）も Downloads セッション複本（後述 6）も原文のまま保存される。翻訳結果はどのファイルにも保存しない。

6. **文字化の停止 / 終了**
   - 入力: 停止操作またはアプリ終了。
   - 処理: オーディオ取得と SpeechAnalyzer を停止し、リソースを解放する。確定テキストを保存する。
   - **既存の finalize → flush は維持する。flush は「保留中があれば確実に書き出す安全網」として残し、最後の確定結果まで保存されることを保証する**（即時 append 設計でも flush 契約は壊さない）。
   - **セッション複本の Downloads エクスポート（機能A）**: メインファイル（`transcript.txt`）への最終確定書き出し完了後、
     **そのセッション中に確定したテキストのみ**を Downloads にタイムスタンプ付きの独立ファイル（推奨: `~/Downloads/speech-tap-YYYYMMDD-HHmmss.txt`）として書き出す。
     既存メインファイルへの append は変更せず、Downloads 側はあくまで「そのセッション分の独立コピー」とする。保存内容は原文（機能B の翻訳結果は含めない）。
   - **表示クリア確認ダイアログ（機能A）**: 複本の書き出しが完了した後、ユーザーに「ウィンドウに表示されているテキストを削除してよいか」を確認するダイアログを提示する。
     Yes → 表示ウィンドウのテキスト（および表示用バッファ）をクリア。No → 表示を残す。どちらの場合もメインファイル `transcript.txt` の中身には影響しない。
   - **次セッション継続性（機能A）**: メインファイル `transcript.txt` は append-only を維持するため、次回「文字化を開始」したとき、確定結果は同じファイルの末尾に続けて積まれる。既存内容は壊さない。
   - 出力: 文字化が停止し、メインファイルへの確定結果保存・Downloads への複本書き出し・表示クリア可否の確認が完了する。

### 画面操作: ピン（機能C）
- 入力: 文字起こし表示ウィンドウ上のピン操作（ボタン or メニュー）。
- 処理:
  - 押下時: ウィンドウを常に最前面に切り替える（`NSWindow.level = .floating` 想定。具体実装は presentation 層に閉じる）。
  - 再度押下: 最前面状態を解除し、通常のウィンドウレベルに戻す。
  - **ピン状態は永続化しない**: アプリ再起動ごとに OFF で開始する。設定ファイル・UserDefaults 等にも保存しない。
- 出力: ピン中は他アプリの上にウィンドウが常に表示される。ピン中であることが視覚的に分かる（ボタンの押下状態 / アイコン強調等のトグル表示）。

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

### クラッシュ耐性（確定結果の即時永続化）
- [ ] 文字化中に **確定（finalized）結果が出るたびに、それが速やかに出力先ファイルへ追記**されている
      （ある finalized 結果の受信からファイル反映までの遅延が実用的に短い）。
- [ ] アプリが文字化中に**予期せず終了（クラッシュ・強制終了）した場合でも、その時点までに確定した結果はファイルに残っている**
      （停止操作を経ずとも確定済み分は失われない）。
- [ ] 出力ファイルは**1つ**であり、新たな確定結果は**末尾に追記**される
      （停止のたびに新規ファイルを作らない・既存内容を上書きしない）。

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

### セッション複本エクスポート要件（機能A）
- [ ] 停止操作を行うと、メインファイル（`transcript.txt`）への最終確定書き出し完了後、
      Downloads に**そのセッション分の確定テキストを含む新規 `.txt`** が作成される（毎セッション独立ファイル・既存ファイルを上書きしない）。
- [ ] Downloads の複本のファイル名はセッションごとに一意（タイムスタンプ等で区別可能。具体規則は /architect で確定）。
- [ ] 複本書き出しの完了後、ユーザーに表示クリアの可否を確認するダイアログが提示される。
      Yes で表示ウィンドウのテキストがクリアされ、No で表示が残る。どちらの場合もメインファイル `transcript.txt` の中身には影響しない。
- [ ] 次回「文字化を開始」したとき、メインファイル `transcript.txt` には**続きが append される**。
      既存の内容は壊れず、過去の確定結果も残ったままで新しい確定結果が末尾に積まれる。
- [ ] Downloads の複本書き出しに失敗してもメインファイルへの保存（既存の取りこぼし防止本質）は損なわれない
      （複本の失敗は停止フロー全体を巻き戻さない。失敗はユーザーに通知する）。

### 翻訳要件（機能B）
- [ ] 非日本語の音声を再生したとき、画面に**日本語訳がリアルタイムに表示**される（オンデバイス）。
- [ ] 日本語の音声を再生したときは翻訳されず、原文（日本語）のまま表示される。
- [ ] 翻訳結果は **`transcript.txt` にも Downloads 複本にも保存されない**。保存はどちらも原文のみ。
- [ ] 翻訳はオンデバイスで完結し、外部送信が発生しないことが**観測可能**である（ネットワーク送信コードを持たない・実機でネットワークコール無しを観測できる）。
- [ ] 翻訳パックが未インストール / 利用不可な場合、ユーザーにその旨が通知され、表示は**原文にフォールバック**する（黙って空表示・クラッシュにならない）。
- [ ] 初回利用時の言語パックダウンロード許諾フローを通って利用できる（ダウンロード未許諾の場合はフォールバック挙動）。

### UI 要件（機能C）
- [ ] 文字起こしウィンドウに「ピン」操作（ボタン or メニュー）があり、押下するとウィンドウが**常に最前面**に表示される。
- [ ] ピン中に再度押下すると最前面状態が**解除**され、通常のウィンドウレベルに戻る。
- [ ] ピン中であることが**視覚的に区別**できる（ボタンの押下状態・アイコン強調等のトグル表示）。
- [ ] ピン状態は**アプリ再起動でリセット**される（毎起動 OFF で開始。設定ファイル・UserDefaults 等にも保存しない）。

---

## スコープ（やらないこと）

- 自分のマイク入力（発話）の文字起こしは対象外（対象アプリの出力音声のみを扱う）。
- 複数アプリの同時文字化は初期スコープ外（対象アプリは同時に 1 つ）。
- 話者分離（誰が話したかの識別）は初期スコープ外。
  本クラッシュ耐性対応（即時 append 化）でも**話者分離はスコープ外のまま**である。
  Apple SpeechAnalyzer に話者分離モジュールは存在しない
  （公式確認済み: SpeechTranscriber / DictationTranscriber / SpeechDetector の 3 モジュールのみ）。
- **翻訳は機能B でスコープに含める**（非日本語音声を**オンデバイスで日本語に翻訳して表示**する）。
  ただし**保存対象は原文のみ**で、翻訳結果はファイルに保存しない（画面表示と保存の経路分離）。
  要約・話者分離など、その他の後処理は引き続き初期スコープ外。
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
- **翻訳エンジン**: **Apple の Translation framework（オンデバイス）に固定**。
  他翻訳サービス（Google / DeepL / OpenAI 等のクラウド系）に置き換えない。
  これは固定要件「オンデバイス完結」を翻訳側に拡張するもので、音声に加えてテキストも外部送信しない。
- **画面表示と永続保存の経路分離**: 翻訳結果は**表示用にのみ生成**し、`TranscriptSink`（保存先）には常に原文（SpeechAnalyzer が返した認識結果のテキスト）を渡す。
  メインファイル（`transcript.txt`）と Downloads セッション複本のいずれも原文のみが保存される。
- **オンデバイス完結の翻訳側への拡張**: 音声・テキストとも外部に送信しない（既存「オンデバイス完結」の意味を翻訳にも適用）。
- **セッション複本エクスポートの非破壊性（機能A）**: 停止時の Downloads 複本書き出しは、既存のメインファイル `transcript.txt` への append 経路（ADR-3 / ADR-4）を**壊してはならない**。複本側の失敗は停止フロー全体を巻き戻さない（メインファイルへの保存は完了済みのまま）。
- **ピン状態の非永続化（機能C）**: ピン（最前面）状態はアプリ再起動ごとに OFF。設定ファイル・UserDefaults 等に保存しない。

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

### 新サイクル（機能A/B/C）で /architect が確定する未確定事項

以下は仕様上「やる」は確定しているが、設計判断（具体 API・タイミング・UI フロー）は /architect が ADR-5 / ADR-6 として確定する。

- **Downloads ファイル名規則（機能A）** — **Resolved（→ ADR-6）**。
  確定: `~/Downloads/speech-tap-YYYYMMDD-HHmmss.txt`（停止時刻ベース・ローカルタイム・24 時間表記）。秒精度衝突時は `-2`, `-3`, ... のサフィックスを拡張子の直前に付与。上書き禁止。
- **「セッション境界」概念の実装方針（機能A）** — **Resolved（→ ADR-6）**。
  確定: 「**開始操作（`TranscriptionService.start`）→ 停止操作（`TranscriptionService.stop`）まで**」を 1 セッション。プロセス再起動を跨いだ場合も別セッション。データ構造は `TranscriptStore._finalized` を「現セッションの確定列」と意味付けし再利用（新フィールド追加なし）。停止フローの末尾で `clearDisplay()` によりクリアする。
- **翻訳のタイミング（機能B）** — **Resolved（→ ADR-5）**。
  確定: **finalized のみ翻訳**する。volatile は原文をそのままグレー表示する（理由: `TranslationSession` 起動コスト・体感遅延・volatile の頻繁な書き換えに対する翻訳品質）。
- **翻訳パック未インストール時の UI フロー（機能B）** — **Resolved（→ ADR-5）**。
  確定: 二段階。(a) 初回検出時に Apple Translation framework のダウンロード許諾フローが OS から表示される。(b) 利用不可（throw）時はメニューバー状態行に「翻訳: 利用不可（原文表示）」と表示し、画面は原文にフォールバックする（黙って空表示にしない）。
- **`Translator` / `LanguageDetector` の正確な API シグネチャ（機能B）** — **Resolved（→ ADR-5）**。
  確定（Foundation のみ・OS 型を漏らさない）:
  - `Translator.translate(_ text: String, from source: Locale, to target: Locale) async throws -> String`
  - `Translator.ensureAvailable(for source: Locale) async throws`
  - `LanguageDetector.detect(_ text: String) -> Locale?`
- **Composition Root への注入順序（機能A/B/C）** — **Resolved（→ ADR-5 / ADR-6 / 「### Composition Root 注入順序（確定）」）**。
  確定: 既存の `TranscriptionService` のコンストラクタは触らず（翻訳は presentation の `DisplayPipeline` に閉じる）、`AppDelegate` で `AppleTranslator` / `AppleLanguageDetector` / `DisplayPipeline` / `DownloadsSessionExporter` / `StopFlowCoordinator` を順に生成・配線する。詳細は「## アーキテクチャ設計 → ### Composition Root 注入順序（確定）」参照。
- **ADR-5 / ADR-6 の追記（/architect）** — **Resolved**。「## アーキテクチャ設計 / ADR」セクションに ADR-5・ADR-6 を追加済み。
- **実装側からの確認（/tdd 2026-05-31）** — **Resolved**。Red→Green→Refactor で機能 A/B/C を実装。`TranscriptionService.stop()` の API は不変（戻り値・例外・コールバック全て既存と同じ）。`Translator` / `LanguageDetector` / `SessionExporter` の 3 つの新 port を Foundation のみで追加し、`TranscriptStore` に `snapshotCurrentSession(startedAt:stoppedAt:) -> TranscriptSession` / `clearDisplay()` を追加（`clearDisplay` は **TranscriptSink には何も発行しない** ことを SpyTranscriptSink で検証済み）。`DisplayPipeline` は OS/UI 非依存のため domain ターゲットに置く判断とした（実装側からの設計改善・固定要件「domain は OS/UI 非依存」と整合・テスト容易性を最大化）。`DownloadsSessionExporter` は秒精度衝突時に `-2`/`-3` サフィックスで安全側に倒すロジックを実装し一時ディレクトリで検証 PASS。`AppleTranslator` は macOS 26 の Translation framework API が実機未確定のためコンパイル通過するスケルトン（throw → DisplayPipeline の原文フォールバック経路を駆動）。`AppleLanguageDetector` は `NLLanguageRecognizer` を使用。Composition Root（`AppDelegate`）に `DisplayPipeline` / `DownloadsSessionExporter` / `StopFlowCoordinator` を順に生成・配線。**既存 30 テスト全 PASS** + **新規 14 テスト PASS** = 合計 44 tests / 9 suites（`swift build -Xswiftc -strict-concurrency=complete` 警告ゼロ・`swift build -c release` 成功）。

### 実機検証で確定する事項（決め打ちしない）

以下は ADR-5 / ADR-6 の判断には影響しないが、実装フェーズで実機検証して確定する。

- **Translation framework の macOS 26 での具体的 API 名称**（`TranslationSession` / `Configuration` / `availableLanguages` の正確なシグネチャと Sendable / actor 制約）。port シグネチャ（`Translator` / `LanguageDetector`）は Foundation の `Locale` で抽象化済みのため、API 名称差は infrastructure に閉じる。
- **サポートロケール一覧**（Apple Translation framework がどの言語ペアをオンデバイスでサポートしているか）。未サポート時のフォールバックは ADR-5 のとおり原文表示 + 状態行通知。
- **NLLanguageRecognizer の confidence しきい値**（短い発話・カタカナ・固有名詞での誤判定対策）。
- **`AppleTranslator` の actor / `TranslationSession` 保持戦略**（実機での Sendable 制約に応じて確定）。
- **言語パックダウンロードの実機での UX**（OS が出すダイアログの挙動が安定しているか）。

---

## システム構成（コンポーネント依存関係）
<!-- /architect が精緻化する。本セクションが影響範囲分析・テスト計画・デプロイチェックの根拠になる。 -->

3層の責務とコンポーネント:

- **presentation 層**
  - `MenuBarUI`（メニューバー常駐・対象アプリ選択 UI・文字起こし表示・権限案内 UI）
  - **TranscriptWindow（機能C: ピン操作 = `NSWindow.level = .floating` の切替を担当。状態は永続化しない）**
  - **DisplayPipeline（機能B: 「原文 → 言語検出 → 必要なら翻訳 → 表示」の合成経路。保存パスとは独立した表示用パイプライン）**
  - **StopFlowCoordinator（機能A: 停止時の「finalize → flush → Downloads 複本書き出し → 表示クリア確認ダイアログ」を順序付けて回す UI 駆動コーディネータ）**
- **domain 層**
  - `TranscriptionService`（文字化のユースケース調整: 開始・停止・状態管理）
  - `TranscriptStore`（文字起こし結果の集約・保持）
  - `AudioSource` / `SpeechRecognizer` / `AppEnumerator` / `PermissionGate`（**protocol = 抽象**。OS 依存を隠蔽する境界）
  - **`Translator` port（新規・機能B）**: 「原文を指定 locale から指定 locale へ翻訳する」抽象。OS 型を漏らさない。
  - **`LanguageDetector` port（新規・機能B）**: 「テキストから言語を検出する」抽象。OS 型を漏らさない。
  - **`SessionExporter` port（新規・機能A）**: 「セッション分の確定テキストを独立ファイルとして書き出す」抽象。保存先パスの決定・ファイル名生成も含める（具体規則は /architect 確定）。
- **infrastructure 層**
  - `AudioTapAdapter`（音声取得方式の実装。Core Audio Process Tap または ScreenCaptureKit を採用方式に応じて実装）
  - `SpeechAnalyzerAdapter`（Apple SpeechAnalyzer への接触）
  - `RunningAppProvider`（起動中／音声出力アプリの列挙）
  - `TCCPermissionAdapter`（マイク／画面収録等の権限確認・要求）
  - `ConfigLoader`（config ファイルの読み込み）
  - **`AppleTranslator`（新規・機能B）**: `Translator` 実装。Apple Translation framework（オンデバイス）を使用。言語パックの利用可否確認・初回ダウンロード許諾を扱う。
  - **`AppleLanguageDetector`（新規・機能B）**: `LanguageDetector` 実装。`NLLanguageRecognizer`（NaturalLanguage）を使用。
  - **`DownloadsSessionExporter`（新規・機能A）**: `SessionExporter` 実装。`~/Downloads/` 配下にタイムスタンプ付きファイル名で書き出す。

依存関係（テキスト形式・依存方向は上→下の一方向）:

```
[presentation] MenuBarUI / TranscriptWindow（機能C: ピン）
      │  DisplayPipeline（機能B: 表示用に原文→検出→翻訳）
      │  StopFlowCoordinator（機能A: 停止フロー駆動）
      │ 依存している（使う）
      ▼
[domain] TranscriptionService ── TranscriptStore
      │  （AudioSource / SpeechRecognizer / AppEnumerator / PermissionGate / TranscriptSink
      │   ＋新規: Translator / LanguageDetector / SessionExporter という protocol に依存）
      ▼ （protocol を実装するのは infrastructure。domain は実装を知らない＝逆依存なし）
[infrastructure]
      ProcessTapAudioSource ───▶ Core Audio Process Tap（OS フレームワーク, macOS 14.4+。ADR-1 で確定）
      SpeechAnalyzerAdapter ───▶ Apple SpeechAnalyzer（OS フレームワーク, macOS 26+）
      RunningAppProvider ──────▶ NSWorkspace / Core Audio process list（OS）
      AudioCapturePermission ──▶ TCC（音声キャプチャ権限 / NSAudioCaptureUsageDescription。画面収録/マイク権限は要求しない）
      ConfigLoader ────────────▶ config ファイル（.env / config.yaml）
      FileTranscriptSink ──────▶ ファイルシステム（メイン `transcript.txt` への即時 append。ADR-3/4）
      AppleTranslator ─────────▶ Apple Translation framework（オンデバイス。ADR-5）
      AppleLanguageDetector ──▶ NaturalLanguage / NLLanguageRecognizer（ADR-5）
      DownloadsSessionExporter ▶ ファイルシステム（~/Downloads セッション複本。ADR-6）
      OSEventLogger ───────────▶ os.Logger / OSLog（観測点。EventLogger 実装）
```

依存関係の要点:
- presentation は domain にのみ依存する。
- domain は infrastructure の **protocol（抽象）** にのみ依存し、具体実装（OS API）を知らない。
  具体 Adapter は起動時（composition root / presentation 起動部）で domain に注入する。
- infrastructure のみが OS フレームワーク（Core Audio / ScreenCaptureKit / SpeechAnalyzer / TCC / Translation / NaturalLanguage）に接触する。
- **機能B の表示パスは presentation の DisplayPipeline 内に閉じ、保存パス（`TranscriptStore` → `TranscriptSink`）には触れない**（経路分離の固定要件）。
- **機能C のピンは presentation 内のみで完結**し、domain・infrastructure には波及しない。

影響範囲の観点（変更時に確認すべき対象）:
- **音声取得方式（ADR-1 で確定）** は `ProcessTapAudioSource` と、それが要求する **TCC 権限**、
  および `AudioCapturePermission` の実装に影響する。domain（`TranscriptionService`）の interface は方式に依存させない。
- **SpeechAnalyzer の API 変更** は `SpeechAnalyzerAdapter` に閉じる。
- **翻訳エンジンの仕様変更**（macOS 26 での `TranslationSession` API 名称・サポート言語ペア・言語パック未導入時の挙動等）は `AppleTranslator` に閉じる。`Translator` port シグネチャ（Foundation `Locale` のみ）は不変のため domain・presentation への波及なし。
- **言語検出ロジックの変更**（`NLLanguageRecognizer` の confidence しきい値・短文の扱い）は `AppleLanguageDetector` に閉じる。`LanguageDetector.detect` の戻り値 `Locale?` 契約（判定不能時 nil）は不変。
- **Downloads ファイル名規則の変更**（衝突時のサフィックス・タイムスタンプ書式・出力先パス）は `DownloadsSessionExporter` に閉じる。`SessionExporter.export` シグネチャ不変なら domain・presentation への波及なし。
- **停止後 UI フロー（複本書き出し → 表示クリア確認）の変更**は `StopFlowCoordinator`（presentation）に閉じる。`TranscriptionService.stop()` の API・状態遷移は不変。
- **表示パイプライン（言語検出 → 翻訳 → 表示）の変更**は `DisplayPipeline`（presentation）に閉じる。保存パス（`TranscriptStore` → `TranscriptSink`）には触れない（経路分離・固定要件）。
- **ピン UI の振る舞い変更**は `TranscriptWindowController`（presentation）に閉じる。domain・infrastructure・既存 ADR への波及なし。

### Port セマンティクス（契約）

port のシグネチャは変えずに、**`TranscriptSink` の意味（契約）を明確化**する。
これは ADR-4（確定結果は即時ファイル追記でクラッシュ耐性を確保する）に対応する。

- **`TranscriptSink.append(_:)`**: 「**確定セグメントを durably に永続化する**」操作と定義する。
  受信したその時点で、後続の flush を待たずに**永続ストレージ（ファイル）に反映**しなければならない。
  メモリバッファに溜めて停止時にまとめて書き出す実装は**禁止**する（クラッシュ耐性を満たさないため）。
- **`TranscriptSink.flush()`**: 「**保留中の書き出しを確実に完了させる安全網**」と定義する。
  即時 append 実装では実質 no-op に近くてよいが、**契約としては残す**
  （domain の停止フロー「finalize → drain → flush」が壊れないようにする）。
- これにより、停止時の flush に依存せずクラッシュ耐性が得られる。
  影響は infrastructure 側の `FileTranscriptSink` 実装のみであり、`TranscriptSink` protocol のシグネチャは変わらない
  （既存 domain テスト22件は壊れない想定）。

### 新規 port のセマンティクス（機能A/B 向け契約）

ADR-5 / ADR-6 で確定したシグネチャと契約を以下にまとめる。

- **`Translator.translate(_ text: String, from source: Locale, to target: Locale) async throws -> String`（機能B / ADR-5）**:
  「原文 text を **オンデバイスで** sourceLocale から targetLocale へ翻訳する」操作。
  - **外部送信禁止**: 実装は外部ネットワークに音声・テキストを送信してはならない（固定要件）。
  - **不可時の throw 契約**: 翻訳パック未インストール / 利用不可な場合は明確な error を throw する（黙って空文字列・原文返却にしない）。呼び出し側（`DisplayPipeline`）が「原文フォールバック + ユーザー通知」を判断する。
- **`Translator.ensureAvailable(for source: Locale) async throws`（機能B / ADR-5）**:
  「指定言語の翻訳が利用可能か（必要なら言語パックダウンロード許諾を促す）」操作。
  - **呼び出しタイミング**: 起動時ではなく**初回検出時**（`LanguageDetector` で日本語以外が検出された最初の機会）に呼ぶ。複数言語の事前一括ダウンロードを強制しないため。
  - **不可時 throw**: 言語非対応・ダウンロード未許諾・ネットワーク不可で throw する。
- **`LanguageDetector.detect(_ text: String) -> Locale?`（機能B / ADR-5）**:
  「テキストの言語を判定する」操作。同期で OK。
  - **判定不能時は `nil` を返す**（例: 空文字列・極端に短い文字列・低 confidence）。呼び出し側は「日本語ではない」とは扱わず、原文表示にフォールバックして良い。
  - **OS 型を漏らさない**: `NLLanguageRecognizer` / `NLLanguage` は port シグネチャに出さず、`Locale`（Foundation）を返す。
- **`SessionExporter.export(_ session: TranscriptSession) async throws -> URL`（機能A / ADR-6）**:
  「セッション分の確定テキスト列を、独立した 1 ファイルとして書き出す」操作。
  - **入力**: `TranscriptSession { segments: [TranscriptSegment], startedAt: Date, stoppedAt: Date }`（domain 値型、Foundation のみ）。
  - **戻り値**: 書き出した先の URL（UI 提示・後続検証に使う）。
  - **保存内容は原文のみ**（機能B の翻訳結果を含めない）。固定要件「画面表示と永続保存の経路分離」をここでも担保する。
  - **既存 `transcript.txt` の append 経路には触れない**（停止フローの主経路 finalize → drain → flush は維持。Exporter は副経路）。
  - **失敗時の意味**: error を throw する。停止フロー全体は巻き戻さず、呼び出し側（`StopFlowCoordinator`）が「メイン保存は完了済み」を前提にユーザー通知する。
  - **ファイル名**: `~/Downloads/speech-tap-YYYYMMDD-HHmmss[-N].txt`（`stoppedAt` ベース、ローカルタイム、24 時間表記、衝突時は `-2`, `-3`, ... のサフィックス、上書き禁止）。

> いずれの port も OS 型（`Translation.Session` / `TranslationSession` / `NLLanguageRecognizer` / `NLLanguage` / `FileHandle` 等）を引数・戻り値・throw 型に出さない。
> domain は Foundation の純粋型のみで意味を扱う（固定要件「domain は OS/UI 非依存」）。

---
<!-- 以下は後続エージェントが追記するセクション -->

## アーキテクチャ設計

### 0. 設計サマリ（結論）

- **音声取得方式 = Core Audio Process Tap（候補A）を採用**（ADR-1）。最重要本質「対象アプリ音声の非混入」をプロセス単位タップで満たし、かつ画面収録権限が不要で常駐アプリの UX が良いため。
- **3層一方向依存（presentation → domain → infrastructure）を厳守**。domain は OS API / UI に一切依存せず、protocol（`AudioSource` / `SpeechRecognizer` / `AppEnumerator` / `PermissionGate`）にのみ依存する。
- **Composition Root はアプリ起動部（presentation 層の `AppDelegate` / `@main` 相当）に 1 箇所だけ置く**。ここで具体 Adapter を生成し domain に注入する。
- **音声→文字化はストリーミング**。Process Tap の PCM を `bestAvailableAudioFormat` へ変換し、`AsyncStream<AnalyzerInput>` で SpeechAnalyzer に供給。途中経過（volatile）と確定結果（finalized）を区別し、確定結果は取りこぼさず保存する。
- **確定結果は即時 append で永続化**（ADR-4）。クラッシュ時にも確定済み分が失われない。
- **翻訳はオンデバイス + 表示と保存の経路分離**（ADR-5）。Apple Translation framework を採用し、`DisplayPipeline`（presentation）で原文 → 言語検出 → 必要なら翻訳 → 表示する。**保存パス（`TranscriptSink`）には常に原文**を渡し、メインファイル `transcript.txt` も Downloads セッション複本も原文のみが残る。
- **セッション境界 = 開始操作から停止操作まで**（ADR-6）。停止のたびに `StopFlowCoordinator`（presentation）が `~/Downloads/speech-tap-YYYYMMDD-HHmmss[-N].txt` として独立ファイルを書き出す（メインファイル append 経路には触れない / 非破壊）。
- **機能C（ピン）は presentation のみで完結**し、永続化しない（再起動ごとに OFF）。

---

### 1. コンポーネント構成（精緻化版）

ディレクトリ構成（Swift Package / Xcode target いずれでも層を物理分離する）:

```
Sources/
  presentation/ (= SpeechTapApp)      ← UI・入出力のみ。ロジックを持たない
    MenuBarApp / AppDelegate              （@main 相当。= Composition Root）
    MenuBarController                     （メニューバー常駐・メニュー構築）
    TranscriptWindowController            （文字起こし表示 + ピン（機能C: NSTitlebarAccessoryViewController））
    DisplayPipeline（新規・機能B / ADR-5）（原文 → LanguageDetector → 必要なら Translator → 表示用文字列）
    StopFlowCoordinator（新規・機能A / ADR-6）（`.stopped` 検知 → SessionExporter.export → 表示クリア確認ダイアログ → clearDisplay）
    PermissionPromptView                  （権限案内 UI）
  domain/ (= SpeechTapDomain) ← 純粋ロジック。OS API / UI を import しない
    TranscriptionService  （ユースケース調整: 開始・停止・状態遷移。`startedAt: Date?` を内部保持）
    TranscriptStore        （文字起こし結果の集約・保持。`snapshotCurrentSession(...)` / `clearDisplay()` を追加）
    SessionState           （状態: idle / awaitingPermission / running / stopped / error）
    model/                 （TargetApp, TranscriptSegment, RecognitionResult, AppId, TranscriptSession（新規） 等の値型）
    ports/                 ← protocol（抽象 = 境界）。実装は infra 側
      AudioSource
      SpeechRecognizer
      AppEnumerator
      PermissionGate
      TranscriptSink         （確定結果の出力先。保存の抽象）
      EventLogger             （観測点の抽象）
      Translator（新規・機能B / ADR-5）           （オンデバイス翻訳の抽象）
      LanguageDetector（新規・機能B / ADR-5）    （言語検出の抽象）
      SessionExporter（新規・機能A / ADR-6）     （セッション複本書き出しの抽象）
      Config                 （任意: 設定の抽象）
  infrastructure/ (= SpeechTapInfrastructure)  ← OS API への接触のみ。domain の port を実装
    ProcessTapAudioSource     （AudioSource 実装: Core Audio Process Tap）
    SpeechAnalyzerAdapter     （SpeechRecognizer 実装: Apple SpeechAnalyzer）
    RunningAppProvider        （AppEnumerator 実装: NSWorkspace / Core Audio process list）
    AudioCapturePermission    （PermissionGate 実装: NSAudioCaptureUsageDescription / TCC）
    FileTranscriptSink        （TranscriptSink 実装: ファイル保存。ADR-3/4）
    ConfigLoader              （Config 実装: config.conf 読み込み）
    AudioFormatConverter      （AVAudioConverter による PCM → analyzer format 変換）
    OSEventLogger             （EventLogger 実装: os.Logger ラッパ）
    AppleTranslator（新規・機能B / ADR-5）        （Translator 実装: Apple Translation framework / TranslationSession）
    AppleLanguageDetector（新規・機能B / ADR-5） （LanguageDetector 実装: NLLanguageRecognizer）
    DownloadsSessionExporter（新規・機能A / ADR-6）（SessionExporter 実装: ~/Downloads にタイムスタンプ付きファイル）
```

> 旧「`AudioTapAdapter`」は採用方式確定により **`ProcessTapAudioSource`** に具体化した（ScreenCaptureKit 実装は作らない）。
> 機能A/B/C 追加に伴う新規コンポーネントは、いずれも presentation または infrastructure に閉じ、`TranscriptionService` のコンストラクタ・既存 port シグネチャを変更しない（既存テスト 22 件を維持する設計）。

---

### 2. レイヤーと依存関係（一方向）

```
[presentation]  AppDelegate(=Composition Root)
       ├─ MenuBarController / TranscriptWindowController（ピン: NSWindow.level トグル / 機能C）
       ├─ DisplayPipeline（機能B: 原文 → 言語検出 → 必要なら翻訳 → 表示用文字列）
       └─ StopFlowCoordinator（機能A: .stopped 検知 → Downloads 複本書き出し → 表示クリア確認）
       │ 依存（domain の型・protocol・Service を使う）
       │ ※ DisplayPipeline は Translator / LanguageDetector port に依存（保存経路には触れない）
       │ ※ StopFlowCoordinator は SessionExporter port + TranscriptStore + TranscriptionService に依存
       ▼
[domain]        TranscriptionService ── TranscriptStore ── SessionState ── TranscriptSession（機能A）
       │  ports（抽象）にのみ依存:
       │    AudioSource / SpeechRecognizer / AppEnumerator / PermissionGate / TranscriptSink / EventLogger
       │    + Translator（機能B）/ LanguageDetector（機能B）/ SessionExporter（機能A）
       ▼  （port を実装するのは infrastructure。domain は具体実装を知らない＝逆依存なし）
[infrastructure]
       ProcessTapAudioSource ───▶ Core Audio Process Tap（AudioHardwareCreateProcessTap / CATapDescription / Aggregate Device）
       SpeechAnalyzerAdapter ───▶ Apple SpeechAnalyzer / SpeechTranscriber（macOS 26+）
       RunningAppProvider ──────▶ NSWorkspace / kAudioHardwarePropertyProcessObjectList
       AudioCapturePermission ──▶ TCC（音声キャプチャ / NSAudioCaptureUsageDescription）
       FileTranscriptSink ──────▶ ファイルシステム（メイン transcript.txt への即時 append / ADR-4）
       ConfigLoader ────────────▶ config.conf
       AudioFormatConverter ────▶ AVFoundation（AVAudioConverter）
       OSEventLogger ───────────▶ os.Logger / OSLog
       AppleTranslator ─────────▶ Apple Translation framework / TranslationSession（オンデバイス / ADR-5）
       AppleLanguageDetector ──▶ NaturalLanguage / NLLanguageRecognizer / NLLanguage（ADR-5）
       DownloadsSessionExporter ▶ FileManager（~/Downloads/speech-tap-YYYYMMDD-HHmmss[-N].txt / ADR-6）
```

依存関係の要点（機能A/B/C 追加後・確定）:
- **機能B（翻訳）の表示パスは `DisplayPipeline`（presentation）内に閉じる**。`TranscriptionService` には `Translator` / `LanguageDetector` を注入しない。保存パス（`TranscriptStore` → `TranscriptSink` → `FileTranscriptSink`）は原文のまま不変（経路分離・固定要件）。
- **機能A（Downloads 複本）は `StopFlowCoordinator`（presentation）が `.stopped` 遷移を検知して駆動**する。`TranscriptionService.stop()` の API・戻り値・状態遷移は不変（domain の停止フロー主経路を壊さない）。複本書き出しの失敗は presentation が通知するだけで、停止フロー全体を巻き戻さない。
- **機能C（ピン）は `TranscriptWindowController`（presentation）内のみで完結**。domain・infrastructure・既存 ADR への波及なし。永続化なし（`NSWindow.isRestorable = false`、`UserDefaults` 不使用）。

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
| `EventLogger` | 観測点の抽象（domain を OS 非依存のまま可観測化） | `func log(_ message: String)` / `func error(_ message: String)` |
| `Translator`（新規・機能B / ADR-5） | オンデバイス翻訳（表示パスのみ・保存には流さない） | `func translate(_ text: String, from source: Locale, to target: Locale) async throws -> String` / `func ensureAvailable(for source: Locale) async throws` |
| `LanguageDetector`（新規・機能B / ADR-5） | テキストの言語検出（判定不能時 nil） | `func detect(_ text: String) -> Locale?` |
| `SessionExporter`（新規・機能A / ADR-6） | セッション分の確定テキスト列を独立ファイルとして書き出す | `func export(_ session: TranscriptSession) async throws -> URL`（`TranscriptSession { segments: [TranscriptSegment], startedAt: Date, stoppedAt: Date }`） |
| `Config`（任意） | 設定値の供給 | `var targetAppId: AppId?` / `var locale: Locale` / `var outputPath: String` |

> `AudioFrame` / `AudioStreamFormat` は domain 中立の値型。infrastructure 側で AVAudioPCMBuffer ⇔ AudioFrame を相互変換し、OS 型を domain に漏らさない。
> `Translator` / `LanguageDetector` / `SessionExporter` も同様に Foundation の `Locale` / `Date` / `URL` のみを出し、`TranslationSession` / `NLLanguage` / `FileHandle` 等の OS 型を domain に漏らさない。

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

### 8. 影響範囲マップ（機能 A/B/C 追加に伴う影響）

ADR-5（翻訳・経路分離）・ADR-6（セッション境界・Downloads）・機能C（ピン）の追加で各層・コンポーネントが受ける影響を一覧化する。/tdd のテスト計画・/deploy の受け入れ条件の根拠となる。

| コンポーネント | 機能 | 変更前 | 変更後 | 対応方針 | 担当フェーズ |
|---|---|---|---|---|---|
| `Translator` port（domain） | B | 未存在 | protocol 新設（`translate(_:from:to:)` / `ensureAvailable(for:)`）。Foundation のみ | 追加必要 | /tdd, 実装 |
| `LanguageDetector` port（domain） | B | 未存在 | protocol 新設（`detect(_:) -> Locale?`）。Foundation のみ | 追加必要 | /tdd, 実装 |
| `SessionExporter` port（domain） | A | 未存在 | protocol 新設（`export(_:) async throws -> URL`）。`TranscriptSession` 値型を導入 | 追加必要 | /tdd, 実装 |
| `TranscriptSession` 値型（domain） | A | 未存在 | `{ segments, startedAt, stoppedAt }` を新設（Foundation のみ） | 追加必要 | /tdd, 実装 |
| `TranscriptStore`（domain） | A | finalized/volatile 分離管理 | `snapshotCurrentSession(startedAt:stoppedAt:) -> TranscriptSession` / `clearDisplay()` を追加。既存メソッド・フィールドは不変 | 追加必要（既存テスト 22 件は不変） | /tdd, 実装 |
| `TranscriptionService`（domain） | A | 状態遷移・stop フロー | `startedAt: Date?` を内部状態として保持。`start()` 成功時に記録。読み取り用ゲッタ `currentSessionTimes` を公開。`stop()` の API・状態遷移は不変 | 軽微追加（既存 22 テスト維持） | /tdd, 実装 |
| `TranscriptSink` / `FileTranscriptSink` | — | ADR-3/4 で確定 | **不変**（保存経路は壊さない。固定要件） | 変更不要 | — |
| `TranscriptionService.stop()` フロー | — | finalize → drain → flush → stopped | **不変**。Downloads 複本書き出しは presentation の `StopFlowCoordinator` が `.stopped` 遷移後に駆動 | 変更不要 | — |
| `AppleTranslator`（infrastructure） | B | 未存在 | `Translator` 実装。Apple Translation framework / `TranslationSession` を内部に保持 | 追加必要 | /tdd（薄いアダプタ）, 実装, 実機検証 |
| `AppleLanguageDetector`（infrastructure） | B | 未存在 | `LanguageDetector` 実装。`NLLanguageRecognizer` を使用 | 追加必要 | /tdd（薄いアダプタ）, 実装 |
| `DownloadsSessionExporter`（infrastructure） | A | 未存在 | `SessionExporter` 実装。`~/Downloads/speech-tap-YYYYMMDD-HHmmss[-N].txt` 生成 | 追加必要 | /tdd, 実装 |
| `DisplayPipeline`（presentation） | B | 未存在 | 「原文 → `LanguageDetector` → 必要なら `Translator` → 表示」を組み立てる。保存経路には触れない | 追加必要 | 実装 |
| `StopFlowCoordinator`（presentation） | A | 未存在 | `.stopped` 遷移を検知して `SessionExporter.export` → 表示クリア確認ダイアログ → `clearDisplay()` を順に駆動 | 追加必要 | 実装 |
| `TranscriptWindowController`（presentation） | A/C | 表示のみ | `clear()` メソッド追加（A）。`isPinned: Bool` + `NSTitlebarAccessoryViewController` ピンボタン追加（C）。`window.level = .floating / .normal` をトグル | 変更必要 | 実装 |
| `AppDelegate`（Composition Root） | A/B/C | `TranscriptionService` を組み立て注入 | `AppleTranslator` / `AppleLanguageDetector` / `DisplayPipeline` / `DownloadsSessionExporter` / `StopFlowCoordinator` を追加生成・配線。`TranscriptionService` のコンストラクタは不変 | 変更必要 | 実装 |
| Info.plist / 署名 / entitlements | A/B/C | 音声キャプチャのみ | **不変**（翻訳・ピン・Downloads 書き出しは追加権限不要。Downloads はサンドボックス無効環境では制限なし） | 変更不要 | — |

### 9. Composition Root 注入順序（確定）

`AppDelegate.applicationDidFinishLaunching` で以下の順序に従って具体実装を生成・配線する。**`TranscriptionService` のコンストラクタは変更しない**（翻訳・エクスポートはサービス外で組み立てる）。

```
1. config の解決（既存）: ConfigLoader.load(...)
2. infrastructure Adapter 群の生成（既存 + 新規）:
   - audioSource:      ProcessTapAudioSource()                  （既存）
   - recognizer:       SpeechAnalyzerAdapter()                  （既存）
   - permissionGate:   AudioCapturePermission()                 （既存）
   - sink:             FileTranscriptSink(outputPath: cfg.outputPath)（既存・メイン経路）
   - eventLogger:      OSEventLogger()                          （既存）
   - translator:       AppleTranslator()                        （新規・ADR-5）
   - languageDetector: AppleLanguageDetector()                  （新規・ADR-5）
   - sessionExporter:  DownloadsSessionExporter()               （新規・ADR-6）
3. domain サービスの生成（既存・コンストラクタ不変）:
   - service: TranscriptionService(
       audioSource: audioSource,
       recognizer: recognizer,
       permissionGate: permissionGate,
       sink: sink,
       locale: cfg.locale,
       eventLogger: eventLogger
     )
4. presentation 構成要素の生成（新規）:
   - transcriptWindow:    TranscriptWindowController()                                （既存 + ピン対応）
   - displayPipeline:     DisplayPipeline(detector: languageDetector,
                                          translator: translator,
                                          targetLocale: Locale(identifier: "ja-JP"))   （新規・ADR-5）
   - stopFlowCoordinator: StopFlowCoordinator(exporter: sessionExporter,
                                              store: service.transcriptStore,
                                              service: service,
                                              window: transcriptWindow,
                                              presenter: self)                         （新規・ADR-6）
5. ハンドラ配線（既存 + 拡張）:
   - service.setStateChangeHandler { state in
       self.onStateChanged(state)                       // 既存
       stopFlowCoordinator.handleStateChange(state)     // 新規（.stopped で 複本書き出し → クリア確認）
     }
   - service.setTranscriptUpdateHandler {
       Task { @MainActor in
         let finalized = await displayPipeline.renderFinalized(service.transcriptStore.finalizedSegments)
         let volatileText = service.transcriptStore.volatileText   // volatile は原文表示
         transcriptWindow.update(finalized: finalized, volatile: volatileText)
       }
     }
6. メニュー UI の構築（既存）
```

**配線の要点**:
- `TranscriptionService` には翻訳・エクスポート関連の port を**注入しない**（翻訳は表示の関心事、エクスポートは UI フローの関心事のため、presentation に閉じる）。
- `DisplayPipeline` は `finalizedSegments`（原文）を受け取り、ロケール検出 → 必要なら翻訳して**表示用文字列**に変換する。**`TranscriptStore` の状態は書き換えない**（store は保存経路の真実値。表示変換は読み取り専用）。
- `StopFlowCoordinator` は `service.setStateChangeHandler` のクロージャから駆動される（既存通知 port を再利用するため、`TranscriptionService` の API を増やさない）。
- 翻訳パック未インストール時の状態行表示は `DisplayPipeline` が `Translator` の throw を捕捉し、`AppDelegate.latestStateText` を更新する経路で行う（既存の `presentPermissionGuidance` と同様、UI の関心事として presentation に閉じる）。

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

#### ADR-4: 確定結果は即時ファイル追記でクラッシュ耐性を確保する

**状況:**
実機検証で文字起こしの基本動作（タップ → SpeechAnalyzer → 表示・保存）が確認できた後、ユーザーから
「途中でアプリが落ちたときのことを考えると問題なので、ファイルもある程度の間隔で書き足していくような感じに
できませんか？ファイルは1つでいいんですけど、更新していくようなイメージ」と要望があった。
現状の `FileTranscriptSink` は `append()` をメモリバッファに溜め、停止時の `flush()` で初めてファイルに書き出す設計。
これは正常停止には強いが**クラッシュには弱く**、最重要本質の一つ「**確定結果を取りこぼさず保存**」
（受け入れ条件「確定した文字起こし結果が、設定された出力先に保存される」/ ADR-3）の延長として、
**クラッシュ時にも確定済み分が失われない**よう拡張すべきである。

**判断:**
**確定（finalized）結果ごとに `append` = 即時ファイル末尾追記する**設計に変更する。
出力ファイルは 1 つに維持し、新たな確定結果は末尾に追記する（停止のたびに新規ファイルを作らず、既存内容を上書きしない）。
domain の `TranscriptSink` protocol のシグネチャは変えず、**「append の意味（契約）」を「durable な即時永続化」と再定義**して
infrastructure の `FileTranscriptSink` 実装のみを差し替える。

**理由:**
- **取りこぼし防止の本質をクラッシュ時にも拡張**: 停止時 flush に依存していた現状は、文字化中のクラッシュで確定済みもすべて失う。
  毎 finalized の即時追記なら、クラッシュ時点までに確定した分は必ずファイルに残る。
- **文字レートが低く I/O は無視できる**: 文字化の確定結果は人間の発話速度に律速される（毎秒数語〜数十語オーダ）。
  ディスク I/O コストは現実の動作で無視できる。
- **1 セグメント = 1 書き込みで原子性が高い**: 短い書き込みは POSIX append の原子性を期待できる。
  途中状態の壊れた追記が残るリスクが小さい。
- **periodic タイマー（N 秒ごと書き出し）は不採用**: タイマー管理コストの割にデータロス窓が広がる。
  毎 finalized 即時追記の方が**データロス窓が最小**になる。

**検討した代替案と棄却理由:**
- **(a) 既存どおり停止時 flush（現状維持）**: クラッシュに弱い。確定済み分でもクラッシュで全消失。→ **棄却**。
- **(b) periodic N 秒タイマーでバッチ flush**: タイマー実装・キャンセル制御が増える割に、データロス窓が N 秒に広がる
  （毎 finalized より大きい）。→ **棄却**。
- **(c) 毎 finalized 即時追記**: 実装シンプル（FileHandle で末尾シーク → 書き込み、または追記モードで write）、
  データロス窓が最小。→ **採用**。

**トレードオフ・残るリスク:**
- 書き込み中の電源断など極稀なケース（POSIX append の原子性に依存）。
  SSD / HFS+ / APFS の通常運用では十分なロバスト性。本アプリのユースケース（会議録の保存）では許容範囲。
- 高頻度 finalized 環境（極端に高速な文字化）でのディスク I/O 集中。文字化レートでは現実的問題にならない想定。

**影響:**
- **`FileTranscriptSink.append` の実装が変わる**: メモリバッファを廃止し、直接ファイル末尾追記
  （FileHandle で末尾シーク → 書き込み、または追記モードで write）に変更する。
  親ディレクトリ未存在時の作成は維持する（既存の Should 対応）。
- **`FileTranscriptSink.flush` は安全網として簡素化**: 保留中があれば書き出す契約は維持しつつ、
  即時 append 実装では実質 no-op に近くなる（契約は壊さない）。
- **`TranscriptSink` protocol 自体のシグネチャは変わらない**。`append` の意味（契約）が
  「durable な即時永続化」に明確化される（「## システム構成 / Port セマンティクス」参照）。
- **既存 domain テスト 22 件は壊れない想定**（port シグネチャ不変・domain の停止フロー
  「finalize → drain → flush」も不変）。
- スレッド安全性は actor のシリアライズで維持する（`FileTranscriptSink` は actor）。

#### ADR-5: 翻訳エンジンに Apple Translation framework を採用し、画面表示と保存の経路を分離する

**状況:**
機能B（非日本語音声のリアルタイム日本語表示）を追加する。最重要本質「**オンデバイス完結（音声・テキストとも外部送信しない）**」を翻訳側にも拡張する必要があり、かつ「**保存対象は原文のみ**（画面表示と永続保存の経路分離）」「確定結果の取りこぼし防止（ADR-3/4）」「3層一方向依存・domain の OS/UI 非依存」を一切壊してはならない（固定要件）。対象 OS は macOS 26+。

**判断:**
- **翻訳エンジン**: **Apple Translation framework**（`Translation` モジュール、macOS 14+、macOS 26 で利用可）を採用する。infrastructure に `AppleTranslator`（`Translator` 実装）を置き、`TranslationSession` / `Configuration` / 言語パック利用可否確認 / 初回ダウンロード許諾を扱う。
- **言語自動検出**: `NLLanguageRecognizer`（NaturalLanguage）で `RecognitionResult.text` を分析し言語コードを得る。infrastructure に `AppleLanguageDetector`（`LanguageDetector` 実装）を置く。
- **port 境界（domain 中立 / OS 型を漏らさない / Foundation のみ）**:
  - `Translator.translate(_ text: String, from source: Locale, to target: Locale) async throws -> String`
  - `Translator.ensureAvailable(for source: Locale) async throws`（不可時は throw する）
  - `LanguageDetector.detect(_ text: String) -> Locale?`（同期で OK。判定不能時は `nil`）
- **画面表示パイプライン（presentation 内に新設 `DisplayPipeline`）**:
  ```
  RecognitionResult(text, isFinal)
    → LanguageDetector.detect(text) → Locale?
    → if Locale が ja でない（かつ判定不能ではない）: Translator.translate(text, from: Locale, to: ja-JP)
    → 表示用テキスト（日本語訳 or 原文）
  ```
- **保存経路は別**: `TranscriptSink.append(...)` には**常に原文**（`RecognitionResult.text`）を渡す（ADR-3/4 の経路と接続。`TranscriptionService` の保存経路は不変）。翻訳結果は `DisplayPipeline` 内のみに留め、`TranscriptStore` の `finalizedSegments` / `volatileText` にも漏らさない（保存経路を汚染しない）。
- **翻訳のタイミング（推奨・採用）**: **finalized のみ翻訳**。volatile は**原文をそのまま表示**（またはグレー表示）し、直近の finalized 訳との対応をユーザーに視認させる。理由:
  - Translation framework の `TranslationSession` 起動コストと体感遅延を考えると、volatile（毎フレーム上書きされる暫定）まで翻訳するのは過剰。
  - volatile は刻一刻と書き換わるため、翻訳結果の体感品質が低い（語順が変わる言語では悪化）。
  - finalized のみ翻訳すれば翻訳呼び出し回数は確定セグメント数に律速され、リアルタイム性とのバランスが取れる。
- **判定しきい値**: `LanguageDetector.detect(...)` が `nil` を返す（判定不能・極端に短い文字列）ケースは「日本語ではない」と扱わず**原文表示にフォールバック**する。低 confidence の扱いも同様（実装フェーズで NLLanguageRecognizer の confidence しきい値を実機検証で確定）。
- **翻訳パック未インストール / 言語非対応時のフォールバック**:
  - `Translator.ensureAvailable(for:)` を**初回検出時に呼ぶ**（起動時ではなく、対象言語が判明したタイミング。複数言語パックを事前に強制ダウンロードさせないため）。
  - 利用不可（throw）なら**原文表示にフォールバック**し、ユーザーに通知する（後述「未インストール時 UI」）。**黙って空表示・クラッシュにしない**（受け入れ条件）。
- **未インストール時 UI（確定）**: 二段階で行う。
  - (a) 初回検出時のダイアログ: 「この言語の翻訳パックをダウンロードしますか？」（Apple Translation framework の許諾フローを通る）。
  - (b) 利用不可・ダウンロード未許諾・ネットワーク不可で `ensureAvailable` が throw した場合: メニューバーの状態行（`AppDelegate.latestStateText`）に「翻訳: 利用不可（原文表示）」のように状態表示する（モーダル再表示は煩雑なので 1 回のみ）。これで「黙って空表示」は構造的に発生しない。
- **並行性（Swift 6 strict-concurrency=complete を維持）**: `AppleTranslator` は actor とし、`TranslationSession` を内部に保持して `translate` 呼び出しをシリアライズする（`TranslationSession` の Sendable 制約は実機検証で確定）。port のシグネチャは `async throws` で抽象に閉じる。

**理由:**
- **オンデバイス完結（固定要件）**: Apple Translation はオンデバイスで完結し、音声・テキストとも外部送信しない。固定要件「オンデバイス完結の翻訳側への拡張」を満たす唯一現実的な選択肢。
- **無料・標準・Apple 公式**: 追加ライセンス費・SDK 導入コスト・ベンダーリスクが無い。OS バージョンと一致した品質改善が期待できる。
- **スコープに過剰機能なし**: 単方向 / 1 言語ペア / リアルタイム翻訳という今のスコープに対し、API がぴったり合う。
- **経路分離の自然な実装**: `DisplayPipeline` を presentation に置けば、`TranscriptSink` 経路（domain）を一切触らずに表示パスだけを拡張できる。固定要件「**表示と保存の経路分離**」を構造的に担保。

**代替案（棄却理由）:**
- **Google Cloud Translation / DeepL / OpenAI 等のクラウド翻訳**: テキストを外部送信するため**固定要件「オンデバイス完結（翻訳側拡張）」に違反**。棄却。
- **自前 Core ML 翻訳モデル**: モデル選定・配布・更新・ライセンスのコストが過大。スコープ（リアルタイム表示・複数言語対応）に対し過剰投資。Apple Translation で十分。棄却。
- **`Translation` framework の `Configuration` を起動時に全言語分初期化**: ユーザーが使わない言語まで強制ダウンロードを促す UX 悪化。**初回検出時に必要言語のみ `ensureAvailable`** とする方が UX 良。棄却。
- **volatile も翻訳する**: 体感遅延・品質・API 呼び出し量がいずれも悪化（上記）。**finalized のみ翻訳**で十分。棄却。

**トレードオフ・残るリスク（実機検証で確定する事項）:**
- **macOS 26 での具体的 API 名称・サポートロケール一覧**は実機検証で確定する（決め打ちしない）。port シグネチャは Foundation の `Locale` で抽象化済みのため、API 名称が変わっても infrastructure に閉じる。
- **`TranslationSession` の Sendable / actor 制約**: 実機で確定。実装フェーズで `AppleTranslator` 内の concurrency 設計を最終化する。
- **言語パックダウンロード許諾の UX**: 初回検出時にダイアログが OS から表示される想定。出ない / 出方が不安定な場合は実装フェーズで `assetInstallationRequest` 相当の明示誘導を検討する。
- **NLLanguageRecognizer の confidence しきい値**: 短い発話・カタカナ・固有名詞で誤判定の可能性。低 confidence は「日本語ではない」と扱わず原文表示フォールバックする方針で安全側に倒す。具体しきい値は実機検証で確定。
- **finalized のみ翻訳 → volatile は原文のまま表示**: ユーザーから見ると確定時に「英文が日本語訳に置き換わる」遷移が見える。これは仕様であり、UI 上は volatile をグレー表示で「暫定（原文）」だと視覚的に区別する。

**影響:**
- domain に **`Translator` / `LanguageDetector` port**（protocol、Foundation のみ）を追加。`TranscriptionService` のシグネチャは変更しない（翻訳は presentation の `DisplayPipeline` に閉じるため、domain には注入しなくてよい）。
- presentation に **`DisplayPipeline`** を新設。`AppDelegate`（Composition Root）が `Translator` / `LanguageDetector` の具体実装を生成し、`DisplayPipeline` に渡す。`TranscriptionService` の `setTranscriptUpdateHandler` で受け取った更新通知を契機に、`TranscriptStore.finalizedSegments` / `volatileText` を `DisplayPipeline` に通して翻訳→`TranscriptWindowController.update(finalized:volatile:)` に流す。
- infrastructure に **`AppleTranslator`（`Translator` 実装）**・**`AppleLanguageDetector`（`LanguageDetector` 実装）** を追加。両 Adapter は OS 型（`TranslationSession` / `NLLanguageRecognizer` / `NLLanguage`）を内部に閉じ、port シグネチャには Foundation 型のみ出す。
- 既存 `TranscriptStore` / `TranscriptSink` / `FileTranscriptSink` は**シグネチャ・契約とも不変**。保存対象は原文のみのまま（ADR-3/4 の経路を破壊しない）。
- 既存 domain テスト 22 件は**壊さない想定**（domain port 追加のみ・既存 port のシグネチャは変えない・`TranscriptionService` のフローも変えない）。
- Composition Root（`AppDelegate`）の注入順序（後述「### Composition Root 注入順序（確定）」参照）に `AppleTranslator` / `AppleLanguageDetector` / `DisplayPipeline` を追加する。

#### ADR-6: セッション境界の定義と Downloads セッション複本エクスポート方針

**状況:**
機能A（停止操作のたびに、そのセッション分の確定テキストを Downloads に独立した `.txt` として書き出す）を追加する。固定要件として「メインファイル `transcript.txt` への append 経路（ADR-3/4）を**壊してはならない**」「複本側の失敗は停止フロー全体を巻き戻さない」「**保存内容は原文**（機能B の翻訳結果は含めない）」が課されている。さらに「セッション境界」「ファイル名規則」「データ構造」が未確定で、これらを ADR-6 で決定する必要がある。

**判断:**
- **セッション境界（確定）**: 「**開始操作（`TranscriptionService.start(app:)`）から停止操作（`TranscriptionService.stop()`）まで**」を 1 セッションとする。停止 → 次の開始までは別セッション。プロセス再起動を跨いだ場合も別セッション（再起動後の最初の `start` から新セッションを開始する）。これは現在の `generation`（停止のたびに加算される単調増加値）と意味的に一致する。
- **セッション中の確定テキストの蓄積方針（確定）**: `TranscriptStore` に「**現セッションの finalized 列**」を意味付ける。既存の `_finalized: [TranscriptSegment]` を**そのまま「現セッションの確定列」として再利用**し、停止時の `clearDisplay()`（後述）でクリアする。新たな別フィールド（`sessionFinalized`）は導入しない（既存 22 テストの構造を壊さないため・データ二重持ちを避けるため）。
  - メインファイル `transcript.txt` には ADR-4 のとおり append され続け、停止しても触らない。
  - 一方、`TranscriptStore._finalized` は「現セッション分のみ」を表すように、停止フローの最後で `clearDisplay()` を呼ぶことでクリアする（次セッションは空から始まる）。
- **Downloads ファイル名規則（確定）**: `~/Downloads/speech-tap-YYYYMMDD-HHmmss.txt`（**停止時刻**ベース、**ローカルタイム**、`HH` は 24 時間表記）。秒精度の衝突時は `-2`, `-3`, ... のサフィックスを末尾（拡張子の直前）に付与して回避（例: `speech-tap-20260531-153045-2.txt`）。**上書きは禁止**。
- **ファイル内容（確定）**: そのセッションの finalized テキストを 1 セグメント = 1 行（末尾に `\n`）で結合（既存 `FileTranscriptSink.append` と同等の見え方）。原文のみ（機能B の翻訳結果は含めない）。
- **非破壊性（固定要件・確定）**: メイン `transcript.txt` への `append` 経路には**一切触れない**。Downloads 書き出しは停止フローの**末尾の副経路**として追加し、失敗しても巻き戻さない。
- **停止フロー（更新・確定）**:
  ```
  TranscriptionService.stop():
    既存:
      1. recognizer.finalize()
      2. drain（残り finalized の取り込み）
      3. generation を進める
      4. audioSource.stop()
      5. sink.flush()（メインファイルの安全網）
      6. transition(to: .stopped)

  presentation 側 StopFlowCoordinator が .stopped 遷移を検知して以下を順に実行:
    7. sessionExporter.export(session) → Downloads に新規ファイル作成
       - 失敗時: ユーザーに通知（モーダル or 状態行）。メインファイル保存は完了済みなので巻き戻さない。
    8. 「表示クリアしますか？」ダイアログ表示
       - Yes: store.clearDisplay() + TranscriptWindowController.clear()
       - No: 表示を残す（次セッション開始時はメインファイルに append 継続・表示には残骸が見える）。
       - どちらの場合も transcript.txt の内容には影響しない。
  ```
- **`SessionExporter` port のシグネチャ（確定・Foundation のみ）**:
  - `func export(_ session: TranscriptSession) async throws -> URL`（書き出した URL を返す。UI 提示・後続検証に使う）
  - `TranscriptSession` は domain 値型: `{ segments: [TranscriptSegment], startedAt: Date, stoppedAt: Date }`
  - `Date` の取得は `TranscriptionService` の内部状態で startedAt / stoppedAt を保持し、`TranscriptSession` を組み立てて返す。**`Clock` port は今回導入しない**（Foundation の `Date()` を `TranscriptionService` 内部で 1 箇所だけ呼ぶ方が単純で、テストは startedAt/stoppedAt を外部から検証可能。`Clock` 抽象化は過剰投資と判断）。
- **`TranscriptStore` への追加メソッド（確定・最小）**:
  - `func snapshotCurrentSession(startedAt: Date, stoppedAt: Date) -> TranscriptSession`（現セッションの finalized 列 + 時刻を値型で返す。store は不変のまま）
  - `func clearDisplay()`（`_finalized` と `_volatile` をクリアする。**`TranscriptSink` には触らない**。表示用バッファのクリアという意味）
- **表示クリア確認ダイアログの意味付け（確定）**: 「表示用バッファのクリア」のみ。**メインファイル `transcript.txt` は触らない**。次回 `start` 時、メインファイルには ADR-4 のとおり append が続く（既存内容は壊さない）。
- **`StopFlowCoordinator` の責務（確定）**: presentation 内に新設。`TranscriptionService.setStateChangeHandler` で `.stopped` 遷移を検知し、上記 7→8 を順に実行する。**domain には漏らさない**（停止後の UI フローは presentation の関心事のため）。
  - 注意: `TranscriptionService.stop()` 自体は 6 で完了する。`stop()` の戻り値や追加コールバックを増やさず、既存の状態遷移通知（`onStateChange`）のみで駆動する。これにより domain の API を翻訳/エクスポート機能の有無で揺らさない。

**理由:**
- **既存メイン経路（ADR-3/4）非破壊**: stop フロー 1–6 は既存どおりで、Downloads 書き出し（7）は presentation 側で `.stopped` 遷移後に行う。domain の `TranscriptionService.stop()` API は変更しない（戻り値も増やさない）。これにより既存 domain テスト 22 件は壊れない。
- **セッション境界 = 開始→停止の単純な定義**: 現実の使い方（会議の開始から終了までを 1 ファイル）に合致し、`generation` の意味とも一致する。プロセス再起動を跨ぐと別セッション扱いになる挙動は、メインファイル append が続くこととは独立で、ユーザーの「複本＝この回の議事録」という期待にも合う。
- **既存 `_finalized` を再利用**: 二重持ちすると整合性管理が増える。`_finalized` の意味を「現セッションの確定列」と再定義し、`clearDisplay()` で停止後にクリアするだけで実現できる（最小変更）。
- **ファイル名規則 `YYYYMMDD-HHmmss`**: 辞書順 = 時系列順になり、Finder で並べ替えやすい。秒精度の衝突は `-2`, `-3` で回避し、上書きは禁止（データロス防止）。
- **`Clock` port 不導入**: 時刻取得は 1 箇所（`TranscriptionService` の `start` / `stop`）に閉じ、`Date()` を直接呼ぶ。`TranscriptSession` の `startedAt`/`stoppedAt` は値として渡るのでテスト可能（fake で固定時刻を渡したくなる場合は将来 `Clock` 抽象を入れる余地は残る）。今回は YAGNI。
- **`StopFlowCoordinator` = presentation**: 「停止後の UI フロー（ダイアログ表示・ウィンドウクリア・エラー通知）」は UI の関心事であり、domain には不要。domain は `.stopped` を通知するだけで責務完了。

**代替案（棄却理由）:**
- **`TranscriptStore` に新フィールド `sessionFinalized` を別途持つ**: データ二重持ち・同期コスト・既存テストへの影響大。`_finalized` の意味を「現セッション」と再定義する方が安価。棄却。
- **`TranscriptionService.stop()` の戻り値に `TranscriptSession` を返す**: domain API が機能A のために揺れる。`.stopped` 状態通知 + `store.snapshotCurrentSession(...)` の 2 つで十分なので、API を増やさない。棄却。
- **メインファイル `transcript.txt` の最後の確定〜停止まで分を Downloads に切り出す**: メインファイルに ADR-4 で即時 append しているので、「セッション分の切り出し」を transcript.txt から行うには境界マーカーが必要で複雑化する。`TranscriptStore._finalized`（メモリ上の現セッション分）から書き出す方が単純。棄却。
- **停止のたびにメインファイルをローテーションする**: 受け入れ条件「出力ファイルは 1 つであり、新たな確定結果は末尾に追記される」に違反。棄却。
- **`Clock` port を導入する**: 時刻取得が 1 箇所のため過剰投資。将来必要になったら追加する。棄却（今回スコープ外）。
- **ファイル名に翻訳結果を反映する（例: 言語コード付き）**: 翻訳結果はファイルに保存しないという固定要件と、UX 上の複雑化のため棄却。

**トレードオフ・残るリスク:**
- **「表示クリアダイアログで No を選ぶと次セッションの volatile/finalized が前セッションの上に積まれる」**: 仕様上の挙動（メインファイルとの整合性を優先するため）。UI 上は次セッション開始時に視覚的な区切り（例: 区切り線・タイムスタンプ見出し）を入れることを実装フェーズで検討する。
- **Downloads 書き出しの失敗（容量不足・権限・パス無効）**: `StopFlowCoordinator` がモーダル or 状態行でユーザーに通知。メインファイルの保存（ADR-4）は既に完了しているため、データロスは発生しない。
- **秒精度衝突**: 通常は人間操作で連続停止が秒内に並ぶことは稀。`-2`, `-3` サフィックスで安全側に倒す。
- **長時間セッションでのメモリ使用量**: `TranscriptStore._finalized` がセッション中に増え続ける。文字化レート（人間の発話速度）では現実的問題にならない想定。極端な長時間運用が問題化したら、`TranscriptStore` 側でリングバッファ化等を将来検討。

**影響:**
- domain に **`SessionExporter` port**（protocol、`func export(_ session: TranscriptSession) async throws -> URL`）と **`TranscriptSession` 値型**（segments / startedAt / stoppedAt）を追加。
- `TranscriptStore` に `snapshotCurrentSession(startedAt:stoppedAt:) -> TranscriptSession` と `clearDisplay()` を追加（既存メソッド・既存フィールドは不変）。
- `TranscriptionService` に **`startedAt: Date?`** を内部状態として持ち、`start()` 成功時に `Date()` を記録、`stop()` 完了時に `stoppedAt` をスナップショットして `TranscriptSession` を作れるようにする。**`TranscriptionService.stop()` の API（async/throws/戻り値）は変更しない**。`store.snapshotCurrentSession(...)` を presentation が呼ぶときに使う `startedAt` / `stoppedAt` は、`TranscriptionService` のゲッタ（例: `var currentSessionTimes: (Date, Date)?`）で公開する（読み取り専用・OS 非依存）。
- presentation に **`StopFlowCoordinator`** を新設。`.stopped` 遷移を検知して `SessionExporter.export` → 表示クリア確認ダイアログ → `store.clearDisplay()` を順に実行する。
- infrastructure に **`DownloadsSessionExporter`（`SessionExporter` 実装）** を追加。`FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)` で `~/Downloads/` を解決し、`speech-tap-YYYYMMDD-HHmmss[-N].txt` を生成。内容書き込みは `Data.write(to:)` のシンプルな single write（セッション全体を 1 回で書き出す）。
- 既存 `FileTranscriptSink` / `TranscriptSink` / `TranscriptionService.stop()` フローは**不変**。
- Composition Root（`AppDelegate`）に `DownloadsSessionExporter` と `StopFlowCoordinator` を追加注入（後述「### Composition Root 注入順序（確定）」参照）。
- 既存 domain テスト 22 件は壊さない想定（既存 port シグネチャ不変・新規 port 追加 + 新規 store メソッド追加のみ）。新規 port / 新規 store メソッドは /tdd で fake テストを追加する。

#### ピン（機能C）の設計メモ（ADR には起こさない・小規模 presentation 変更）

機能Cは presentation のみで完結し、3層依存・domain・infrastructure・既存 ADR との緊張がないため、ADR ではなく実装メモとして方針を記録する。

- **配置**: `TranscriptWindowController` に閉じる（presentation のみ）。
- **状態**: `private var isPinned: Bool = false`。**永続化しない**（固定要件「機能C ピン非永続化」。`UserDefaults` / 設定ファイル / `NSWindow.isRestorable` 等を使わない）。
- **UI（採用方針）**: **`NSTitlebarAccessoryViewController`** でウィンドウのタイトルバー右側に **`NSButton(.checkbox)` または `NSButton(image: NSImage(systemSymbolName: "pin"...))`** を配置する。理由:
  - メニュー項目（`NSMenuItem` ⌘P）よりウィンドウ上で完結し、ピン中であることが**視覚的に区別**できる（ボタン押下状態 / SF Symbol の pin/pin.slash 切替）。
  - macOS 26 でも `NSTitlebarAccessoryViewController` は安定して動く API。
  - ⌘P のキーボードショートカットも合わせて提供（`button.keyEquivalent = "p"` / `keyEquivalentModifierMask = .command`）。
- **挙動**: トグル時に `window?.level = isPinned ? .floating : .normal` を切り替える。アプリ再起動時は OS が NSWindow の state を復元しない（`isRestorable = false` 既定）ため、自動的に OFF からスタート（永続化なしを構造的に担保）。
- **状態遷移図への影響なし**: domain の `SessionState` は変わらない。pin は完全に表示層の関心事。
- **テスト**: presentation の単体テストは現状無し（既存方針: UI は手動検証）。手動検証チェックリストに「ピンボタンの押下で最前面切替」「再起動で OFF に戻る」を追加する。

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
| **【実機バグ修正】analyzer の Int16 フォーマットへ変換しても破棄しない（音声フォーマット変換・ブロッカー）** | `48k/2ch/float32 → 16k/1ch/Int16 へ変換しても nil にならず frameLength>0`（AudioFormatConverterTests） | PASS |
| 同上（Float32 ターゲットも対応） | `Float32 ターゲットでも nil にならず変換できる` | PASS |
| 同上（48k→16k リサンプル成立） | `48k→16k のサンプルレート変換で出力フレーム数がおおよそ sampleRate 比になる` | PASS |
| **文字化中のリアルタイム表示更新（結果受信ごとに UI へ通知・presentation 検証に必要）** | `文字起こし結果を受信するたびに transcript 更新ハンドラが呼ばれる`（TranscriptionServiceTests） | PASS |
| **【ADR-4】append 即時にファイル末尾に永続化（クラッシュ耐性・flush を待たない）** | `append のたびにファイル末尾に内容が反映されている（flush を呼ばずに読める・ADR-4）` | PASS |
| **【ADR-4】複数 append の順序保持（取りこぼし・順序崩れ防止）** | `複数 append が順にファイル末尾に積まれる（順序保持・ADR-4）` | PASS |
| **【ADR-4】flush を呼ばない停止（クラッシュ模擬）でも確定済み分が残る** | `停止せず（flush を呼ばずに）読んでも内容が見える（クラッシュ模擬・ADR-4）` | PASS |
| **【ADR-4】親ディレクトリ未存在でも append 単独で作成して書ける（flush に依存しない）** | `親ディレクトリが無くても append 時点で作成して書ける（ADR-4・親ディレクトリ作成は append 側）` | PASS |
| **【機能A / ADR-6】TranscriptSession 値型（domain・Foundation のみ）** | `TranscriptSession 値型は segments / startedAt / stoppedAt を保持する（Foundation のみ）` | PASS |
| **【機能A / ADR-6】snapshotCurrentSession が現セッションの確定列＋時刻を返す（store は不変）** | `snapshotCurrentSession は現セッションの finalized 列と時刻を含む TranscriptSession を返す（store は不変）` | PASS |
| **【機能A / ADR-6】clearDisplay は表示用バッファをクリアする** | `clearDisplay は表示用バッファをクリアする（_finalized / _volatile 両方）` | PASS |
| **【機能A / ADR-6・固定要件】clearDisplay は TranscriptSink に一切触れない（メイン append 経路不変）** | `clearDisplay は TranscriptSink には何の操作も発行しない（保存経路を一切触らない・固定要件）` | PASS |
| **【機能A / ADR-6】currentSessionTimes は start→stop の境界時刻を返す（stop API 不変）** | `currentSessionTimes は start→stop の境界時刻を返す（機能A / ADR-6・stop の API 不変）` | PASS |
| **【機能A / ADR-6】Downloads セッション複本: タイムスタンプ付きファイル名 + 1セグメント=1行 UTF-8** | `セッション分の確定テキストを 1 セグメント = 1 行で UTF-8 書き出す（タイムスタンプ付きファイル名）` | PASS |
| **【機能A / ADR-6】秒精度衝突時の -2, -3 サフィックスで上書き禁止** | `秒精度の衝突時は -2, -3 のサフィックスで回避し既存ファイルを上書きしない` | PASS |
| **【機能A / ADR-6】空セッションでも空ファイルが作成される（上書き禁止は維持）** | `空セッション（segments 0 件）でも空ファイルが作成される（上書き禁止は維持）` | PASS |
| **【機能B / ADR-5】日本語の finalized は翻訳せず原文表示** | `finalized が日本語と検出されたら翻訳せず原文を表示する（日本語はそのまま）` | PASS |
| **【機能B / ADR-5】非日本語の finalized は Translator.translate で日本語訳に変換** | `finalized が非日本語（英語）と検出されたら Translator.translate で日本語訳を表示用テキストにする` | PASS |
| **【機能B / ADR-5】翻訳失敗時は原文フォールバック（黙って空表示にしない）** | `Translator.translate が throw したら原文にフォールバックする（黙って空表示にしない）` | PASS |
| **【機能B / ADR-5】LanguageDetector が判定不能（nil）でも原文フォールバック** | `LanguageDetector が判定不能（nil）なら原文表示にフォールバック（『日本語ではない』とは扱わない）` | PASS |
| **【機能B / ADR-5】volatile は翻訳しない（常に原文）** | `volatile は翻訳しない（常に原文をそのまま表示する・ADR-5）` | PASS |
| **【機能B / ADR-5・固定要件】TranscriptSink.append には常に原文（経路分離）** | `TranscriptSink.append には常に原文が渡る（DisplayPipeline は保存経路を一切触らない）` | PASS |

### テスト環境

- フレームワーク: Swift Testing（`import Testing`）
- 環境: 実機・OS API・権限なしで完結（fake port 注入のみ）。ConfigLoader / FileTranscriptSink テストは一時ディレクトリ（一部はホーム配下のユニーク一時ディレクトリ）にファイル生成→破棄。
- 実行コマンド: `swift test` / 警告ゼロ確認: `swift build -Xswiftc -strict-concurrency=complete`
- 結果: **44 tests / 9 suites すべて PASS**（macOS 26.5 / Swift 6.3.2）。`swift build -Xswiftc -strict-concurrency=complete` 警告ゼロ。`swift build -c release` 成功。
  - レビュー差し戻し対応で **+6 tests / +1 suite**（FileTranscriptSinkTests）を追加。Must-1（finalize 取りこぼし防止）・Should-2（start 直接検証）・Should-3（error 経路）・FileTranscriptSink 群を Red→Green で実装。
  - 実機ログで断定した不具合修正で **+4 tests / +1 suite**（AudioFormatConverterTests 3 件 + TranscriptionServiceTests 1 件）。音声フォーマット変換（Int16 対応）と表示のリアルタイム更新を Red→Green→Refactor で実装。
  - **ADR-4（クラッシュ耐性のための即時 append 化）対応で +4 tests**（FileTranscriptSinkTests に追加）。`FileTranscriptSink.append` のメモリバッファを廃止し、毎回ファイル末尾に追記する実装に変更。`flush()` は契約上残しつつ no-op 化。`TranscriptSink` protocol のシグネチャは不変（domain テスト 22 件全 PASS を維持）。
  - **機能A/B/C（ADR-5 / ADR-6）対応で +14 tests / +3 suites**（TranscriptSessionAndStoreTests 4 件・DisplayPipelineTests 6 件・DownloadsSessionExporterTests 3 件 + TranscriptionServiceTests 1 件）。新規 port（`Translator` / `LanguageDetector` / `SessionExporter`）追加と、TranscriptStore 拡張（`snapshotCurrentSession` / `clearDisplay`）、TranscriptionService 拡張（`currentSessionTimes`・stop API 不変）、`DisplayPipeline`（domain・OS 非依存）、`DownloadsSessionExporter`（infra）、`AppleTranslator` / `AppleLanguageDetector`（infra スケルトン）、`StopFlowCoordinator`（presentation）を Red→Green→Refactor で実装。**TranscriptionService.stop の API は不変・既存 30 テスト全 PASS 維持**。`AppleTranslator` の Apple Translation framework API は実機検証で確定する未確定事項のため throw（→ 原文フォールバック）に留めるスケルトン。

### カバー範囲

- **domain（TDD で厚く）**: 値型（`TranscriptSession` 追加）、port protocol（`Translator` / `LanguageDetector` / `SessionExporter` 追加）、`TranscriptStore`（volatile/finalized 分離 + `snapshotCurrentSession` / `clearDisplay` で **TranscriptSink を触らない**ことを Spy 検証）、`TranscriptionService`（全状態遷移・権限分岐・取りこぼし防止・**停止時 finalize→drain→flush**・停止後不追記・**認識ストリーム error 終端からの error 遷移** + `currentSessionTimes`：stop の API 不変）、**`DisplayPipeline`**（言語検出→必要時のみ翻訳→表示用テキスト・volatile は翻訳しない・翻訳失敗時原文フォールバック・**保存経路 TranscriptSink には触れない**）。
- **infrastructure（OS 非依存部のみテスト）**: `ConfigLoader`（設定外部化）、`FileTranscriptSink`（親ディレクトリ作成・追記・保存失敗のエラー伝播・`~` 展開）、`DownloadsSessionExporter`（タイムスタンプ付きファイル名生成・秒精度衝突時の `-2`/`-3` サフィックス・上書き禁止・1セグメント=1行 UTF-8）。
- **アーキテクチャ**: domain の OS/UI 非 import をソース走査でガード。逆依存はコンパイル時に不可能化（確認済み）。新規 port（`Translator` / `LanguageDetector` / `SessionExporter`）はいずれも Foundation のみで OS 型を漏らさず、ガードテストを引き続き PASS。

### 機能C（ピン）のテスト方針

- **GUI 直接テストは行わない**（SPEC「ピン（機能C）の設計メモ」と整合）。`TranscriptWindowController.togglePin` は AppKit `NSWindow` に依存し、テスト用に headless で `NSWindow` を作る価値が薄いため、手動検証で担保する。
- 手動検証チェックリスト（実機・/deploy で確認）:
  - [ ] ピンボタン押下でウィンドウが最前面（`window.level = .floating`）になる。
  - [ ] 再度押下で最前面状態が解除（`.normal`）される。
  - [ ] ボタンアイコン（`pin` / `pin.fill`）と `state`（`.on` / `.off`）でピン中が視覚的に区別できる。
  - [ ] アプリ再起動後は OFF で開始する（`isRestorable = false` / UserDefaults 不使用）。

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
`DownloadsSessionExporter` も OS 非依存に近く実装済み・テスト済み（タイムスタンプ生成・衝突回避・1セグメント=1行 UTF-8）。
`AppleLanguageDetector` は `NLLanguageRecognizer` を使用する薄いアダプタとして実装済み（confidence しきい値 0.5 を暫定値として実機検証で確定する）。
**`AppleTranslator` は macOS 26 の Translation framework 正式 API シグネチャが実機検証で確定するまでスケルトン**（`translate` / `ensureAvailable` を `TranslationError.notImplemented` で throw する。`DisplayPipeline` 側のフォールバック経路で原文表示にされる）。`#if canImport(Translation)` で Translation モジュールを import 可能だが、実 API 呼び出しは TODO コメントで方針を残してある。**クラウド送信を一切行わない実装方針** を当該ファイルのコメントで明示し、`URLSession` / ネットワーク API を一切 import していないことで構造的に担保する。
presentation の実 @main アプリ・メニューバー UI（ピンボタン含む）・`StopFlowCoordinator`・Composition Root 配線は実装済み（手動検証で `.app` バンドル化・署名は /deploy フェーズへ）。

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

### ADR-4 実装レビュー（2026-05-29, 対象 commit `3123b5e`）

#### 判定: 承認（Should 2 件 / Want 2 件。Must 無し）

> ADR-4 の目的「**文字化中のクラッシュ（プロセス死）時にも確定済み分が失われない**」は、現実装で達成されている。
> `swift test` **30 tests / 6 suites 全 PASS**、`swift build -Xswiftc -strict-concurrency=complete` 警告ゼロ、
> `swift build -c release` 成功を実機で再確認済み。SPEC.md の目的・本質・固定要件とのズレなし。
> 受け入れ条件「### クラッシュ耐性」3 項目（即時反映・予期せぬ終了でも確定分が残る・1 ファイル末尾追記）は実装・テストで担保済み。

#### 整合性チェック（SPEC の目的・本質との照合）

- **「対象アプリ音声の非混入」（最重要本質）**: 本変更は永続化層のみで、`ProcessTapAudioSource` / `CATapDescription(stereoMixdownOfProcesses:)` の構造的担保には影響なし。実機検証項目として正しく未確定扱いを維持。
- **「取りこぼし防止」を「クラッシュ時にも拡張」**: 即時 append により、ADR-3 の停止時 finalize→flush 経路はそのまま、クラッシュ時データロス窓が「停止 1 回分の蓄積」→「現在書き込み中の 1 セグメント以内」に縮小。本質の強化として正しい方向。
- **3層一方向依存**: `TranscriptSink` protocol シグネチャ不変。変更は infrastructure 内に閉じ、`SpyTranscriptSink` も含めて domain テスト 22 件は全 PASS。固定要件「domain は OS/UI 非依存」も `ArchitectureGuardTests` PASS で維持。
- **固定要件（SpeechAnalyzer 固定・設定外部化・TCC 音声キャプチャのみ・OS 非依存）**: 本変更はいずれにも触れていない（Foundation のみ使用）。

#### 重点観点ごとの所見

##### 1. クラッシュ耐性（fsync の必要性）

- **プロセス死（アプリのクラッシュ・強制終了）に対しては実装は安全**: `FileHandle.write(contentsOf:)` は `write(2)` 経路で、書き込み完了時点でカーネルページキャッシュに到達する。プロセスが死んでも OS が後続で必ずディスクへフラッシュするため、ユーザー要望「途中でアプリが落ちた時に確定結果を失わない」は満たされる。
- **電源断・カーネルパニックに対しては `fsync` していないため未保証**: SPEC「### Port セマンティクス」は「**durably に永続化**」と書いており、文字通り読むと永続化媒体（ディスク）への到達まで含む。しかし ADR-4 のトレードオフ節は「書き込み中の電源断など極稀なケース」「APFS の通常運用では十分なロバスト性」と明言しており、**今回の要望スコープ（アプリのクラッシュ）に対しては妥当な妥協点**。
- **所見**: SPEC の文言「durably」と実装の `write(2)` レベルの間に厳密には乖離がある。ただし ADR-4 トレードオフ節と本質（プロセス死耐性）から見れば許容範囲。`fsync` を呼ばないトレードオフは「会議録の数秒分の確定結果が稀な電源断で失われ得る」というレベルで、文字化レートでは現実的問題は小さい。**Want（後述）**: 強化したい場合は `flush()` で `F_FULLFSYNC` 相当（macOS では `fcntl(F_FULLFSYNC)`）を呼ぶ余地がある。`flush()` を完全 no-op にしておくと、後でディスク到達を保証したくなった時の自然な置き場所が失われるので、契約として残している現状の判断は妥当。

##### 2. FD リーク / リソース解放

- **問題なし**: `let handle = try FileHandle(forWritingTo: outputURL)` の直後に `defer { try? handle.close() }` が置かれており、その後の `seekToEnd` / `write(contentsOf:)` のいずれが throw しても `defer` が確実に発火する。`FileHandle(forWritingTo:)` 自体が throw した場合は handle が未生成なので close 不要。actor 並行性下でも、actor メソッド内の同期 throw に対し Swift の `defer` セマンティクスは保たれる。
- 初回 append 経路（`Data.write(to:)`）は `Data` 側がオープン〜クローズを内部完結するため FD 漏洩なし。

##### 3. エラー伝播 / 部分書き込み

- **`write(contentsOf:)` は全量書き終わるか throw するか**であり、戻り値による部分成功シグナルは持たない。Apple SDK の `_NSDataWritingContents` 系は内部で短書き込みをループするため、通常の通常時は気にしなくてよい。
- **ディスクフルなどで途中 throw した場合**: 既に進んだ書き込みオフセット分のバイトが部分的にファイル末尾に残り得る（行末改行が欠ける部分行）。次回の append は `seekToEnd` で再度末尾にシークするため**位置不整合は起きない**が、出力ファイル末尾に行末改行欠落の壊れた 1 行が残る可能性はある（Should-A、後述）。
- エラーは `try` で domain に伝播し、`TranscriptionService.handle()` で `failed()` 経路 → `.error` 状態遷移＋`audioSource.stop()` 解放につながる（既存テスト `recognitionStreamErrorGoesError` の保存失敗版と同じ仕組み）。

##### 4. 3層一方向依存の維持

- **不変・問題なし**: `TranscriptSink` の `func append(_:) async throws` / `func flush() async throws` は両方ともシグネチャ変わらず。意味（契約）の「durable な即時永続化」への強化は domain 側コードに影響しない。
- `SpyTranscriptSink`（domain テスト）も変更なしで動作。
- `ArchitectureGuardTests` PASS。

##### 5. テストの本質適合

- 新規 4 テストは ADR-4 受け入れ条件を網羅:
  - 即時反映（flush なしで読める）→ `appendIsImmediatelyPersisted`
  - 順序保持 → `multipleAppendsArePersistedInOrder`
  - クラッシュ模擬（flush を呼ばずに外部 read）→ `contentVisibleWithoutFlush`
  - 親ディレクトリ作成は append 側 → `appendCreatesParentDirectory`
- **クラッシュ耐性のテストとして「flush を呼ばずに同プロセス内で読む」で十分か**: 実プロセス kill ではないため厳密ではないが、契約「append 完了時点でファイルに反映」を検証するには適切。プロセス死後の状態は OS のページキャッシュ→ディスク同期の問題でアプリ側コードでは検証不能（実プロセス kill テストでも fsync しなければ同様）。テスト目的としては適切に絞り込まれている。
- **Should-B（後述）**: 空文字列 segment・改行を含む segment・既存ファイル末尾に改行が無い場合（外部編集後）の境界が未テスト。

##### 6. flush の取り扱い

- 現状 `flush()` は完全 no-op。`TranscriptionService.stop()` は flush を呼び、失敗時は `.error` に遷移する（黙殺しない）。**呼び出し側コードは契約として意味を持ち続ける**（将来の fsync 化や別 Sink 実装の余地）。名残のデッドコードではない。
- **Want-1（後述）**: 耐久性向上が必要なら `flush()` で fsync 相当（macOS なら `fcntl(F_FULLFSYNC)`）を呼ぶ拡張余地がある。現状の SPEC スコープでは不要。

##### 7. 改行・エンコーディング

- `Data((segment.text + "\n").utf8)` で UTF-8 出力。日本語含むテキストで問題なし。
- 旧 flush の `joined(separator: "\n") + "\n"` との見え方比較:
  - 旧: 各セグメント間に "\n"、末尾にも "\n"。
  - 新: 各 append が `text + "\n"` を末尾追記 → セグメント数 N で `text1\ntext2\n...textN\n` となり**等価**。
- **境界の懸念**（Should-B）:
  - **空文字列 segment**: 旧は `["", "x"]` を flush すると `"\nx\n"`、新は append 順次で `"\n"` + `"x\n"` = `"\nx\n"` → 等価。
  - **text に "\n" を含む segment**: 旧・新ともそのまま追記され改行が出力される。SpeechAnalyzer の finalized が複数行を含むかは現状不明。**保存対象は finalized のみ**で、SpeechAnalyzer の typical finalized は短い文節なので実害は薄いが、設計意図として 1 行 = 1 セグメントを期待するなら正規化 or 検証が欲しい（Want-2）。
  - **外部から末尾改行欠けの既存ファイル**を編集された場合: 新の追記は末尾シークするだけなので「前の行＋text\n」が結合されて 1 行になる可能性がある。実用上のリスクは低い。

##### 8. 回帰

- 既存 4 テスト（`createsParentDirectoryAndWrites` / `appendsAcrossFlushes` / `propagatesWriteError` / `expandsTilde`）は新実装で意味を保ち PASS（手元再実行で確認）。`appendsAcrossFlushes` は flush が no-op になった現在でも「複数回 append → 累積反映」を実質的に検証している（テスト名は flush の振る舞いを示唆するが、実体は累積追記のテストとして有効）。
- `propagatesWriteError` は出力先をディレクトリパスにすることで `FileHandle(forWritingTo:)` か `Data.write(to:)` のいずれかが throw する経路を確認。新実装でも有効。
- domain テスト 22 件全 PASS（`SpyTranscriptSink` 経由）。

##### 9. 命名・可読性・一貫性

- ドキュメンテーションコメントが SPEC・ADR-4 と一貫しており追従しやすい。
- 実装は十分に単純（FileHandle で seek→write、初回は Data.write）。文字化レートでの I/O コスト懸念は ADR-4 トレードオフで言及済み。
- 高頻度 append 時の最適化（FileHandle を actor 内で保持して使い回す）は採用していないが、現スコープでは過剰最適化と判断できる。本質（クラッシュ耐性）と実装単純性のトレードオフとして妥当。

#### 指摘事項

| 重要度 | 場所 | 内容 | 改善案 |
|---|---|---|---|
| Should-A | `FileTranscriptSink.append` | ディスクフル等で `write(contentsOf:)` が途中 throw した場合、改行を含む最終バイト群が部分書き込みで残り、出力ファイル末尾に「行末改行欠け」の壊れた行が残る可能性。次回 append との接続で行が結合されるリスクがある。確率は低いが、本質（取りこぼし防止）と緊張する。 | (a) 書き込み前にファイル末尾の最後の文字が `\n` でないことを検出した場合、次の append で先頭に `\n` を補う、または (b) 書き込み失敗時に末尾を切り詰める（`truncate(atOffset:)` で seek 前のサイズへ戻す）。最小限の対策として、書き込み失敗時にエラーログでバイト数の不整合可能性を残す。スコープを抑えるなら「現状は許容（ADR-4 トレードオフに含める）」と SPEC に明記しても可。 |
| Should-B | `Tests/.../FileTranscriptSinkTests.swift` | 新規テストは正常系のみで、境界（空文字列 segment / 改行を含む segment / 既存ファイル末尾に改行が無いケース）が未カバー。改行・エンコーディングの SPEC 適合（旧 flush の見え方と等価）を保証するための回帰テストが欠ける。 | (a) `append(TranscriptSegment(text: ""))` で `"\n"` が積まれることのテスト、(b) `append(TranscriptSegment(text: "ab\ncd"))` でそのまま追記されるテスト、(c) ファイル末尾が改行無しの既存ファイルへ append したときの見え方を明文化するテスト、を追加する。 |
| Want-1 | `FileTranscriptSink.flush` | 現状 no-op。SPEC「### Port セマンティクス」の「durably に永続化」を厳密に読むなら、`flush` で `fcntl(F_FULLFSYNC)`（macOS の完全永続化）相当を呼ぶ余地がある。電源断耐性まで欲しい場合の明確な拡張ポイント。 | append ごとに fcntl は I/O コストが大きいので flush 側に置く設計が自然。`stop()` が flush を呼ぶ既存フローを活かし、停止時にのみディスク同期を保証する。ADR-4 トレードオフの「電源断は許容」を覆すかは SPEC 判断。今回のスコープ（プロセス死耐性）では不要。 |
| Want-2 | `FileTranscriptSink.append` の改行扱い | finalized text に "\n" が含まれた場合、ファイル上で「1 セグメント = 複数行」になる。後段の解析（行数＝確定回数を仮定するツール等）と緊張する可能性。 | 必要なら append 時に text 内の "\n" を空白等に置換（`text.replacingOccurrences(of: "\n", with: " ")`）。スコープ外なら無視可。 |

#### 良い点

- ADR-4 の意図（クラッシュ耐性のためのメモリバッファ廃止・即時 append）が実装・コメント・テスト名に一貫して反映されており、後から読んでも設計意図が明確。
- `defer { try? handle.close() }` の配置が正しく、エラー経路でも FD リークしない。actor シリアライズで `seekToEnd → write` の競合も構造的に排除されている。
- 初回 append でディレクトリ作成を `append` 側に移したことで「flush に依存せず append 単独で書ける」契約を強制している。設計と実装が一致。
- `flush` を no-op として残し契約を壊さなかったことで、`TranscriptionService.stop()` の既存フロー（finalize → drain → flush + 失敗時 error 遷移）が無傷で済んでいる。port セマンティクスの明確化（実装変更 / シグネチャ不変）の好例。
- 既存テスト 4 件を新実装でも維持・有効化しており、回帰検出能力を落としていない。


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

### 次の /tdd タスク（ADR-4: クラッシュ耐性のための即時 append 化）

> **Resolved（2026-05-29, /tdd）**: ADR-4 を Red→Green→Refactor で実装完了。
> `swift test` **30 tests / 6 suites 全 PASS**、`swift build -Xswiftc -strict-concurrency=complete` 警告ゼロ、`swift build -c release` 成功を確認。
> 詳細は「## テスト計画」の ADR-4 関連 4 件と「テスト環境」末尾の追記参照。

**実装変更（実施済み）:**
- `FileTranscriptSink.append` を「即時ファイル末尾追記」に変更
  （初回 append でファイル作成 → 以降 `FileHandle(forWritingTo:)` で `seekToEnd` → `write(contentsOf:)`。
  `Data.write(to:options:.atomic)` のような上書き系は使用しない）。
- メモリバッファ（`buffer: [String]`）を廃止。
- 親ディレクトリ未存在時の作成は **append 側**で行うように移動
  （flush に頼らず append 単独で書ける必要があるため）。
- `flush()` は no-op（契約として残す。即時 append のため保留中は存在しない）。
- スレッド安全性は actor のシリアライズで維持。

**追加したテスト（Red → Green）:**
- `append のたびにファイル末尾に内容が反映されている（flush を呼ばずに読める・ADR-4）` — PASS
- `複数 append が順にファイル末尾に積まれる（順序保持・ADR-4）` — PASS
- `停止せず（flush を呼ばずに）読んでも内容が見える（クラッシュ模擬・ADR-4）` — PASS
- `親ディレクトリが無くても append 時点で作成して書ける（ADR-4・親ディレクトリ作成は append 側）` — PASS
- 既存の 4 件（親ディレクトリ作成 / flush 跨ぎ追記 / 書き込みエラー伝播 / `~` 展開）も維持・PASS。

**回帰確認:**
- `TranscriptSink` protocol のシグネチャ不変。domain テスト 22 件全 PASS を維持（合計 30 = 22 domain + 4 infra 既存 + 4 新規 + その他）。
- `swift build -Xswiftc -strict-concurrency=complete` 警告ゼロ維持。

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

## オブザーバビリティ設計
<!-- /observe が追記 -->

### 背景・目的（解決する品質問題）

実機検証で「状態は **running（文字化中）** になる（＝権限許可・タップ生成・Aggregate Device 生成・
`AudioDeviceStart`・SpeechAnalyzer 開始・モデル導入・`bestAvailableAudioFormat` 取得まで成功）」のに
**認識結果が 1 件も出ない**。ブラウザでも単一プロセスアプリ（ミュージック等）でも同様に空。
現状コードにログが一切無く、**音声フレームがパイプラインのどこまで流れ、どこで消えるかが追跡不能**だった
（＝可観測性の欠如という品質問題）。

本フェーズは黒箱を可観測にするための**構造化ログ（os.Logger）を実装**する。原因の修正は次フェーズ（/tdd）。
モニタリング（既知の閾値監視）ではなく、未知の不具合を**調査**できるようにするオブザーバビリティの実装である。

### ログ基盤（subsystem / category）

- **subsystem 統一**: `com.example.speech-tap`（`AppLog.subsystem`）。`log stream --predicate 'subsystem == "..."'` で一括観測する。
- **category で観測点を分離**（`AppLog.Category`）:

| category | 観測点 | 主に判定する仮説 |
|---|---|---|
| `tap` | Process Tap 構成・起動（PID 解決 / `processObjectID` / tap native ASBD 全フィールド / aggregateID / `AudioDeviceStart` / stop サマリ） | A（IOProc 未呼び出し）・B（フォーマット） |
| `ioproc` | IOProc コールバック（`mNumberBuffers` / 先頭バッファの `mNumberChannels`・`mDataByteSize` / 算出 floatCount / 宣言 format）。最初の 3 回のみ出力 | A・B |
| `analyzer` | SpeechAnalyzer 供給・結果受信（`analyzerFormat` / アセット導入有無 / feeder received・converted・dropped / results volatile・finalized） | C（変換 nil drop）・D（results 出ない） |
| `converter` | フォーマット変換のフォールバック発生（AVAudioConverter 経路失敗。入力/target format 付き、最初の 3 回のみ） | B・C |
| `app` | domain の状態遷移・権限分岐・認識結果受信件数・error/保存失敗（`EventLogger` port 経由） | 状態の全体追跡 |

### 3層一方向依存の維持（domain を OS 非依存のまま可観測化）

固定要件「domain は OS API（os.Logger/OSLog）を import しない」を守るため、**port + 注入**で観測する:

- domain 側に薄い `EventLogger` protocol（`Sources/SpeechTapDomain/ports/EventLogger.swift`）を定義。Foundation のみ依存。既定実装は no-op の `NullEventLogger`。
- 実体（os.Logger ラッパ）は infrastructure の `OSEventLogger`（`Sources/SpeechTapInfrastructure/OSEventLogger.swift`）に置き、**Composition Root（`AppDelegate`）でのみ注入**する。
- これにより `TranscriptionService` は OS を import せず可観測になり、`ArchitectureGuardTests`（domain の禁止 import 走査）も維持される（**`swift test` 22 tests / 5 suites 全 PASS**、`swift build -Xswiftc -strict-concurrency=complete` 警告ゼロを確認済み）。

### リアルタイム安全性の配慮（IOProc）

IOProc はリアルタイムスレッドであり、確保・ロック・ブロッキングを増やさないことが固定要件。

- 呼び出し回数・yield フレーム数は `Synchronization.Atomic<Int>` で**ロックフリーに加算**するのみ。
- `Logger` 呼び出しは**最初の 3 回だけ**に間引く（`callIndex <= 3`）。総量は `stop()` 時に 1 回だけサマリ出力する。
- `Logger` は Sendable な値型のため、IOProc ブロックには `self` を捕捉せず**値コピー**で渡す。
- feeder/results ループは非リアルタイムタスクのため、件数は atomic / ローカル変数で集計し、先頭数件 + 区切り（20 件毎）で間引きログする。

### ログ収集 runbook（実機での観測手順）

事前準備: 音声を出すアプリ（ブラウザで動画再生 or ミュージック）を 1 つ。

1. **ログをストリーム表示**（別ターミナル。アプリ起動前に開始しておく）:
   ```
   log stream --predicate 'subsystem == "com.example.speech-tap"' --info --debug
   ```
   - 特定 category だけ見たい場合: `--predicate 'subsystem == "com.example.speech-tap" && category == "ioproc"'`
2. **アプリを起動**（stderr も見たい場合はバイナリ直起動）:
   ```
   open build/SpeechTap.app
   # もしくは stderr も見る:
   build/SpeechTap.app/Contents/MacOS/SpeechTapApp
   ```
3. メニューから**対象アプリを選択**。
4. **「文字化を開始」** → 権限許可 → 対象アプリで**音声を再生**。
5. しばらく流したら**「文字化を停止」**（`tap` の stop サマリ・`analyzer` の feeder/results サマリが出る）。
6. ストリームに出たログを下表（仮説対応表）で判定する。
7. 過去ログを後から見る場合: `log show --predicate 'subsystem == "com.example.speech-tap"' --info --debug --last 10m`

### 仮説 → ログ判定対応表

「結果ゼロ」の原因を、どのログ行で切り分けるかの対応表。

| 仮説 | 内容 | 判定するログ（category: 行） | 判定基準 |
|---|---|---|---|
| **A** | IOProc が一度も呼ばれない（タップが無音） | `tap`: `stop summary: ioProcCalls=... yieldedFrames=...` / `ioproc`: `IOProc call #1..3` | `ioProcCalls=0`（call ログも出ない）なら A 確定。タップ自体は成功でも音が来ていない |
| **B** | IOProc は呼ばれるがフォーマット解釈が誤り | `tap`: `tap native ASBD: ...`（isFloat/isNonInterleaved/channelsPerFrame/bytesPerFrame）/ `ioproc`: `mNumberBuffers=... first.mNumberChannels=... first.mDataByteSize=... computedFloatCount=... declaredFormat.channels=...` | `mNumberBuffers>1`（非インターリーブ）なのに先頭バッファのみ読む / `isFloat=false` / `declaredFormat.channels` と `first.mNumberChannels` の不整合があれば B（後述「未解決事項」も参照） |
| **C** | 変換が nil を返し全フレームが黙って捨てられる | `analyzer`: `feeder DROPPED frame #...（pcmBuffer==nil）` / `feeder summary: received=... converted=... dropped=...` / `converter`: `convert FALLBACK #...` | `dropped > 0` かつ `converted == 0` なら C 確定。`converter` の FALLBACK 連発も変換経路破綻の兆候 |
| **D** | バッファは渡るが results が出ない | `analyzer`: `analyzerFormat: ...` / `feeder summary: ...converted=N(>0)` / `results stream ended: volatile=... finalized=...` | `converted>0` なのに `results ... volatile=0 finalized=0` なら D（analyzerFormat 不一致・無音入力・モデル等）。`asset installation` ログでモデル導入状態も確認 |

> 補助: `app` category の `recognition result ...` / `stop requested; received so far volatile=... finalized=...` で
> **domain まで結果が届いているか**を確認できる（infra の `results stream ended` と domain の受信件数が一致するか）。

### ログ実装中に気づいた疑わしいバグ（未解決事項・修正は /tdd 判断）

> **【解決 / Resolved 2026-05-28 by /tdd】実機＋ライブログで根本原因を断定し修正した。**
> ライブログの実測値: タップ native = **48kHz/2ch/float32/インターリーブ**（mNumberBuffers=1・先頭バッファに 2ch インターリーブ 1024 floats=512 frames）。
> analyzerFormat（`bestAvailableAudioFormat`）= **Int16 / 16kHz / モノ**（commonFormat=3）。
> feeder summary は `received=8764 converted=0 dropped=8764`（全フレーム破棄）、results は volatile=0/finalized=0。
>
> **真の根本原因（仮説 B/C ではなく Int16 フォーマット非対応）:** 旧 `AudioFormatConverter.pcmBuffer(from:format:)` が `floatChannelData` を使うため、
> analyzer の **Int16 フォーマットのバッファでは `floatChannelData` が必ず nil** を返し、`SpeechAnalyzerAdapter.makeStream` で毎フレーム `pcmBuffer==nil` → 全破棄 → 認識結果ゼロになっていた。
> 加えて「float32 の AudioFrame に一旦変換 → それを Int16 バッファに floatChannelData で詰める」という二重変換の設計ミスがあった。
>
> **修正:** `AudioFormatConverter.convertBuffer(_:to:)` を追加し、**出力バッファを analyzerFormat（Int16 等）で確保**して `AVAudioConverter` に任せる（floatChannelData 前提を撤廃）。
> `SpeechAnalyzerAdapter` はタップ native の AVAudioPCMBuffer を作り、それを `analyzerFormat` へ一段変換して `AnalyzerInput` に渡すよう変更。
> 旧 `convert(_ frame:to:)`・`audioFrame(from:)`・`streamFormat`・フォールバック計数（下記 3）は二重変換の名残なので削除した。
>
> 下記の当時の仮説（実機確認前）は記録として残す:
>
> - **仮説 B（実測で否定）**: タップ native は float32・interleaved だった（int / 別レイアウトではなかった）。IOProc の Float 読みは正しかった。
> - **仮説 B+C（実測で否定）**: 非インターリーブ stereo によるチャンネル取りこぼしは発生していなかった（実機はインターリーブ 1 バッファ）。
> - したがって下記 1〜2 の懸念は **本実機環境では発生せず**、3 のフォールバックは削除済み。

1. **【最有力 / 仮説 B+C】非インターリーブ stereo でのチャンネル取りこぼし + フォーマット矛盾。**
   - `ProcessTapAudioSource` の IOProc は `ablPointer.first`（先頭バッファ）**のみ**を読み、
     `floatCount = first.mDataByteSize / sizeof(Float)` を全サンプルとして `AudioFrame` を作る
     （`ProcessTapAudioSource.swift` の IOProc 内）。
   - しかし `AudioFrame.format` には tap native の `channelCount`（stereo なら 2）を付与する。
   - **非インターリーブ stereo なら ABL は 2 バッファ（チャンネル毎）**で、先頭バッファには 1ch 分の N サンプルしか無い。
     よって「N サンプルしか無いのに format は 2ch」という**サンプル数とフォーマットの矛盾**が生じる。
   - これが下流の `AudioFormatConverter.pcmBuffer` に波及する: `frameCapacity = samples.count / channels = N/2`、
     さらに非インターリーブ分配で `samples[i*channels + ch]` と**インターリーブ前提のインデックス**で読むため、
     1ch の連続データを stereo として誤って分配する（音が壊れる・半分になる）。
   - **対応方針案（/tdd）**: IOProc で ABL の全バッファ（全チャンネル）を読む、または「先頭バッファ 1ch のみ採用し format も 1ch（mono）に揃える」のどちらかに統一し、IOProc が作る samples 数と `AudioFrame.format.channelCount` を**必ず整合**させる。`pcmBuffer` の非インターリーブ分配ロジックも samples レイアウト定義に合わせて見直す。
2. **【仮説 B】tap native format が float / interleaved である保証が無い。**
   - 現コードは IOProc で無条件に `mData` を `Float` として読む。tap native が int / 別レイアウトなら誤読する。
   - → `tap native ASBD` ログ（`isFloat` / `bitsPerChannel` / `formatID`）で実値を確認してから /tdd で対処。
3. **（軽微）`AudioFormatConverter.convert` のフォールバックが変換失敗を黙ってパススルーする。**
   - walking skeleton 用フォールバックだが、実機で AVAudioConverter 経路が失敗していても気づきにくい。
     本フェーズで FALLBACK 発生をログ化した（`converter` category）。多発するなら 1 の format 矛盾が原因の可能性。

### ログした具体ポイント一覧（実装箇所）

- `ProcessTapAudioSource.start`: PID 解決 / `processObjectID` / tap created / **tap native ASBD 全フィールド** / aggregate created / `AudioDeviceStart` status。
- `ProcessTapAudioSource` IOProc: 呼び出し回数（atomic, 先頭 3 回のみログ + stop サマリ）/ `mNumberBuffers` / 先頭バッファの `mNumberChannels`・`mDataByteSize` / 算出 floatCount / 宣言 format。
- `ProcessTapAudioSource.stop`: `ioProcCalls` / `yieldedFrames` サマリ。
- `SpeechAnalyzerAdapter`: locale / asset 導入有無 / **analyzerFormat（sampleRate/channels/interleaved/commonFormat）** / feeder received・converted・dropped（+ サマリ）/ results volatile・finalized（+ サマリ）。
- `AudioFormatConverter.convert`: 変換フォールバック発生（入力/target format、先頭 3 回）。
- `TranscriptionService`（domain, `EventLogger` 経由）: 状態遷移 / 権限 currentStatus・afterRequest / audioSource.start 成功 / 認識結果受信件数（volatile/finalized）/ stop 時サマリ / error・保存失敗。
