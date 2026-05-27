import Testing
import Foundation
@testable import SpeechTapInfrastructure
import SpeechTapDomain
#if canImport(AVFoundation)
import AVFoundation
#endif

/// AudioFormatConverter の本質（ADR-3 / 実機ログで断定したバグの再発防止）:
/// タップの native format（48kHz/2ch/float32/インターリーブ）を、SpeechAnalyzer が要求する
/// analyzerFormat（commonFormat が Int16 等・16kHz・モノ）の AVAudioPCMBuffer へ正しく変換すること。
///
/// 旧実装は出力を常に floatChannelData 前提で詰めていたため、Int16 フォーマットのバッファでは
/// floatChannelData が nil となり全フレームが破棄され、認識結果がゼロになっていた（実機ログで確定）。
#if canImport(AVFoundation)
struct AudioFormatConverterTests {

    /// タップ native 相当（48kHz/2ch/float32/インターリーブ）のサイン波バッファを生成する。
    private func makeSourceBuffer(frames: Int = 512) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        // インターリーブなので floatChannelData[0] に [L0,R0,L1,R1,...] が並ぶ。
        let ptr = buffer.floatChannelData![0]
        for i in 0..<frames {
            let t = Double(i) / 48_000.0
            let v = Float(sin(2.0 * Double.pi * 440.0 * t)) * 0.5
            ptr[i * 2] = v
            ptr[i * 2 + 1] = v
        }
        return buffer
    }

    @Test("48k/2ch/float32 → 16k/1ch/Int16 へ変換しても nil にならず frameLength>0（Int16 で破棄されない）")
    func convertsToInt16Mono() throws {
        let converter = AudioFormatConverter()
        let source = makeSourceBuffer()
        let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!

        let out = converter.convertBuffer(source, to: target)
        let buffer = try #require(out, "Int16 ターゲットで変換結果が nil になってはならない（旧 floatChannelData バグの再発）")
        #expect(buffer.frameLength > 0)
        #expect(buffer.format.commonFormat == .pcmFormatInt16)
        #expect(buffer.format.channelCount == 1)
        #expect(buffer.format.sampleRate == 16_000)
    }

    @Test("Float32 ターゲットでも nil にならず変換できる")
    func convertsToFloat32Mono() throws {
        let converter = AudioFormatConverter()
        let source = makeSourceBuffer()
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        let out = converter.convertBuffer(source, to: target)
        let buffer = try #require(out)
        #expect(buffer.frameLength > 0)
        #expect(buffer.format.commonFormat == .pcmFormatFloat32)
    }

    @Test("48k→16k のサンプルレート変換で出力フレーム数がおおよそ sampleRate 比になる")
    func resamplesByRateRatio() throws {
        let converter = AudioFormatConverter()
        let source = makeSourceBuffer(frames: 4_800) // 48k で 0.1 秒
        let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!

        let buffer = try #require(converter.convertBuffer(source, to: target))
        // 16k で 0.1 秒 ≒ 1600 フレーム。リサンプラの過渡で多少前後するため幅を持たせる。
        #expect(buffer.frameLength > 1_200)
        #expect(buffer.frameLength < 2_000)
    }
}
#endif
