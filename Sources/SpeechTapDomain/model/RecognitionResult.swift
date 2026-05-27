import Foundation

/// SpeechAnalyzer から流れてくる認識結果（domain 中立）。
/// isFinal=false は volatile（暫定/上書き表示用）、isFinal=true は finalized（確定/保存対象）。
public struct RecognitionResult: Hashable, Sendable {
    public let text: String
    public let isFinal: Bool
    /// 認識テキストの時間範囲（秒）。任意。
    public let range: ClosedRange<Double>?

    public init(text: String, isFinal: Bool, range: ClosedRange<Double>? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.range = range
    }
}
