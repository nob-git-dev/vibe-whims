import Foundation

/// LLM transcript 校正の設定値。
///
/// 既定では無効。enabled のときだけ transcript text が configured API に送られる。
/// API key / model / endpoint は外部設定から注入し、コードに直書きしない。
public struct LLMCorrectionConfig: Sendable, Equatable {
    public let baseURL: URL
    public let apiKey: String?
    public let model: String
    public let temperature: Double
    public let timeoutSeconds: TimeInterval
    public let maxTokens: Int?
    public let disableThinking: Bool

    public init(
        baseURL: URL,
        apiKey: String?,
        model: String,
        temperature: Double = 0.0,
        timeoutSeconds: TimeInterval = 180,
        maxTokens: Int? = nil,
        disableThinking: Bool = false
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.timeoutSeconds = timeoutSeconds
        self.maxTokens = maxTokens
        self.disableThinking = disableThinking
    }
}
