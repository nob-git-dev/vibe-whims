import Foundation
import Synchronization
import SpeechTapDomain
#if canImport(Speech)
import Speech
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(os)
import os
#endif

/// SpeechRecognizer 実装: Apple SpeechAnalyzer / SpeechTranscriber（固定要件・macOS 26+）。
/// 本質: オンデバイス完結（音声を外部送信しない）。volatile/finalized を区別して流す。
///
/// フロー（infrastructure 内に閉じ、domain は AudioFrame / RecognitionResult のみ見る）:
///   AudioFrame → AudioFormatConverter で bestAvailableAudioFormat へ変換 → AnalyzerInput を
///   AsyncStream で SpeechAnalyzer に供給 → SpeechTranscriber.results（volatile/finalized）を
///   RecognitionResult に正規化して AsyncThrowingStream で流す。
///
/// 実機検証項目（SPEC 手動検証項目）:
/// - オンデバイスで実際に文字化するか。volatile/finalized が想定通り流れるか。
/// - bestAvailableAudioFormat への変換が正しいか（タップ native format 依存）。
/// - 言語モデル未インストール時の AssetInstallationRequest フロー。
public final class SpeechAnalyzerAdapter: SpeechRecognizer, @unchecked Sendable {
    private let converter = AudioFormatConverter()
    #if canImport(os)
    private let log = AppLog.logger(.analyzer)
    #endif

    // finalize() で SpeechAnalyzer を終端するための状態（直近の transcribe セッション）。
    private let stateLock = NSLock()
    #if canImport(Speech)
    @available(macOS 26.0, *)
    private final class Session {
        let analyzer: SpeechAnalyzer
        let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
        init(analyzer: SpeechAnalyzer, inputContinuation: AsyncStream<AnalyzerInput>.Continuation) {
            self.analyzer = analyzer
            self.inputContinuation = inputContinuation
        }
    }
    private var _session: Any?

    @available(macOS 26.0, *)
    private func currentSession() -> Session? {
        stateLock.lock(); defer { stateLock.unlock() }
        return _session as? Session
    }

    private func setSession(_ value: Any?) {
        stateLock.lock(); defer { stateLock.unlock() }
        _session = value
    }
    #endif

    public init() {}

    public func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncThrowingStream<RecognitionResult, Error> {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            return makeStream(audio: audio, locale: locale)
        }
        #endif
        // SpeechAnalyzer 非対応環境（固定要件外）。即終端する。
        return AsyncThrowingStream { $0.finish() }
    }

    /// 停止時: SpeechAnalyzer を finalize し、残りの volatile を確定へ昇格して最後の finalized を
    /// 流し切ってからストリームを終端する（ADR-3「停止時 finalize→flush で取りこぼさない」）。
    public func finalize() async {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            let session = currentSession()
            guard let session else { return }
            // 入力ストリームを終端し、SpeechAnalyzer に「これ以上入力は来ない」ことを伝える。
            session.inputContinuation.finish()
            // 最後の確定結果まで流し切る（results ストリームが終端し、transcribe 側の for await が抜ける）。
            try? await session.analyzer.finalizeAndFinishThroughEndOfInput()
        }
        #endif
    }

    #if canImport(Speech)
    @available(macOS 26.0, *)
    private func makeStream(audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncThrowingStream<RecognitionResult, Error> {
        let converter = self.converter
        #if canImport(os)
        let log = self.log
        #endif
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transcriber = SpeechTranscriber(
                        locale: locale,
                        transcriptionOptions: [],
                        reportingOptions: [.volatileResults],
                        attributeOptions: []
                    )
                    #if canImport(os)
                    log.info("transcribe start locale=\(locale.identifier, privacy: .public)")
                    #endif

                    // 言語モデルが未インストールなら導入を要求する（オンデバイス）。
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                        #if canImport(os)
                        log.info("asset installation required -> downloading")
                        #endif
                        try await request.downloadAndInstall()
                        #if canImport(os)
                        log.info("asset installation finished")
                        #endif
                    } else {
                        #if canImport(os)
                        log.info("asset already installed (no installation request)")
                        #endif
                    }

                    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                        #if canImport(os)
                        log.error("bestAvailableAudioFormat returned nil")
                        #endif
                        continuation.finish(throwing: NotImplemented.speechAnalyzer)
                        return
                    }
                    #if canImport(os)
                    log.info(
                        """
                        analyzerFormat: sampleRate=\(analyzerFormat.sampleRate) \
                        channels=\(analyzerFormat.channelCount) \
                        interleaved=\(analyzerFormat.isInterleaved) \
                        commonFormat=\(analyzerFormat.commonFormat.rawValue)
                        """
                    )
                    #endif

                    // SpeechAnalyzer へ AnalyzerInput を供給する入力ストリーム。
                    let (inputStream, inputCont) = AsyncStream.makeStream(of: AnalyzerInput.self)
                    let analyzer = SpeechAnalyzer(modules: [transcriber])

                    // finalize() から終端できるよう session を保持。
                    let session = Session(analyzer: analyzer, inputContinuation: inputCont)
                    self.setSession(session)

                    try await analyzer.start(inputSequence: inputStream)

                    // 観測カウンタ（feeder/results は非リアルタイムタスクなので atomic で共有）。
                    let feedReceived = Atomic<Int>(0)
                    let feedConverted = Atomic<Int>(0)
                    let feedDropped = Atomic<Int>(0)

                    // 入力供給タスク: AudioFrame → 変換 → AVAudioPCMBuffer → AnalyzerInput。
                    let feeder = Task {
                        for await frame in audio {
                            let n = feedReceived.add(1, ordering: .relaxed).newValue
                            // タップ native フォーマット（例: 48kHz/2ch/float32/インターリーブ）の AudioFrame を
                            // その native フォーマットの AVAudioPCMBuffer に詰め、analyzerFormat（Int16 等）へ
                            // 直接変換する。floatChannelData 前提をやめ Int16 ターゲットでも破棄しない（バグ修正）。
                            let sourceFormat = AudioFormatConverter.avFormat(from: frame.format)
                            let sourceBuffer = sourceFormat.flatMap {
                                AudioFormatConverter.pcmBuffer(from: frame, format: $0)
                            }
                            if let sourceBuffer,
                               let buffer = converter.convertBuffer(sourceBuffer, to: analyzerFormat) {
                                inputCont.yield(AnalyzerInput(buffer: buffer))
                                let y = feedConverted.add(1, ordering: .relaxed).newValue
                                #if canImport(os)
                                if y <= 3 {
                                    log.info("feeder yielded buffer #\(y): inSamples=\(frame.samples.count) bufferFrames=\(buffer.frameLength)")
                                }
                                #endif
                            } else {
                                // 仮説 C 判定: 変換で nil（drop）になったフレーム数。
                                let d = feedDropped.add(1, ordering: .relaxed).newValue
                                #if canImport(os)
                                if d <= 3 {
                                    log.error("feeder DROPPED frame #\(n) (pcmBuffer==nil): inSamples=\(frame.samples.count) declaredChannels=\(frame.format.channelCount)")
                                }
                                #endif
                            }
                        }
                        // 入力ストリーム（audio）が終端したら analyzer 入力も終端する。
                        inputCont.finish()
                        #if canImport(os)
                        log.info(
                            "feeder summary: received=\(feedReceived.load(ordering: .relaxed)) converted=\(feedConverted.load(ordering: .relaxed)) dropped=\(feedDropped.load(ordering: .relaxed))"
                        )
                        #endif
                    }

                    // 結果受信: volatile/finalized を RecognitionResult に正規化して流す。
                    var volatileResults = 0
                    var finalizedResults = 0
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        let start = result.range.start.seconds
                        let end = result.range.end.seconds
                        let range: ClosedRange<Double>? = (start.isFinite && end.isFinite && end >= start) ? start...end : nil
                        #if canImport(os)
                        if result.isFinal {
                            finalizedResults += 1
                            log.info("results received finalized #\(finalizedResults) len=\(text.count)")
                        } else {
                            volatileResults += 1
                            if volatileResults <= 3 || volatileResults % 20 == 0 {
                                log.info("results received volatile #\(volatileResults) len=\(text.count)")
                            }
                        }
                        #endif
                        continuation.yield(RecognitionResult(text: text, isFinal: result.isFinal, range: range))
                    }
                    feeder.cancel()
                    #if canImport(os)
                    log.info("results stream ended: volatile=\(volatileResults) finalized=\(finalizedResults)")
                    #endif
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    // 認識/タップの異常終了は error 終端で domain に伝播する（error 状態遷移を駆動）。
                    continuation.finish(throwing: error)
                }
                self.setSession(nil)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #endif
}
