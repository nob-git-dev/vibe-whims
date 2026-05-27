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
/// start で AudioFrame ストリームを返し、stop 呼び出しを記録する。
final class FakeAudioSource: AudioSource, @unchecked Sendable {
    private let frames: [AudioFrame]
    let shouldThrow: Bool
    private(set) var stopCalled = false

    init(frames: [AudioFrame] = [], shouldThrow: Bool = false) {
        self.frames = frames
        self.shouldThrow = shouldThrow
    }

    struct StartError: Error {}

    func start(app: AppId) async throws -> AsyncStream<AudioFrame> {
        if shouldThrow { throw StartError() }
        let frames = self.frames
        return AsyncStream { continuation in
            for f in frames { continuation.yield(f) }
            continuation.finish()
        }
    }

    func stop() async { stopCalled = true }
}

/// 入力音声を無視し、テストが指定した RecognitionResult 列をそのまま流す SpeechRecognizer。
/// 結果の流し方（即時/遅延）を制御するため continuation を外部公開できる。
final class FakeSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let results: [RecognitionResult]

    init(results: [RecognitionResult]) {
        self.results = results
    }

    func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncStream<RecognitionResult> {
        let results = self.results
        return AsyncStream { continuation in
            Task {
                // 入力ストリームを消費（実装の流れに合わせる）。
                for await _ in audio {}
                for r in results { continuation.yield(r) }
                continuation.finish()
            }
        }
    }
}

/// 外部から手動で結果を流せる SpeechRecognizer（停止後到着シナリオ用）。
final class ManualSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<RecognitionResult>.Continuation?

    func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncStream<RecognitionResult> {
        AsyncStream { continuation in
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
