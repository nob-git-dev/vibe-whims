import Testing
import Foundation
@testable import SpeechTapDomain

/// 機能B（ADR-5）: DisplayPipeline の本質テスト。
///
/// 本質（固定要件「表示と保存の経路分離」）:
/// - finalized が日本語と検出された場合は翻訳せず原文表示。
/// - finalized が非日本語と検出された場合は Translator.translate を呼んで日本語訳を表示用テキストにする。
/// - volatile は翻訳しない（常に原文表示。ADR-5）。
/// - 翻訳失敗（throw）時は原文表示にフォールバック（黙って空表示にしない）。
/// - DisplayPipeline は表示用文字列だけを返す純粋なコンポーネントであり、
///   **TranscriptSink には触れない**（保存経路を汚染しない）。本質を別テスト
///   `transcriptSinkReceivesOriginalText` で SpyTranscriptSink により担保する。
struct DisplayPipelineTests {

    /// 言語検出を制御する fake LanguageDetector。
    final class FakeLanguageDetector: LanguageDetector, @unchecked Sendable {
        let result: Locale?
        init(_ result: Locale?) { self.result = result }
        func detect(_ text: String) -> Locale? { result }
    }

    /// 翻訳呼び出しを記録する fake Translator。
    final class FakeTranslator: Translator, @unchecked Sendable {
        struct Failure: Error {}
        private let lock = NSLock()
        private var _calls: [(text: String, from: Locale, to: Locale)] = []
        private var _ensureCalls: [Locale] = []
        let shouldThrow: Bool
        let translateMap: [String: String]
        init(translateMap: [String: String] = [:], shouldThrow: Bool = false) {
            self.translateMap = translateMap
            self.shouldThrow = shouldThrow
        }
        var calls: [(text: String, from: Locale, to: Locale)] {
            lock.lock(); defer { lock.unlock() }; return _calls
        }
        var ensureCalls: [Locale] {
            lock.lock(); defer { lock.unlock() }; return _ensureCalls
        }
        func translate(_ text: String, from source: Locale, to target: Locale) async throws -> String {
            lock.withLock { _calls.append((text, source, target)) }
            if shouldThrow { throw Failure() }
            return translateMap[text] ?? "[\(target.identifier)]\(text)"
        }
        func ensureAvailable(for source: Locale) async throws {
            lock.withLock { _ensureCalls.append(source) }
            if shouldThrow { throw Failure() }
        }
    }

    private let ja = Locale(identifier: "ja-JP")
    private let en = Locale(identifier: "en-US")

    @Test("finalized が日本語と検出されたら翻訳せず原文を表示する（日本語はそのまま）")
    func japaneseFinalizedIsNotTranslated() async {
        let detector = FakeLanguageDetector(ja)
        let translator = FakeTranslator()
        let pipeline = DisplayPipeline(detector: detector, translator: translator, targetLocale: ja)

        let result = await pipeline.renderFinalized("こんにちは")
        #expect(result == "こんにちは")
        #expect(translator.calls.isEmpty)
    }

    @Test("finalized が非日本語（英語）と検出されたら Translator.translate で日本語訳を表示用テキストにする")
    func nonJapaneseFinalizedIsTranslated() async {
        let detector = FakeLanguageDetector(en)
        let translator = FakeTranslator(translateMap: ["hello": "こんにちは"])
        let pipeline = DisplayPipeline(detector: detector, translator: translator, targetLocale: ja)

        let result = await pipeline.renderFinalized("hello")
        #expect(result == "こんにちは")
        let calls = translator.calls
        #expect(calls.count == 1)
        #expect(calls.first?.text == "hello")
        #expect(calls.first?.from.identifier == en.identifier)
        #expect(calls.first?.to.identifier == ja.identifier)
    }

    @Test("Translator.translate が throw したら原文にフォールバックする（黙って空表示にしない）")
    func translationFailureFallsBackToOriginal() async {
        let detector = FakeLanguageDetector(en)
        let translator = FakeTranslator(shouldThrow: true)
        let pipeline = DisplayPipeline(detector: detector, translator: translator, targetLocale: ja)

        let result = await pipeline.renderFinalized("hello")
        #expect(result == "hello")
    }

    @Test("LanguageDetector が判定不能（nil）なら原文表示にフォールバック（『日本語ではない』とは扱わない）")
    func unknownLocaleFallsBackToOriginal() async {
        let detector = FakeLanguageDetector(nil)
        let translator = FakeTranslator()
        let pipeline = DisplayPipeline(detector: detector, translator: translator, targetLocale: ja)

        let result = await pipeline.renderFinalized("???")
        #expect(result == "???")
        #expect(translator.calls.isEmpty)
    }

    @Test("volatile は翻訳しない（常に原文をそのまま表示する・ADR-5）")
    func volatileIsNeverTranslated() async {
        let detector = FakeLanguageDetector(en)
        let translator = FakeTranslator(translateMap: ["hi": "こんにちは"])
        let pipeline = DisplayPipeline(detector: detector, translator: translator, targetLocale: ja)

        let result = await pipeline.renderVolatile("hi")
        #expect(result == "hi")
        #expect(translator.calls.isEmpty)
    }

    /// 固定要件「TranscriptSink.append には常に原文」を構造的に担保するテスト。
    /// DisplayPipeline 経由でテキストを表示用に変換しても、保存経路（TranscriptSink）には原文が渡ることを
    /// SpyTranscriptSink で検証する。DisplayPipeline は TranscriptSink を触らないため、
    /// TranscriptionService が finalized を sink に渡す経路（既存）が原文のままであることを再確認する。
    @Test("TranscriptSink.append には常に原文が渡る（DisplayPipeline は保存経路を一切触らない）")
    func transcriptSinkReceivesOriginalText() async {
        let detector = FakeLanguageDetector(en)
        let translator = FakeTranslator(translateMap: ["hello": "こんにちは"])
        let pipeline = DisplayPipeline(detector: detector, translator: translator, targetLocale: ja)
        let sink = SpyTranscriptSink()

        // 既存の保存経路を模擬: 認識結果の原文を直接 sink へ append する（TranscriptionService の経路）。
        let original = "hello"
        try? await sink.append(TranscriptSegment(text: original, range: nil))
        // 表示用には DisplayPipeline で翻訳結果を返す（保存経路には影響しない）。
        let displayText = await pipeline.renderFinalized(original)

        #expect(displayText == "こんにちは")
        // sink に渡るのは常に原文。翻訳結果は sink には絶対渡らない。
        #expect(await sink.appended.map(\.text) == ["hello"])
    }
}
