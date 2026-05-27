import Foundation
import SpeechTapDomain
#if canImport(Speech)
import Speech
#endif
#if canImport(AVFoundation)
import AVFoundation
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
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transcriber = SpeechTranscriber(
                        locale: locale,
                        transcriptionOptions: [],
                        reportingOptions: [.volatileResults],
                        attributeOptions: []
                    )

                    // 言語モデルが未インストールなら導入を要求する（オンデバイス）。
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                        try await request.downloadAndInstall()
                    }

                    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                        continuation.finish(throwing: NotImplemented.speechAnalyzer)
                        return
                    }
                    let targetFormat = AudioFormatConverter.streamFormat(from: analyzerFormat)

                    // SpeechAnalyzer へ AnalyzerInput を供給する入力ストリーム。
                    let (inputStream, inputCont) = AsyncStream.makeStream(of: AnalyzerInput.self)
                    let analyzer = SpeechAnalyzer(modules: [transcriber])

                    // finalize() から終端できるよう session を保持。
                    let session = Session(analyzer: analyzer, inputContinuation: inputCont)
                    self.setSession(session)

                    try await analyzer.start(inputSequence: inputStream)

                    // 入力供給タスク: AudioFrame → 変換 → AVAudioPCMBuffer → AnalyzerInput。
                    let feeder = Task {
                        for await frame in audio {
                            let converted = converter.convert(frame, to: targetFormat)
                            if let buffer = AudioFormatConverter.pcmBuffer(from: converted, format: analyzerFormat) {
                                inputCont.yield(AnalyzerInput(buffer: buffer))
                            }
                        }
                        // 入力ストリーム（audio）が終端したら analyzer 入力も終端する。
                        inputCont.finish()
                    }

                    // 結果受信: volatile/finalized を RecognitionResult に正規化して流す。
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        let start = result.range.start.seconds
                        let end = result.range.end.seconds
                        let range: ClosedRange<Double>? = (start.isFinite && end.isFinite && end >= start) ? start...end : nil
                        continuation.yield(RecognitionResult(text: text, isFinal: result.isFinal, range: range))
                    }
                    feeder.cancel()
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
