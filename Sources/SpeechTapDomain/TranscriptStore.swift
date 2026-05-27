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
}
