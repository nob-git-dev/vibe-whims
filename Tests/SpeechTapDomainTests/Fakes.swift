import Foundation
@testable import SpeechTapDomain

// 実機・OS API なしで domain をテストするための fake/stub port 群。

/// 任意の権限状態を返す PermissionGate。request 後の状態も指定できる。
final class FakePermissionGate: PermissionGate, @unchecked Sendable {
    private let initial: PermissionStatus
    private let afterRequest: PermissionStatus
    private(set) var requestCalled = false

    init(initial: PermissionStatus, afterRequest: PermissionStatus? = nil) {
        self.initial = initial
        self.afterRequest = afterRequest ?? initial
    }

    func currentStatus() -> PermissionStatus { initial }
    func request() async -> PermissionStatus {
        requestCalled = true
        return afterRequest
    }
}

/// テストが制御する AsyncStream を流す AudioSource。
/// start で AudioFrame ストリームを返し、start / stop 呼び出しを記録する。
final class FakeAudioSource: AudioSource, @unchecked Sendable {
    private let frames: [AudioFrame]
    let shouldThrow: Bool
    private let lock = NSLock()
    private var _startCount = 0
    private var _stopCalled = false

    init(frames: [AudioFrame] = [], shouldThrow: Bool = false) {
        self.frames = frames
        self.shouldThrow = shouldThrow
    }

    /// start が呼ばれた回数（denied 時に「音声取得を開始していない」を直接検証するため）。
    var startCount: Int { lock.lock(); defer { lock.unlock() }; return _startCount }
    /// start が一度でも呼ばれたか。
    var startCalled: Bool { startCount > 0 }
    var stopCalled: Bool { lock.lock(); defer { lock.unlock() }; return _stopCalled }

    struct StartError: Error {}

    func start(app: AppId) async throws -> AsyncStream<AudioFrame> {
        lock.withLock { _startCount += 1 }
        if shouldThrow { throw StartError() }
        let frames = self.frames
        return AsyncStream { continuation in
            for f in frames { continuation.yield(f) }
            continuation.finish()
        }
    }

    func stop() async { lock.withLock { _stopCalled = true } }
}

/// 入力音声を無視し、テストが指定した RecognitionResult 列をそのまま流す SpeechRecognizer。
/// 結果の流し方（即時/遅延）を制御するため continuation を外部公開できる。
final class FakeSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let results: [RecognitionResult]

    init(results: [RecognitionResult]) {
        self.results = results
    }

    func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncThrowingStream<RecognitionResult, Error> {
        let results = self.results
        return AsyncThrowingStream { continuation in
            Task {
                // 入力ストリームを消費（実装の流れに合わせる）。
                for await _ in audio {}
                for r in results { continuation.yield(r) }
                continuation.finish()
            }
        }
    }

    func finalize() async {}
}

/// 実機の SpeechAnalyzer を模し、stop（finalize）時に**初めて**最後の finalized を流す SpeechRecognizer。
/// stop 呼び出し前にはまだ流していない finalized が、finalize() 後に遅れて届くことを再現する。
/// Must-1「停止時 finalize で最後の確定まで取りこぼさない」検証用。
final class DeferredFinalizeRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<RecognitionResult, Error>.Continuation?
    private let immediate: [RecognitionResult]
    private let onFinalize: [RecognitionResult]

    /// - immediate: transcribe 直後に流す結果（running 中に届くもの）。
    /// - onFinalize: finalize() が呼ばれて初めて流す結果（停止時に取りこぼしてはならないもの）。
    init(immediate: [RecognitionResult] = [], onFinalize: [RecognitionResult]) {
        self.immediate = immediate
        self.onFinalize = onFinalize
    }

    func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncThrowingStream<RecognitionResult, Error> {
        let immediate = self.immediate
        return AsyncThrowingStream { continuation in
            self.lock.withLock { self.continuation = continuation }
            for r in immediate { continuation.yield(r) }
            // finalize() が呼ばれるまでストリームは終端しない（running 継続を模す）。
        }
    }

    func finalize() async {
        let c = lock.withLock { continuation }
        for r in onFinalize { c?.yield(r) }
        c?.finish()
    }
}

/// 認識/タップの異常終了を模す SpeechRecognizer。
/// transcribe のストリームが error で終端する（finalize ではなく障害）。error 状態遷移の検証用。
final class FailingSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
    struct StreamError: Error {}
    private let before: [RecognitionResult]

    init(before: [RecognitionResult] = []) {
        self.before = before
    }

    func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncThrowingStream<RecognitionResult, Error> {
        let before = self.before
        return AsyncThrowingStream { continuation in
            for r in before { continuation.yield(r) }
            continuation.finish(throwing: StreamError())
        }
    }

    func finalize() async {}
}

/// 外部から手動で結果を流せる SpeechRecognizer（停止後到着シナリオ用）。
final class ManualSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<RecognitionResult, Error>.Continuation?

    func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncThrowingStream<RecognitionResult, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    func emit(_ result: RecognitionResult) {
        lock.lock()
        let c = continuation
        lock.unlock()
        c?.yield(result)
    }

    func finish() {
        lock.lock()
        let c = continuation
        lock.unlock()
        c?.finish()
    }

    func finalize() async {
        // 手動制御のため finalize では何も流さない（テスト側で emit/finish する）。
    }
}

/// transcribe で受け取った locale を記録する SpeechRecognizer（ADR-7 検証用）。
/// 「setRecognitionLocale 後に start すると、その locale が transcribe に渡る」ことを直接検証する。
final class RecordingSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private var _localesReceived: [Locale] = []
    private let results: [RecognitionResult]

    init(results: [RecognitionResult] = []) {
        self.results = results
    }

    /// transcribe が受け取った locale 列（呼び出し順）。
    var localesReceived: [Locale] { lock.lock(); defer { lock.unlock() }; return _localesReceived }
    /// 直近の transcribe が受け取った locale。
    var lastLocale: Locale? { localesReceived.last }

    func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncThrowingStream<RecognitionResult, Error> {
        lock.withLock { _localesReceived.append(locale) }
        let results = self.results
        return AsyncThrowingStream { continuation in
            Task {
                for await _ in audio {}
                for r in results { continuation.yield(r) }
                continuation.finish()
            }
        }
    }

    func finalize() async {}
}

/// 任意の対応ロケール一覧を返す RecognitionCapabilities（ADR-7 検証用）。
/// OS 型を漏らさず Foundation の [Locale] のみで動くことを担保する。
final class FakeRecognitionCapabilities: RecognitionCapabilities, @unchecked Sendable {
    private let locales: [Locale]
    init(_ locales: [Locale]) { self.locales = locales }
    func supportedLocales() async -> [Locale] { locales }
}

/// 保存（append）と flush を記録する TranscriptSink スパイ。
actor SpyTranscriptSink: TranscriptSink {
    private(set) var appended: [TranscriptSegment] = []
    private(set) var flushCount = 0

    func append(_ segment: TranscriptSegment) async throws {
        appended.append(segment)
    }
    func flush() async throws {
        flushCount += 1
    }
}

// テスト用ヘルパ。
extension AudioFrame {
    static func dummy(_ ts: Double = 0) -> AudioFrame {
        AudioFrame(samples: [0, 0, 0],
                   format: AudioStreamFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: false),
                   timestamp: ts)
    }
}
