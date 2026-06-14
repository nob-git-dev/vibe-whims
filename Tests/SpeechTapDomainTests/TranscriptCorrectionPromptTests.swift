import Testing
import Foundation
@testable import SpeechTapDomain

struct TranscriptCorrectionPromptTests {

    @Test("ASR 校正 prompt は要約・翻訳・情報追加を禁止し、本文だけの出力を要求する")
    func promptConstrainsCorrectionScope() {
        let prompt = TranscriptCorrectionPrompt(rawTranscript: "これは音声認識の原文です。")

        #expect(prompt.system.contains("要約しない"))
        #expect(prompt.system.contains("翻訳しない"))
        #expect(prompt.system.contains("説明を足さない"))
        #expect(prompt.system.contains("90%以上の確信"))
        #expect(prompt.system.contains("番号を推測で変えない"))
        #expect(prompt.system.contains("同じ誤認識"))
        #expect(prompt.system.contains("幾何学"))
        #expect(prompt.system.contains("二直角"))
        #expect(prompt.system.contains("非ユークリッ"))
        #expect(prompt.system.contains("思考過程"))
        #expect(prompt.system.contains("校正済み本文のみ"))
        #expect(prompt.system.contains("Markdown フェンス"))
        #expect(prompt.user.contains("<asr_transcript>"))
        #expect(prompt.user.contains("これは音声認識の原文です。"))
    }

    @Test("TranscriptSession の各 segment を改行区切りの原文 transcript にする")
    func rawTranscriptPreservesSegmentOrder() {
        let now = Date()
        let session = TranscriptSession(
            segments: [
                TranscriptSegment(text: "一つ目。"),
                TranscriptSegment(text: "二つ目。"),
                TranscriptSegment(text: "三つ目。")
            ],
            startedAt: now,
            stoppedAt: now
        )

        #expect(TranscriptCorrectionPrompt.rawTranscript(from: session) == "一つ目。\n二つ目。\n三つ目。")
    }
}
