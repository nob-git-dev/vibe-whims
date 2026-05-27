import Foundation

/// 確定（finalized）した文字起こしの 1 区切り。TranscriptSink に保存される単位。
public struct TranscriptSegment: Hashable, Sendable {
    public let text: String
    public let range: ClosedRange<Double>?

    public init(text: String, range: ClosedRange<Double>? = nil) {
        self.text = text
        self.range = range
    }
}
