import Foundation
import SpeechTapDomain

/// AVAudioConverter による PCM → analyzer format 変換（ADR-3 / 必須前提）。
/// タップの native format と SpeechAnalyzer の bestAvailableAudioFormat が一致する保証はないため独立化する。
///
/// TODO（実機検証が必要なため未実装。SPEC 手動検証項目参照）:
/// - AudioStreamFormat / AudioFrame → AVAudioPCMBuffer 構築
/// - AVAudioConverter で target（bestAvailableAudioFormat）へ変換
/// - 変換結果を AudioFrame（target format）へ戻す、または AnalyzerInput 用バッファを返す
public struct AudioFormatConverter: Sendable {
    public init() {}

    /// native フレームを target フォーマットへ変換する境界（OS 型を domain に漏らさない）。
    public func convert(_ frame: AudioFrame, to target: AudioStreamFormat) -> AudioFrame {
        // TODO: AVAudioConverter による実変換。現状はパススルーのスケルトン。
        AudioFrame(samples: frame.samples, format: target, timestamp: frame.timestamp)
    }
}
