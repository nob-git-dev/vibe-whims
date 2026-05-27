import Foundation
import SpeechTapDomain

/// SpeechRecognizer 実装: Apple SpeechAnalyzer / SpeechTranscriber（固定要件・macOS 26+）。
/// 本質: オンデバイス完結（音声を外部送信しない）。volatile/finalized を区別して流す。
///
/// TODO（実機・実音声検証が必要なため未実装。SPEC 手動検証項目参照）:
/// - SpeechTranscriber.bestAvailableAudioFormat(compatibleWith:) で要求フォーマット取得
/// - AudioFrame → AVAudioPCMBuffer → AnalyzerInput へ変換し AsyncStream で yield
/// - SpeechAnalyzer の結果（volatile / finalized）を RecognitionResult に正規化して流す
/// - 認識/タップが異常終了した場合は continuation.finish(throwing:) で error 終端する
///   （domain 側で error 状態へ遷移しリソース解放する経路を駆動する）
/// - ネットワーク送信コードを一切持たないことでオンデバイス完結を担保
public final class SpeechAnalyzerAdapter: SpeechRecognizer, @unchecked Sendable {
    public init() {}

    public func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncThrowingStream<RecognitionResult, Error> {
        // TODO: SpeechAnalyzer に AnalyzerInput を供給し、認識結果を RecognitionResult に変換して流す。
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    /// 停止時に SpeechAnalyzer を finalize し、残りの volatile を確定へ昇格して最後の finalized を
    /// 流し切ってからストリームを終端する（ADR-3「停止時 finalize→flush で取りこぼさない」）。
    public func finalize() async {
        // TODO: SpeechAnalyzer.finalizeAndFinish(through:) 等で残りの確定結果を流し切り、
        //       transcribe の continuation を正常終端する。
    }
}
