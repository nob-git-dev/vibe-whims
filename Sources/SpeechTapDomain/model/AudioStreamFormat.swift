import Foundation

/// オーディオフレームのフォーマットを表す domain 中立の値型。
/// AVAudioFormat 等の OS 型を domain に漏らさないための正規化表現。
public struct AudioStreamFormat: Hashable, Sendable {
    public let sampleRate: Double
    public let channelCount: Int
    public let isInterleaved: Bool

    public init(sampleRate: Double, channelCount: Int, isInterleaved: Bool) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.isInterleaved = isInterleaved
    }
}
