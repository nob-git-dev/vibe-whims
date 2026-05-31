import Testing
import Foundation
@testable import SpeechTapDomain

/// ADR-7（認識言語選択）の domain 振る舞いを検証する。
///
/// 本質:
/// - `setRecognitionLocale(_:)` で選んだ言語が**次回 start の初期認識ロケール**になり、
///   `recognizer.transcribe(_, locale:)` にその locale が渡る。
/// - 既定（未設定）では `init` の locale（config 由来の既定値）が使われる（設定外部化を尊重）。
/// - 実行中（running）の変更は当該セッションに反映されず、次回 start から有効（実行中ライブ切替はスコープ外）。
/// - 認識 locale を変えても**保存は原文**（経路分離・固定要件の回帰防止）。
struct RecognitionLocaleTests {

    private let ja = Locale(identifier: "ja-JP")
    private let en = Locale(identifier: "en-US")

    private func makeService(
        recognizer: SpeechRecognizer,
        sink: SpyTranscriptSink = SpyTranscriptSink(),
        locale: Locale
    ) -> TranscriptionService {
        TranscriptionService(
            audioSource: FakeAudioSource(frames: [.dummy()]),
            recognizer: recognizer,
            permissionGate: FakePermissionGate(initial: .granted),
            sink: sink,
            locale: locale
        )
    }

    @Test("setRecognitionLocale 後に start すると、その locale が recognizer.transcribe(_, locale:) に渡る")
    func setRecognitionLocaleIsUsedOnNextStart() async {
        let recognizer = RecordingSpeechRecognizer()
        let service = makeService(recognizer: recognizer, locale: ja)

        await service.setRecognitionLocale(en)
        await service.start(app: AppId("a"))
        await service.stop()

        #expect(recognizer.lastLocale?.identifier == en.identifier)
    }

    @Test("setRecognitionLocale を呼ばない場合は init の locale（config 既定）が transcribe に渡る")
    func defaultLocaleIsConfigLocale() async {
        let recognizer = RecordingSpeechRecognizer()
        let service = makeService(recognizer: recognizer, locale: ja)

        await service.start(app: AppId("a"))
        await service.stop()

        #expect(recognizer.lastLocale?.identifier == ja.identifier)
    }

    @Test("running 中に setRecognitionLocale しても当該セッションの locale は変わらず、次回 start で反映される")
    func runtimeChangeAppliesOnNextStartOnly() async {
        let recognizer = RecordingSpeechRecognizer()
        let service = makeService(recognizer: recognizer, locale: ja)

        // 1 回目セッション（ja で開始）。
        await service.start(app: AppId("a"))
        // 実行中に英語へ切替を要求（このセッションには反映されない）。
        await service.setRecognitionLocale(en)
        await service.stop()

        // 2 回目セッション（次回 start から en が反映される）。
        await service.start(app: AppId("a"))
        await service.stop()

        #expect(recognizer.localesReceived.map(\.identifier) == [ja.identifier, en.identifier])
    }

    @Test("非日本語 locale を選んでも TranscriptSink.append には認識原文がそのまま渡る（保存は原文・経路分離）")
    func savedTextIsOriginalRegardlessOfRecognitionLocale() async {
        let sink = SpyTranscriptSink()
        // 認識器は「原文（英語）」をそのまま流す。translation は presentation の DisplayPipeline に閉じる。
        let recognizer = RecordingSpeechRecognizer(results: [
            RecognitionResult(text: "hello world.", isFinal: true)
        ])
        let service = makeService(recognizer: recognizer, sink: sink, locale: ja)

        await service.setRecognitionLocale(en)
        await service.start(app: AppId("a"))
        try? await waitUntil { await service.transcriptStore.finalizedSegments.count == 1 }
        await service.stop()

        // 認識言語が英語でも、保存されるのは認識原文そのまま（翻訳結果は保存経路に入らない）。
        #expect(await sink.appended.map(\.text) == ["hello world."])
    }

    @Test("RecognitionCapabilities.supportedLocales() が Foundation の [Locale] を返す（メニュー構築用・OS 型を漏らさない）")
    func recognitionCapabilitiesReturnsLocales() async {
        let caps: RecognitionCapabilities = FakeRecognitionCapabilities([ja, en])
        let locales = await caps.supportedLocales()
        #expect(locales.map(\.identifier) == [ja.identifier, en.identifier])
    }
}
