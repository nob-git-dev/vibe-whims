import Foundation
import SpeechTapDomain

/// SpeechRecognizer 実装: Apple SpeechAnalyzer / SpeechTranscriber（固定要件・macOS 26+）。
/// 本質: オンデバイス完結（音声を外部送信しない）。volatile/finalized を区別して流す。
///
/// TODO（実機・実音声検証が必要なため未実装。SPEC 手動検証項目参照）:
/// - SpeechTranscriber.bestAvailableAudioFormat(compatibleWith:) で要求フォーマット取得
/// - AudioFrame → AVAudioPCMBuffer → AnalyzerInput へ変換し AsyncStream で yield
/// - SpeechAnalyzer の結果（volatile / finalized）を RecognitionResult に正規化して流す
/// - ネットワーク送信コードを一切持たないことでオンデバイス完結を担保
public final class SpeechAnalyzerAdapter: SpeechRecognizer, @unchecked Sendable {
    public init() {}

    public func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncStream<RecognitionResult> {
        // TODO: SpeechAnalyzer に AnalyzerInput を供給し、認識結果を RecognitionResult に変換して流す。
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
