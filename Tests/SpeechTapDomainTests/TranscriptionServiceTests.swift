import Testing
import Foundation
@testable import SpeechTapDomain

/// TranscriptionService の状態遷移と、受け入れ条件に直結する本質的振る舞いを検証する。
struct TranscriptionServiceTests {

    private func makeService(
        permission: FakePermissionGate,
        audio: FakeAudioSource,
        recognizer: SpeechRecognizer,
        sink: SpyTranscriptSink
    ) -> TranscriptionService {
        TranscriptionService(
            audioSource: audio,
            recognizer: recognizer,
            permissionGate: permission,
            sink: sink,
            locale: Locale(identifier: "ja-JP")
        )
    }

    @Test("対象選択で idle → selected に遷移する")
    func selectTransitionsToSelected() async {
        let service = makeService(
            permission: FakePermissionGate(initial: .granted),
            audio: FakeAudioSource(),
            recognizer: FakeSpeechRecognizer(results: []),
            sink: SpyTranscriptSink()
        )
        await service.select(app: AppId("com.example.app"))
        let state = await service.state
        #expect(state == .selected(AppId("com.example.app")))
    }

    /// 受け入れ条件「未許可のまま音声取得を開始しない」を守る最重要テスト。
    @Test("権限 denied のとき running に進まず awaitingPermission になる（未許可のまま開始しない）")
    func deniedDoesNotStartAndGoesAwaitingPermission() async {
        let audio = FakeAudioSource()
        let service = makeService(
            permission: FakePermissionGate(initial: .denied),
            audio: audio,
            recognizer: FakeSpeechRecognizer(results: []),
            sink: SpyTranscriptSink()
        )
        let app = AppId("com.example.app")
        await service.start(app: app)

        let state = await service.state
        #expect(state == .awaitingPermission(app))
        // 受け入れ条件「未許可のまま音声取得を開始しない」を直接検証する（start が一度も呼ばれない）。
        #expect(audio.startCalled == false)
        #expect(audio.stopCalled == false)
    }

    @Test("undetermined のとき request して granted なら running になる")
    func undeterminedRequestsThenRuns() async {
        let service = makeService(
            permission: FakePermissionGate(initial: .undetermined, afterRequest: .granted),
            audio: FakeAudioSource(frames: [.dummy()]),
            recognizer: FakeSpeechRecognizer(results: []),
            sink: SpyTranscriptSink()
        )
        let app = AppId("com.example.app")
        await service.start(app: app)
        let state = await service.state
        #expect(state == .running(app))
        await service.stop()
    }

    @Test("undetermined → request しても denied なら開始しない")
    func undeterminedRequestDeniedDoesNotStart() async {
        let audio = FakeAudioSource()
        let service = makeService(
            permission: FakePermissionGate(initial: .undetermined, afterRequest: .denied),
            audio: audio,
            recognizer: FakeSpeechRecognizer(results: []),
            sink: SpyTranscriptSink()
        )
        let app = AppId("com.example.app")
        await service.start(app: app)
        let state = await service.state
        #expect(state == .awaitingPermission(app))
        // request 後も denied なら音声取得を開始しない（start を一度も呼ばない）。
        #expect(audio.startCalled == false)
    }

    /// 受け入れ条件「確定結果が保存される」＋ ADR-3「保存対象は finalized のみ」。
    @Test("granted で開始すると finalized のみが sink に保存され volatile は保存されない")
    func onlyFinalizedIsSaved() async {
        let sink = SpyTranscriptSink()
        let results = [
            RecognitionResult(text: "こん", isFinal: false),
            RecognitionResult(text: "こんにちは。", isFinal: true),
            RecognitionResult(text: "げ", isFinal: false),
            RecognitionResult(text: "元気ですか。", isFinal: true)
        ]
        let service = makeService(
            permission: FakePermissionGate(initial: .granted),
            audio: FakeAudioSource(frames: [.dummy()]),
            recognizer: FakeSpeechRecognizer(results: results),
            sink: sink
        )
        await service.start(app: AppId("a"))
        // 認識タスクが結果を流し終えるのを待つ。
        try? await waitUntil { await service.transcriptStore.finalizedSegments.count == 2 }

        #expect(await sink.appended.map(\.text) == ["こんにちは。", "元気ですか。"])
        let store = await service.transcriptStore
        #expect(store.finalizedSegments.count == 2)  // volatile は積まれない
        await service.stop()
    }

    /// 受け入れ条件「停止でき、停止後 finalize→flush され最後の確定まで保存される」。
    @Test("停止すると stopping → stopped に遷移し flush が呼ばれる（取りこぼし防止）")
    func stopFlushesAndTransitionsToStopped() async {
        let sink = SpyTranscriptSink()
        let service = makeService(
            permission: FakePermissionGate(initial: .granted),
            audio: FakeAudioSource(frames: [.dummy()]),
            recognizer: FakeSpeechRecognizer(results: [RecognitionResult(text: "最後。", isFinal: true)]),
            sink: sink
        )
        await service.start(app: AppId("a"))
        try? await waitUntil { await service.transcriptStore.finalizedSegments.count == 1 }
        await service.stop()

        let state = await service.state
        #expect(state == .stopped)
        #expect(await sink.flushCount == 1)                 // 停止時に flush される
        #expect(await sink.appended.map(\.text) == ["最後。"]) // 最後の確定まで保存
    }

    /// 受け入れ条件「停止後は新たなテキストが追記されない」の最重要テスト。
    @Test("停止後に到着した結果は保存・追記されない（停止後不追記）")
    func resultsAfterStopAreDiscarded() async {
        let sink = SpyTranscriptSink()
        let manual = ManualSpeechRecognizer()
        let service = makeService(
            permission: FakePermissionGate(initial: .granted),
            audio: FakeAudioSource(frames: [.dummy()]),
            recognizer: manual,
            sink: sink
        )
        await service.start(app: AppId("a"))
        // running 中に 1 件確定を流す。
        manual.emit(RecognitionResult(text: "停止前。", isFinal: true))
        try? await waitUntil { await service.transcriptStore.finalizedSegments.count == 1 }

        await service.stop()

        // 停止後に遅延結果が到着しても破棄されるべき。
        manual.emit(RecognitionResult(text: "停止後の遅延。", isFinal: true))
        manual.finish()
        // 少し待って追記されないことを確認。
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(await sink.appended.map(\.text) == ["停止前。"]) // 停止後の結果は入らない
        let store = await service.transcriptStore
        #expect(store.finalizedSegments.map(\.text) == ["停止前。"])
    }

    @Test("AudioSource の start が失敗すると error 状態になる（リソース解放・提示）")
    func audioStartFailureGoesError() async {
        let service = makeService(
            permission: FakePermissionGate(initial: .granted),
            audio: FakeAudioSource(shouldThrow: true),
            recognizer: FakeSpeechRecognizer(results: []),
            sink: SpyTranscriptSink()
        )
        await service.start(app: AppId("a"))
        let state = await service.state
        if case .error = state {
            // OK
        } else {
            Issue.record("expected .error, got \(state)")
        }
    }

    /// Must-1: 停止時に finalize で遅れて届く最後の finalized が取りこぼされず保存される（ADR-3）。
    /// stop 呼び出し時点ではまだ流していない finalized を、finalize() 後に流す recognizer で再現する。
    @Test("停止時に finalize で遅れて届く最後の finalized が保存される（取りこぼし防止）")
    func stopFinalizesAndSavesLastFinalized() async {
        let sink = SpyTranscriptSink()
        let recognizer = DeferredFinalizeRecognizer(
            immediate: [RecognitionResult(text: "途中。", isFinal: true)],
            onFinalize: [
                RecognitionResult(text: "最後の暫定が確定。", isFinal: true)
            ]
        )
        let service = makeService(
            permission: FakePermissionGate(initial: .granted),
            audio: FakeAudioSource(frames: [.dummy()]),
            recognizer: recognizer,
            sink: sink
        )
        await service.start(app: AppId("a"))
        // running 中に届く finalized を待つ。
        try? await waitUntil { await service.transcriptStore.finalizedSegments.count == 1 }

        // 停止: finalize → 遅延 finalized 受領 → append → flush の順で取りこぼさない。
        await service.stop()

        let state = await service.state
        #expect(state == .stopped)
        // finalize 後に届いた最後の確定も保存されていること（取りこぼさない）。
        #expect(await sink.appended.map(\.text) == ["途中。", "最後の暫定が確定。"])
        #expect(await sink.flushCount == 1)
    }

    /// Should-3: 認識/タップのストリームが error 終端すると error 状態へ遷移し、
    /// audioSource.stop() でリソース解放される（状態遷移図 running → error）。
    @Test("認識ストリームが error 終端すると error 状態になりリソース解放される")
    func recognitionStreamErrorGoesError() async {
        let audio = FakeAudioSource(frames: [.dummy()])
        let service = makeService(
            permission: FakePermissionGate(initial: .granted),
            audio: audio,
            recognizer: FailingSpeechRecognizer(before: [RecognitionResult(text: "途中。", isFinal: true)]),
            sink: SpyTranscriptSink()
        )
        await service.start(app: AppId("a"))
        // error 状態へ遷移するのを待つ。
        try? await waitUntil {
            if case .error = await service.state { return true }
            return false
        }
        let state = await service.state
        if case .error = state {
            // OK
        } else {
            Issue.record("expected .error, got \(state)")
        }
        // error 経路でも audioSource.stop() が呼ばれリソース解放される。
        #expect(audio.stopCalled == true)
    }
}

/// 条件が満たされるまで短くポーリングする待機ヘルパ（非同期完了の同期点）。
func waitUntil(timeout: Double = 2.0, _ condition: @Sendable () async -> Bool) async throws {
    let start = Date()
    while !(await condition()) {
        if Date().timeIntervalSince(start) > timeout {
            throw WaitTimeout()
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}
struct WaitTimeout: Error {}
