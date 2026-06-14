import Foundation

/// LLM 校正済み transcript を通常の原文複本とは別ファイルとして書き出す境界。
public protocol CorrectedTranscriptExporter: Sendable {
    func export(correctedText: String, originalSession: TranscriptSession) async throws -> URL
}
