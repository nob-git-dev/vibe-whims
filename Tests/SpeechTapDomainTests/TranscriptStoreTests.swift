import Testing
@testable import SpeechTapDomain

/// TranscriptStore の本質: volatile（暫定/上書き）と finalized（確定/保存対象）を分離管理し、
/// 保存対象は finalized のみであること（ADR-3 / 取りこぼし防止）。
struct TranscriptStoreTests {

    @Test("volatile 結果は上書き表示用で、finalized 列には積まれない（保存対象は finalized のみ）")
    func volatileIsNotSaved() {
        let store = TranscriptStore()
        store.ingest(RecognitionResult(text: "こんに", isFinal: false))
        store.ingest(RecognitionResult(text: "こんにちは", isFinal: false))

        #expect(store.volatileText == "こんにちは")        // 最新で上書きされる
        #expect(store.finalizedSegments.isEmpty)             // 暫定は確定列に積まれない
    }

    @Test("finalized 結果は確定列に追加され、volatile はクリアされる")
    func finalizedIsAppendedAndVolatileCleared() {
        let store = TranscriptStore()
        store.ingest(RecognitionResult(text: "こんに", isFinal: false))
        store.ingest(RecognitionResult(text: "こんにちは。", isFinal: true))

        #expect(store.finalizedSegments.count == 1)
        #expect(store.finalizedSegments.first?.text == "こんにちは。")
        #expect(store.volatileText == "")                    // 確定後 volatile はクリア
    }

    @Test("複数の finalized は順序を保って確定列に積まれる（取りこぼし・順序崩れ防止）")
    func multipleFinalizedKeepOrder() {
        let store = TranscriptStore()
        store.ingest(RecognitionResult(text: "一つ目", isFinal: true))
        store.ingest(RecognitionResult(text: "二つ目", isFinal: true))
        store.ingest(RecognitionResult(text: "三つ目", isFinal: true))

        #expect(store.finalizedSegments.map(\.text) == ["一つ目", "二つ目", "三つ目"])
    }
}
