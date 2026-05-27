import Foundation
import SpeechTapDomain
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(os)
import os
#endif

/// AVAudioConverter による PCM → analyzer format 変換（ADR-3 / 必須前提）。
/// タップの native format と SpeechAnalyzer の bestAvailableAudioFormat が一致する保証はないため独立化する。
///
/// 役割:
/// - domain 中立の AudioFrame ⇔ OS 型 AVAudioPCMBuffer の相互変換（OS 型を domain に漏らさない）。
/// - native format → target format（bestAvailableAudioFormat）への AVAudioConverter 変換。
///
/// 実機検証項目: タップ native format の実値・変換後フォーマットの整合・サンプル欠落の有無。
public struct AudioFormatConverter: Sendable {
    public init() {}

    #if canImport(AVFoundation)
    /// source の AVAudioPCMBuffer を target フォーマット（commonFormat は Int16 / Float32 等）の
    /// AVAudioPCMBuffer へ直接変換する（ADR-3）。
    ///
    /// 重要: 出力バッファは **target フォーマットで確保**する。AVAudioConverter は出力バッファの
    /// フォーマットに合わせて書き込むため、floatChannelData 前提（旧バグ）をやめ、
    /// Int16 等の commonFormat でも取りこぼさず変換できる。
    /// SpeechAnalyzer の analyzerFormat（Int16/16kHz/モノ 等）をそのまま target に渡せばよい。
    public func convertBuffer(_ source: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: source.format, to: target) else { return nil }
        return Self.convert(source, using: converter, to: target)
    }

    /// AudioStreamFormat（タップ native などの domain 中立フォーマット）→ AVAudioFormat（float32）。
    /// タップは float32 PCM を供給するため source 側は float32 で表現する。
    static func avFormat(from format: AudioStreamFormat) -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: AVAudioChannelCount(max(1, format.channelCount)),
            interleaved: format.isInterleaved
        )
    }

    /// AudioFrame（[Float] サンプル）→ AVAudioPCMBuffer。
    static func pcmBuffer(from frame: AudioFrame, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let channels = Int(format.channelCount)
        guard channels > 0 else { return nil }
        let frameCapacity = AVAudioFrameCount(frame.samples.count / channels)
        guard frameCapacity > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity),
              let channelData = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = frameCapacity
        if format.isInterleaved {
            // インターリーブ: 単一バッファに全チャンネルが連続。
            let dst = channelData[0]
            frame.samples.withUnsafeBufferPointer { src in
                dst.update(from: src.baseAddress!, count: src.count)
            }
        } else {
            // 非インターリーブ: チャンネルごとに分離。samples は [c0s0, c1s0, c0s1, ...] の順とみなす。
            let n = Int(frameCapacity)
            for ch in 0..<channels {
                let dst = channelData[ch]
                for i in 0..<n {
                    dst[i] = frame.samples[i * channels + ch]
                }
            }
        }
        return buffer
    }

    /// AVAudioConverter で 1 バッファを変換する。
    static func convert(_ input: AVAudioPCMBuffer, using converter: AVAudioConverter, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        // サンプルレート比からおおよその出力容量を見積もる（余裕を持たせる）。
        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        // convert(to:error:withInputFrom:) のブロックは同一スレッドで同期実行されるが、
        // Swift 6 の Sendable 解析を満たすため、入力バッファと消費フラグを box に閉じ込める。
        final class Box: @unchecked Sendable {
            var consumed = false
            let buffer: AVAudioPCMBuffer
            init(_ b: AVAudioPCMBuffer) { self.buffer = b }
        }
        let box = Box(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if box.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            box.consumed = true
            outStatus.pointee = .haveData
            return box.buffer
        }
        if status == .error || error != nil { return nil }
        return output
    }
    #endif
}
