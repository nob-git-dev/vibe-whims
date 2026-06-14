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
public final class SpeechAnalyzerAdapter: SpeechRecognizer, RecognitionCapabilities, @unchecked Sendable {
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

    private final class AnalyzerTimingProbe: @unchecked Sendable {
        struct Snapshot {
            let firstAudioWallTime: Double
            let latestCaptureWallTime: Double
            let fedAudioSeconds: Double
            let fedFrameCount: Int
        }

        private let lock = NSLock()
        private var firstAudioWallTime: Double?
        private var latestCaptureWallTime: Double?
        private var fedAudioSeconds: Double = 0
        private var fedFrameCount: Int = 0

        func recordFedFrame(captureWallTime: Double, durationSeconds: Double) -> Snapshot {
            lock.lock()
            defer { lock.unlock() }
            if firstAudioWallTime == nil {
                firstAudioWallTime = captureWallTime
            }
            latestCaptureWallTime = captureWallTime
            fedAudioSeconds += max(0, durationSeconds)
            fedFrameCount += 1
            return Snapshot(
                firstAudioWallTime: firstAudioWallTime ?? captureWallTime,
                latestCaptureWallTime: latestCaptureWallTime ?? captureWallTime,
                fedAudioSeconds: fedAudioSeconds,
                fedFrameCount: fedFrameCount
            )
        }

        func snapshot() -> Snapshot? {
            lock.lock()
            defer { lock.unlock() }
            guard let firstAudioWallTime, let latestCaptureWallTime else {
                return nil
            }
            return Snapshot(
                firstAudioWallTime: firstAudioWallTime,
                latestCaptureWallTime: latestCaptureWallTime,
                fedAudioSeconds: fedAudioSeconds,
                fedFrameCount: fedFrameCount
            )
        }
    }

    private static func audioLevel(samples: [Float]) -> (rmsDBFS: Double, peakDBFS: Double) {
        guard !samples.isEmpty else { return (-120, -120) }
        var sumSquares: Double = 0
        var peak: Double = 0
        for sample in samples {
            let value = Double(sample)
            let magnitude = abs(value)
            sumSquares += value * value
            if magnitude > peak {
                peak = magnitude
            }
        }
        let rms = sqrt(sumSquares / Double(samples.count))
        let floor = 0.000_001
        return (
            rmsDBFS: 20 * log10(max(rms, floor)),
            peakDBFS: 20 * log10(max(peak, floor))
        )
    }

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

    // MARK: - RecognitionCapabilities（ADR-7）

    /// 認識器がオンデバイスで対応する言語ロケール一覧を返す（ADR-7）。
    /// `SpeechTranscriber.supportedLocales` を Foundation の `[Locale]` に正規化して返す（OS 型を漏らさない）。
    /// 取得不能環境（SpeechAnalyzer 非対応・空）では妥当な既定 `[ja-JP, en-US]` を返し、空表示を避ける。
    public func supportedLocales() async -> [Locale] {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            // TODO(実機検証): `SpeechTranscriber.supportedLocales` の正確なシグネチャ（static/instance/async）と
            //                返却型は macOS 26 実機で確定する（SPEC「ADR-7 で実機検証する事項」）。
            //                現状の SDK では static プロパティとして `[Locale]` を返すため、それを正規化する。
            let locales = await SpeechTranscriber.supportedLocales
            let normalized = locales.map { Locale(identifier: $0.identifier(.bcp47)) }
            if !normalized.isEmpty { return normalized }
        }
        #endif
        // 取得不能・未対応時の既定（presentation 側で最低限の言語を出すための安全側フォールバック）。
        return SpeechAnalyzerAdapter.defaultLocales
    }

    /// 取得不能時に最低限提示する既定ロケール（日本語 / 英語）。
    static let defaultLocales: [Locale] = [
        Locale(identifier: "ja-JP"),
        Locale(identifier: "en-US")
    ]

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
                    let timingProbe = AnalyzerTimingProbe()

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
                                let sampleRate = max(buffer.format.sampleRate, 1)
                                let durationSeconds = Double(buffer.frameLength) / sampleRate
                                let timing = timingProbe.recordFedFrame(
                                    captureWallTime: frame.timestamp,
                                    durationSeconds: durationSeconds
                                )
                                #if canImport(os)
                                if y <= 3 || y % 100 == 0 {
                                    let level = Self.audioLevel(samples: frame.samples)
                                    log.info(
                                        """
                                        feedTiming frame=\(y) inSamples=\(frame.samples.count) \
                                        bufferFrames=\(buffer.frameLength) \
                                        bufferDuration=\(String(format: "%.3f", durationSeconds), privacy: .public) \
                                        fedAudioSeconds=\(String(format: "%.3f", timing.fedAudioSeconds), privacy: .public) \
                                        rmsDBFS=\(String(format: "%.1f", level.rmsDBFS), privacy: .public) \
                                        peakDBFS=\(String(format: "%.1f", level.peakDBFS), privacy: .public) \
                                        captureWall=\(String(format: "%.3f", frame.timestamp), privacy: .public)
                                        """
                                    )
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
                        let receivedWallTime = Date().timeIntervalSinceReferenceDate
                        let text = String(result.text.characters)
                        let start = result.range.start.seconds
                        let end = result.range.end.seconds
                        let range: ClosedRange<Double>? = (start.isFinite && end.isFinite && end >= start) ? start...end : nil
                        #if canImport(os)
                        let resultKind: String
                        let resultIndex: Int
                        if result.isFinal {
                            finalizedResults += 1
                            resultKind = "final"
                            resultIndex = finalizedResults
                        } else {
                            volatileResults += 1
                            resultKind = "volatile"
                            resultIndex = volatileResults
                        }
                        let shouldLogTiming = result.isFinal || volatileResults <= 20 || volatileResults % 10 == 0
                        if shouldLogTiming {
                            if let range, let timing = timingProbe.snapshot() {
                                let rangeStart = range.lowerBound
                                let rangeEnd = range.upperBound
                                let latencyFromStart = receivedWallTime - (timing.firstAudioWallTime + rangeStart)
                                let latencyFromEnd = receivedWallTime - (timing.firstAudioWallTime + rangeEnd)
                                log.info(
                                    """
                                    resultTiming kind=\(resultKind, privacy: .public) index=\(resultIndex) \
                                    chars=\(text.count) \
                                    rangeStart=\(String(format: "%.3f", rangeStart), privacy: .public) \
                                    rangeEnd=\(String(format: "%.3f", rangeEnd), privacy: .public) \
                                    rangeDuration=\(String(format: "%.3f", rangeEnd - rangeStart), privacy: .public) \
                                    latencyFromRangeStart=\(String(format: "%.3f", latencyFromStart), privacy: .public) \
                                    latencyFromRangeEnd=\(String(format: "%.3f", latencyFromEnd), privacy: .public) \
                                    fedAudioSeconds=\(String(format: "%.3f", timing.fedAudioSeconds), privacy: .public) \
                                    fedFrames=\(timing.fedFrameCount)
                                    """
                                )
                            } else {
                                log.info(
                                    "resultTiming kind=\(resultKind, privacy: .public) index=\(resultIndex) chars=\(text.count) noRangeOrNoAudioTiming=true"
                                )
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
