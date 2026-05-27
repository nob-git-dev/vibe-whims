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
    private let locale: Locale

    /// 状態変化の通知（presentation の ViewModel が購読する想定）。
    private var onStateChange: (@Sendable (SessionState) -> Void)?

    /// running になった世代。stop 後に到着した結果を破棄するためのガード。
    private var generation: Int = 0
    private var recognitionTask: Task<Void, Never>?

    public init(
        audioSource: AudioSource,
        recognizer: SpeechRecognizer,
        permissionGate: PermissionGate,
        sink: TranscriptSink,
        store: TranscriptStore = TranscriptStore(),
        locale: Locale
    ) {
        self.audioSource = audioSource
        self.recognizer = recognizer
        self.permissionGate = permissionGate
        self.sink = sink
        self.store = store
        self.locale = locale
    }

    public var transcriptStore: TranscriptStore { store }

    public func setStateChangeHandler(_ handler: @escaping @Sendable (SessionState) -> Void) {
        self.onStateChange = handler
    }

    private func transition(to newState: SessionState) {
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
        if status == .undetermined {
            status = await permissionGate.request()
        }

        guard status == .granted else {
            // 未許可のまま音声取得を開始しない（受け入れ条件・本質）。
            transition(to: .awaitingPermission(app))
            return
        }

        do {
            let audioStream = try await audioSource.start(app: app)
            generation += 1
            let myGeneration = generation
            transition(to: .running(app))

            let results = recognizer.transcribe(audioStream, locale: locale)
            recognitionTask = Task { [weak self] in
                for await result in results {
                    guard let self else { return }
                    await self.handle(result: result, generation: myGeneration)
                }
            }
        } catch {
            transition(to: .error("audio source start failed: \(error)"))
        }
    }

    /// 認識結果の取り込み。停止後（世代不一致）に到着した結果は破棄し、保存・追記しない。
    private func handle(result: RecognitionResult, generation resultGeneration: Int) async {
        // running 世代でなければ（= 停止後の遅延バッファ）破棄する。
        guard case .running = state, resultGeneration == generation else {
            return
        }
        store.ingest(result)
        if result.isFinal {
            // finalized のみ保存（取りこぼし防止・volatile は保存しない）。
            try? await sink.append(TranscriptSegment(text: result.text, range: result.range))
        }
    }

    /// 停止。running → stopping →（finalize+flush）→ stopped。
    /// 最後の finalized まで flush してから停止する。停止後の結果は破棄される（世代更新）。
    public func stop() async {
        guard case .running(let app) = state else { return }
        transition(to: .stopping(app))

        // これ以降に到着する結果を破棄するため世代を進める。
        generation += 1

        await audioSource.stop()
        recognitionTask?.cancel()
        recognitionTask = nil

        // 最後の確定結果まで書き切る（取りこぼし防止）。
        try? await sink.flush()

        transition(to: .stopped)
    }

    /// タップ／認識エラー時。running → error（リソース解放）。
    public func failed(_ message: String) async {
        generation += 1
        await audioSource.stop()
        recognitionTask?.cancel()
        recognitionTask = nil
        transition(to: .error(message))
    }
}
