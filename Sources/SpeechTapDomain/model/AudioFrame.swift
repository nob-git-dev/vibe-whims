import Foundation

/// 対象アプリから取得した PCM フレーム（domain 中立）。
/// samples は正規化された float サンプル列。AVAudioPCMBuffer 等 OS 型は infra で相互変換し domain に漏らさない。
public struct AudioFrame: Sendable {
    public let samples: [Float]
    public let format: AudioStreamFormat
    /// 取得時刻（秒）。順序付け・遅延判定に使う。
    public let timestamp: Double

    public init(samples: [Float], format: AudioStreamFormat, timestamp: Double) {
        self.samples = samples
        self.format = format
        self.timestamp = timestamp
    }
}
