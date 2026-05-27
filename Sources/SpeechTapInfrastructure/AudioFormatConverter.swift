import Foundation
import SpeechTapDomain
#if canImport(AVFoundation)
import AVFoundation
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

    /// domain 中立の native フレームを target フォーマットへ変換する（OS 型を domain に漏らさない境界）。
    /// AVFoundation が使えない環境ではパススルー（テスト・非 macOS 用）。
    public func convert(_ frame: AudioFrame, to target: AudioStreamFormat) -> AudioFrame {
        #if canImport(AVFoundation)
        guard
            let sourceFormat = Self.avFormat(from: frame.format),
            let targetFormat = Self.avFormat(from: target),
            let sourceBuffer = Self.pcmBuffer(from: frame, format: sourceFormat),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
            let converted = Self.convert(sourceBuffer, using: converter, to: targetFormat)
        else {
            // 変換できない場合はサンプルをそのまま運び、フォーマットだけ target に揃える
            // （walking skeleton のフォールバック。実機では上の経路を通る）。
            return AudioFrame(samples: frame.samples, format: target, timestamp: frame.timestamp)
        }
        return Self.audioFrame(from: converted, format: target, timestamp: frame.timestamp)
        #else
        return AudioFrame(samples: frame.samples, format: target, timestamp: frame.timestamp)
        #endif
    }

    #if canImport(AVFoundation)
    /// AudioStreamFormat → AVAudioFormat（float32）。
    static func avFormat(from format: AudioStreamFormat) -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: AVAudioChannelCount(max(1, format.channelCount)),
            interleaved: format.isInterleaved
        )
    }

    /// AVAudioFormat → AudioStreamFormat（domain 中立）。
    static func streamFormat(from format: AVAudioFormat) -> AudioStreamFormat {
        AudioStreamFormat(
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            isInterleaved: format.isInterleaved
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

    /// AVAudioPCMBuffer → AudioFrame（[Float] サンプル）。
    static func audioFrame(from buffer: AVAudioPCMBuffer, format: AudioStreamFormat, timestamp: Double) -> AudioFrame {
        guard let channelData = buffer.floatChannelData else {
            return AudioFrame(samples: [], format: format, timestamp: timestamp)
        }
        let channels = Int(buffer.format.channelCount)
        let n = Int(buffer.frameLength)
        var samples = [Float]()
        samples.reserveCapacity(n * channels)
        if buffer.format.isInterleaved {
            let src = channelData[0]
            samples.append(contentsOf: UnsafeBufferPointer(start: src, count: n * channels))
        } else {
            for i in 0..<n {
                for ch in 0..<channels {
                    samples.append(channelData[ch][i])
                }
            }
        }
        return AudioFrame(samples: samples, format: format, timestamp: timestamp)
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
