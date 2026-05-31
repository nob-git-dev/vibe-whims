import Foundation

/// 文字化ユースケースの調整役（SPEC「## 状態遷移」/ ADR-2 / ADR-3）。
/// port（AudioSource / SpeechRecognizer / PermissionGate / TranscriptSink）にのみ依存し、
/// OS API・UI を一切 import しない純粋ロジック。
///
/// 担保する本質的振る舞い:
/// - 権限 denied のとき running に進まず awaitingPermission になる（未許可のまま開始しない）。
/// - 停止時に finalize→flush され、最後の finalized まで保存される（取りこぼし防止）。
/// - 停止後に到着した結果は保存・追記されない（停止後は追記されない）。
public actor TranscriptionService {
    public private(set) var state: SessionState = .idle

    private let audioSource: AudioSource
    private let recognizer: SpeechRecognizer
    private let permissionGate: PermissionGate
    private let sink: TranscriptSink
    private let store: TranscriptStore
    /// 次回 `start` で使う初期認識ロケール（ADR-7）。
    /// `init` で config 由来の既定値を受け取り、`setRecognitionLocale(_:)` で上書きできる。
    /// `running` / `stopping` 中の変更は当該セッションに反映せず、次回 `start` から有効
    /// （実行中の locale 即時切替は SpeechAnalyzer セッションの作り直しが必要で初版スコープ外）。
    private var recognitionLocale: Locale
    /// 観測点（OS 非依存の port）。既定は no-op。Composition Root で os.Logger 実装を注入する。
    private let eventLogger: EventLogger

    /// 状態変化の通知（presentation の ViewModel が購読する想定）。
    private var onStateChange: (@Sendable (SessionState) -> Void)?

    /// 文字起こし結果が更新されたことの通知（presentation が購読し UI を更新する想定）。
    /// running 中にストリーミングで届く volatile/finalized を画面へリアルタイム反映するための port。
    /// domain は UI に依存せず、クロージャ経由で通知するだけ（onStateChange と同じ流儀）。
    private var onTranscriptUpdate: (@Sendable () -> Void)?

    /// running になった世代。stop 後に到着した結果を破棄するためのガード。
    private var generation: Int = 0
    private var recognitionTask: Task<Void, Never>?

    /// 観測用カウンタ: domain が受信した認識結果数（volatile / finalized 別）。
    /// 「running まで行くのに結果ゼロ」の切り分けで、domain まで結果が届いているかを判定する。
    private var volatileCount: Int = 0
    private var finalizedCount: Int = 0

    /// 現セッションの境界時刻（機能A / ADR-6）。
    /// `start` 成功時に Date() を記録し、`stop` 完了時に stoppedAt をスナップショットする。
    /// 読み取り用ゲッタ `currentSessionTimes` を公開し、presentation（StopFlowCoordinator）が
    /// `store.snapshotCurrentSession(...)` を組み立てる際に使う。
    /// 注: `TranscriptionService.stop()` の API は不変（戻り値や追加コールバックを増やさない）。
    private var _startedAt: Date?
    private var _stoppedAt: Date?

    public init(
        audioSource: AudioSource,
        recognizer: SpeechRecognizer,
        permissionGate: PermissionGate,
        sink: TranscriptSink,
        store: TranscriptStore = TranscriptStore(),
        locale: Locale,
        eventLogger: EventLogger = NullEventLogger()
    ) {
        self.audioSource = audioSource
        self.recognizer = recognizer
        self.permissionGate = permissionGate
        self.sink = sink
        self.store = store
        self.recognitionLocale = locale
        self.eventLogger = eventLogger
    }

    public var transcriptStore: TranscriptStore { store }

    /// 現セッションの境界時刻（機能A / ADR-6）。
    /// 直近の `start` が成功してから `stop` 完了するまでの時刻ペアを返す。
    /// 1 度も start していない場合や、stop が未完了の場合は nil（または stoppedAt 未確定で nil）。
    /// presentation の `StopFlowCoordinator` が `.stopped` 遷移を検知して読み取る用途。
    public var currentSessionTimes: (startedAt: Date, stoppedAt: Date)? {
        guard let s = _startedAt, let e = _stoppedAt else { return nil }
        return (s, e)
    }

    public func setStateChangeHandler(_ handler: @escaping @Sendable (SessionState) -> Void) {
        self.onStateChange = handler
    }

    /// 文字起こし結果更新の通知ハンドラを登録する（presentation が UI 更新のために購読する）。
    public func setTranscriptUpdateHandler(_ handler: @escaping @Sendable () -> Void) {
        self.onTranscriptUpdate = handler
    }

    /// 現在の認識ロケール（ADR-7）。presentation の「認識言語」サブメニューでチェックマーク表示に使う。
    public var currentRecognitionLocale: Locale { recognitionLocale }

    /// 次回 `start` で使う初期認識ロケールを更新する（ADR-7）。
    /// `running` / `stopping` 中も内部状態は更新するが、適用は**次回 `start` から**（実行中の即時切替は行わない）。
    /// `init` の引数・`start` / `stop` の API・状態遷移は不変（既存テストを壊さない）。OS 型を漏らさず `Locale` のみ扱う。
    public func setRecognitionLocale(_ locale: Locale) {
        recognitionLocale = locale
        eventLogger.log("recognition locale set -> \(locale.identifier) (applies on next start)")
    }

    private func transition(to newState: SessionState) {
        eventLogger.log("state transition -> \(newState)")
        state = newState
        onStateChange?(newState)
    }

    /// 対象アプリ選択。idle → selected。
    public func select(app: AppId) {
        transition(to: .selected(app))
    }

    /// 文字化開始。selected → checkingPermission →（granted）running /（denied）awaitingPermission。
    /// 権限が未許可（denied/undetermined→denied）の場合は running に進まず、音声取得を開始しない。
    public func start(app: AppId) async {
        transition(to: .checkingPermission(app))

        var status = permissionGate.currentStatus()
        eventLogger.log("permission currentStatus=\(status)")
        if status == .undetermined {
            status = await permissionGate.request()
            eventLogger.log("permission afterRequest=\(status)")
        }

        guard status == .granted else {
            // 未許可のまま音声取得を開始しない（受け入れ条件・本質）。
            transition(to: .awaitingPermission(app))
            return
        }

        do {
            let audioStream = try await audioSource.start(app: app)
            eventLogger.log("audioSource.start succeeded for \(app.rawValue)")
            generation += 1
            let myGeneration = generation
            // 機能A / ADR-6: セッション境界の開始時刻を記録（次回 stop で stoppedAt を組む）。
            _startedAt = Date()
            _stoppedAt = nil
            transition(to: .running(app))

            // ADR-7: 開始時点で保持している recognitionLocale を初期ロケールとして渡す。
            let results = recognizer.transcribe(audioStream, locale: recognitionLocale)
            // recognitionTask は self が所有し、stop()/failed() で nil 化して破棄する。
            // actor の self を強参照しても、タスク完了または nil 化で循環は解消されるため weak にしない
            // （weak だとストリーム消費が静かに止まる挙動が分かりにくいため、意図を明確化して強参照とする）。
            recognitionTask = Task {
                do {
                    for try await result in results {
                        await self.handle(result: result, generation: myGeneration)
                    }
                } catch is CancellationError {
                    // 正常な停止に伴うキャンセル。error 扱いしない。
                } catch {
                    // 認識/タップのストリームが異常終了した（finalize ではなく障害）。
                    // running → error（リソース解放）。状態遷移図 running → error を担保する。
                    await self.failed("recognition stream failed: \(error)", generation: myGeneration)
                }
            }
        } catch {
            transition(to: .error("audio source start failed: \(error)"))
        }
    }

    /// 認識結果の取り込み。停止後（世代不一致 / stopped 以降）に到着した結果は破棄し、保存・追記しない。
    /// running 中だけでなく stopping 中（finalize による最後の確定の取り込み）も受け付ける。
    private func handle(result: RecognitionResult, generation resultGeneration: Int) async {
        // 世代不一致（= 停止後の遅延バッファ）や stopped/error 後は破棄する。
        guard resultGeneration == generation else { return }
        switch state {
        case .running, .stopping:
            break
        default:
            return
        }
        store.ingest(result)
        // 結果が更新されたことを presentation に通知し、UI をリアルタイム反映させる（Fix2）。
        onTranscriptUpdate?()
        // 観測: domain まで結果が届いているか（最初の数件 + 区切りで間引きログ）。
        if result.isFinal {
            finalizedCount += 1
            eventLogger.log("recognition result #\(finalizedCount) finalized (len=\(result.text.count))")
        } else {
            volatileCount += 1
            if volatileCount <= 3 || volatileCount % 20 == 0 {
                eventLogger.log("recognition result volatile #\(volatileCount) (len=\(result.text.count))")
            }
        }
        if result.isFinal {
            // finalized のみ保存（取りこぼし防止・volatile は保存しない）。
            // 保存失敗は黙殺しない: 失敗時は error 状態へ遷移する。
            do {
                try await sink.append(TranscriptSegment(text: result.text, range: result.range))
            } catch {
                await failed("transcript save failed: \(error)", generation: resultGeneration)
            }
        }
    }

    /// 停止。running → stopping →（finalize → 残り finalized 取り込み → flush）→ stopped。
    /// ADR-3: 認識器を finalize して最後の確定結果まで取りこぼさず flush してから停止する。
    /// 即時 cancel で打ち切らない（finalize で正規に流す確定結果を取りこぼさないため）。
    public func stop() async {
        guard case .running(let app) = state else { return }
        eventLogger.log("stop requested; received so far volatile=\(volatileCount) finalized=\(finalizedCount)")
        transition(to: .stopping(app))

        // 1. 認識器を finalize: 残りの volatile を確定へ昇格し、未配信 finalized を流し切ってストリームを終端する。
        //    （port 契約: finalize() はストリームを終端する。これにより 2 の待機が完了する。）
        await recognizer.finalize()

        // 2. finalize で遅れて届く最後の finalized まで全て handle されるのを待つ
        //    （stopping 中・同一世代なので append される）。
        //    契約に反してストリームが終端しない実装に備え、有界に待ってからキャンセルで打ち切る
        //    （finalize 済みの結果は既に handle 済みのため取りこぼさない）。
        if let task = recognitionTask {
            await drain(task)
        }
        recognitionTask = nil

        // 3. 以降に到着する遅延結果を破棄するため世代を進める（停止後不追記の担保）。
        generation += 1

        // 4. 音声取得を停止しリソース解放。
        await audioSource.stop()

        // 5. 最後の確定結果まで書き切る（取りこぼし防止）。保存失敗は黙殺しない。
        do {
            try await sink.flush()
        } catch {
            transition(to: .error("transcript flush failed: \(error)"))
            return
        }

        // 機能A / ADR-6: セッション境界の停止時刻を記録（presentation が currentSessionTimes で読む）。
        _stoppedAt = Date()
        transition(to: .stopped)
    }

    /// 認識タスクの完了を有界に待つ。port 契約どおり finalize() でストリームが終端していれば即完了する。
    /// 万一終端しない実装でも stop() がハングしないよう、タイムアウトでキャンセルして打ち切る
    /// （finalize 済みの確定結果は待機中に handle 済みのため取りこぼさない）。
    private func drain(_ task: Task<Void, Never>, timeout: Duration = .milliseconds(100)) async {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await task.value; return true }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let completedNormally = await group.next() ?? false
            if !completedNormally { task.cancel() }
            group.cancelAll()
            // 残りのサブタスク（タイムアウト or task.value）の完了を待ち、確実に終端させる。
            for await _ in group {}
        }
    }

    /// タップ／認識エラー時。running/stopping → error（リソース解放）。
    /// 公開 API（外部からの明示的エラー通知用）。
    public func failed(_ message: String) async {
        await failed(message, generation: nil)
    }

    /// 内部用: 世代ガード付きの error 遷移。認識タスクから呼ぶ際は自世代でのみ遷移させ、
    /// 既に停止済み（世代更新後）なら無視する。
    private func failed(_ message: String, generation resultGeneration: Int?) async {
        if let resultGeneration, resultGeneration != generation { return }
        eventLogger.error(message)
        switch state {
        case .stopped, .error:
            return
        default:
            break
        }
        generation += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        await audioSource.stop()
        transition(to: .error(message))
    }
}
