import Foundation

/// 確定テキストの永続化境界（実装は infrastructure: ファイル保存等）。
/// 本質: 確定結果を取りこぼさず保存する。停止時は flush で最後まで書き切る。
public protocol TranscriptSink: Sendable {
    func append(_ segment: TranscriptSegment) async throws
    func flush() async throws
}
