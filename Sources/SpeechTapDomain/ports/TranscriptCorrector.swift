import Foundation

/// transcript を LLM 等で校正する境界。
///
/// 実装は infrastructure に置く。失敗してもメイン transcript 保存を巻き戻してはならない。
public protocol TranscriptCorrector: Sendable {
    func correct(rawTranscript: String) async throws -> String
}
