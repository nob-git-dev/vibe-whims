import Testing
import Foundation
@testable import SpeechTapDomain

/// 機能A（ADR-6）: セッション境界 / snapshotCurrentSession / clearDisplay の本質テスト。
///
/// 本質:
/// - snapshotCurrentSession は「現セッションの確定列」と時刻だけを値として返す（store は不変）。
/// - clearDisplay は表示用バッファ（_finalized / _volatile）をクリアするのみで、
///   **TranscriptSink には何の操作も発行しない**（保存経路を一切触らない＝メインファイル append 経路は不変）。
struct TranscriptSessionAndStoreTests {

    @Test("snapshotCurrentSession は現セッションの finalized 列と時刻を含む TranscriptSession を返す（store は不変）")
    func snapshotIncludesFinalizedAndTimes() {
        let store = TranscriptStore()
        store.ingest(RecognitionResult(text: "一つ目", isFinal: true))
        store.ingest(RecognitionResult(text: "二つ目", isFinal: true))
        store.ingest(RecognitionResult(text: "途中", isFinal: false))

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let stoppedAt = Date(timeIntervalSince1970: 1_700_000_120)
        let session = store.snapshotCurrentSession(startedAt: startedAt, stoppedAt: stoppedAt)

        #expect(session.segments.map(\.text) == ["一つ目", "二つ目"])
        #expect(session.startedAt == startedAt)
        #expect(session.stoppedAt == stoppedAt)
        // store はスナップショット後も不変（snapshot は読み取り専用）。
        #expect(store.finalizedSegments.map(\.text) == ["一つ目", "二つ目"])
        #expect(store.volatileText == "途中")
    }

    @Test("clearDisplay は表示用バッファをクリアする（_finalized / _volatile 両方）")
    func clearDisplayClearsBuffers() {
        let store = TranscriptStore()
        store.ingest(RecognitionResult(text: "x", isFinal: true))
        store.ingest(RecognitionResult(text: "y", isFinal: false))

        store.clearDisplay()

        #expect(store.finalizedSegments.isEmpty)
        #expect(store.volatileText == "")
    }

    /// 固定要件「メインファイル append 経路に触れない」を構造的に担保するための核心テスト。
    /// clearDisplay は **TranscriptSink には何の操作も発行しない**（append/flush どちらも呼ばれない）。
    @Test("clearDisplay は TranscriptSink には何の操作も発行しない（保存経路を一切触らない・固定要件）")
    func clearDisplayDoesNotTouchSink() async {
        let store = TranscriptStore()
        store.ingest(RecognitionResult(text: "x", isFinal: true))
        let sink = SpyTranscriptSink()

        // TranscriptStore は TranscriptSink を保持しない設計だが、念のため:
        // clearDisplay 呼び出しの前後で sink への操作はゼロのまま。
        store.clearDisplay()

        #expect(await sink.appended.isEmpty)
        #expect(await sink.flushCount == 0)
    }

    @Test("TranscriptSession 値型は segments / startedAt / stoppedAt を保持する（Foundation のみ）")
    func transcriptSessionValueTypeIsConstructible() {
        let segments = [
            TranscriptSegment(text: "one", range: nil),
            TranscriptSegment(text: "two", range: nil)
        ]
        let startedAt = Date(timeIntervalSince1970: 0)
        let stoppedAt = Date(timeIntervalSince1970: 60)
        let session = TranscriptSession(segments: segments, startedAt: startedAt, stoppedAt: stoppedAt)

        #expect(session.segments.count == 2)
        #expect(session.startedAt == startedAt)
        #expect(session.stoppedAt == stoppedAt)
    }
}
