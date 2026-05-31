import Foundation

/// 文字起こし結果の集約・保持（ADR-3）。
/// volatile（暫定）は「上書き表示用」、finalized（確定）は「確定列」として分離管理する。
/// 保存対象は finalized のみ。volatile は最新のみ保持し、finalized が来たら volatile はクリアする。
public final class TranscriptStore: @unchecked Sendable {
    private let lock = NSLock()
    private var _finalized: [TranscriptSegment] = []
    private var _volatile: String = ""

    public init() {}

    /// 認識結果を取り込む。isFinal=true は finalized 列に追加し volatile をクリア。
    /// isFinal=false は volatile を上書き（表示用）するだけで保存しない。
    public func ingest(_ result: RecognitionResult) {
        lock.lock()
        defer { lock.unlock() }
        if result.isFinal {
            _finalized.append(TranscriptSegment(text: result.text, range: result.range))
            _volatile = ""
        } else {
            _volatile = result.text
        }
    }

    /// 確定済みセグメント列（保存対象）。
    public var finalizedSegments: [TranscriptSegment] {
        lock.lock()
        defer { lock.unlock() }
        return _finalized
    }

    /// 現在の暫定表示テキスト（保存しない）。
    public var volatileText: String {
        lock.lock()
        defer { lock.unlock() }
        return _volatile
    }

    /// 全確定テキストを結合した表示用文字列。
    public var finalizedText: String {
        lock.lock()
        defer { lock.unlock() }
        return _finalized.map(\.text).joined(separator: " ")
    }

    /// 現セッションの確定列と時刻を値型として返す（機能A / ADR-6）。
    /// store の状態は変更しない（読み取り専用のスナップショット）。
    /// 呼び出し側（StopFlowCoordinator 等）が SessionExporter に渡す入力を組み立てるために使う。
    public func snapshotCurrentSession(startedAt: Date, stoppedAt: Date) -> TranscriptSession {
        lock.lock()
        defer { lock.unlock() }
        return TranscriptSession(segments: _finalized, startedAt: startedAt, stoppedAt: stoppedAt)
    }

    /// 表示用バッファ（_finalized / _volatile）をクリアする（機能A / ADR-6）。
    ///
    /// 重要（固定要件「メインファイル append 経路は不変」）:
    /// - **TranscriptSink には一切触れない**（append / flush を呼ばない）。
    /// - メインファイル `transcript.txt` には ADR-4 のとおり append され続けているため、
    ///   ここで表示用列をクリアしてもメインファイルの内容には影響しない。
    /// - 次セッション開始時は _finalized が空から始まる（セッション境界の意味付け）。
    public func clearDisplay() {
        lock.lock()
        defer { lock.unlock() }
        _finalized.removeAll()
        _volatile = ""
    }
}
