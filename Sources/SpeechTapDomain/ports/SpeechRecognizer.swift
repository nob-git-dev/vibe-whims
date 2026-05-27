import Foundation

/// PCM ストリームをオンデバイス文字化し結果を返す境界（実装は infrastructure: SpeechAnalyzer）。
/// 本質: オンデバイス完結（外部送信しない）。volatile/finalized を区別して流す。
public protocol SpeechRecognizer: Sendable {
    func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncStream<RecognitionResult>
}
