import Foundation
import SpeechTapDomain

public struct HTTPTransportResponse: Sendable, Equatable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPTransportResponse
}

public struct URLSessionHTTPTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> HTTPTransportResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        return HTTPTransportResponse(statusCode: statusCode, data: data)
    }
}

public enum OpenAICompatibleTranscriptCorrectorError: Error, Equatable {
    case invalidEndpoint(URL)
    case httpStatus(Int, String)
    case emptyChoices
    case emptyCorrectedText
}

/// OpenAI 互換 `/chat/completions` API を使う transcript 校正器。
///
/// API base URL / model / key は config から注入する。既定では AppDelegate が生成しないため、
/// transcript text は `LLM_CORRECTION_ENABLED=true` のときだけ外部 API に送られる。
public actor OpenAICompatibleTranscriptCorrector: TranscriptCorrector {
    private let config: LLMCorrectionConfig
    private let transport: HTTPTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(config: LLMCorrectionConfig, transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.config = config
        self.transport = transport
    }

    public func correct(rawTranscript: String) async throws -> String {
        let prompt = TranscriptCorrectionPrompt(rawTranscript: rawTranscript)
        let request = try makeRequest(prompt: prompt)
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw OpenAICompatibleTranscriptCorrectorError.httpStatus(
                response.statusCode,
                String(data: response.data, encoding: .utf8) ?? ""
            )
        }
        let decoded = try decoder.decode(ChatCompletionResponse.self, from: response.data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenAICompatibleTranscriptCorrectorError.emptyCorrectedText
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAICompatibleTranscriptCorrectorError.emptyCorrectedText
        }
        return trimmed
    }

    public func makeRequest(prompt: TranscriptCorrectionPrompt) throws -> URLRequest {
        guard let endpoint = chatCompletionsEndpoint(baseURL: config.baseURL) else {
            throw OpenAICompatibleTranscriptCorrectorError.invalidEndpoint(config.baseURL)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body = ChatCompletionRequest(
            model: config.model,
            messages: [
                ChatCompletionRequest.Message(role: "system", content: prompt.system),
                ChatCompletionRequest.Message(role: "user", content: prompt.user)
            ],
            temperature: config.temperature,
            maxTokens: config.maxTokens,
            stream: false,
            chatTemplateKwargs: config.disableThinking ? ChatTemplateKwargs(enableThinking: false) : nil
        )
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func chatCompletionsEndpoint(baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.isEmpty {
            components.path = "/chat/completions"
        } else {
            components.path = "/\(normalizedPath)/chat/completions"
        }
        return components.url
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int?
    let stream: Bool
    let chatTemplateKwargs: ChatTemplateKwargs?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case chatTemplateKwargs = "chat_template_kwargs"
    }

    struct Message: Encodable, Equatable {
        let role: String
        let content: String
    }
}

private struct ChatTemplateKwargs: Encodable {
    let enableThinking: Bool

    enum CodingKeys: String, CodingKey {
        case enableThinking = "enable_thinking"
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}
