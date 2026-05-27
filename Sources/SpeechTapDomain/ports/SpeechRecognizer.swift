import Foundation

/// PCM ストリームをオンデバイス文字化し結果を返す境界（実装は infrastructure: SpeechAnalyzer）。
/// 本質: オンデバイス完結（外部送信しない）。volatile/finalized を区別して流す。
///
/// ストリームは `AsyncThrowingStream` とし、認識/タップが異常終了した場合は error で終端する。
/// domain（TranscriptionService）はこの error 終端を error 状態への遷移トリガとして扱う（取りこぼし防止と区別）。
public protocol SpeechRecognizer: Sendable {
    func transcribe(_ audio: AsyncStream<AudioFrame>, locale: Locale) -> AsyncThrowingStream<RecognitionResult, Error>

    /// 停止時に呼ぶ。残っている volatile を最終確定（finalized）へ昇格し、
    /// 未配信の finalized を全て流し切ってからストリームを正常終端する。
    /// ADR-3「停止時に finalize→flush で最後の確定結果まで取りこぼさない」を境界で担保する。
    func finalize() async
}
