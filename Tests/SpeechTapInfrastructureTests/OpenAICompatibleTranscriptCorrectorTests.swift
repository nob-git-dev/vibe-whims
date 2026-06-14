import Testing
import Foundation
@testable import SpeechTapInfrastructure
import SpeechTapDomain

struct OpenAICompatibleTranscriptCorrectorTests {

    @Test("OpenAI 互換 chat/completions に校正 prompt を送り、本文だけを返す")
    func sendsChatCompletionRequestAndReturnsContent() async throws {
        let transport = FakeHTTPTransport(
            response: HTTPTransportResponse(
                statusCode: 200,
                data: Data("""
                {"choices":[{"message":{"role":"assistant","content":"校正済み本文です。\\n"}}]}
                """.utf8)
            )
        )
        let config = LLMCorrectionConfig(
            baseURL: URL(string: "http://localhost:30000/v1")!,
            apiKey: "local-key",
            model: "qwen3.5-122b",
            temperature: 0,
            timeoutSeconds: 90,
            maxTokens: 32768,
            disableThinking: true
        )
        let corrector = OpenAICompatibleTranscriptCorrector(config: config, transport: transport)

        let corrected = try await corrector.correct(rawTranscript: "校正まえ のぶんしょう")

        #expect(corrected == "校正済み本文です。")
        let request = try #require(await transport.lastRequest())
        #expect(request.url?.absoluteString == "http://localhost:30000/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 90)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer local-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "qwen3.5-122b")
        #expect(json["temperature"] as? Double == 0)
        #expect(json["max_tokens"] as? Int == 32768)
        #expect(json["stream"] as? Bool == false)
        #expect(json["extra_body"] == nil)
        let chatTemplateKwargs = try #require(json["chat_template_kwargs"] as? [String: Any])
        #expect(chatTemplateKwargs["enable_thinking"] as? Bool == false)

        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect((messages[0]["content"] as? String)?.contains("要約しない") == true)
        #expect(messages[1]["role"] as? String == "user")
        #expect((messages[1]["content"] as? String)?.contains("<asr_transcript>") == true)
        #expect((messages[1]["content"] as? String)?.contains("校正まえ のぶんしょう") == true)
    }

    @Test("API key が空の場合 Authorization header を付けない")
    func omitsAuthorizationHeaderWhenAPIKeyIsEmpty() async throws {
        let transport = FakeHTTPTransport(
            response: HTTPTransportResponse(
                statusCode: 200,
                data: Data(#"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#.utf8)
            )
        )
        let config = LLMCorrectionConfig(
            baseURL: URL(string: "http://localhost:30000/v1/")!,
            apiKey: nil,
            model: "local-model"
        )
        let corrector = OpenAICompatibleTranscriptCorrector(config: config, transport: transport)

        _ = try await corrector.correct(rawTranscript: "raw")

        let request = try #require(await transport.lastRequest())
        #expect(request.url?.absoluteString == "http://localhost:30000/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("HTTP エラーは校正失敗として投げる")
    func httpErrorThrows() async throws {
        let transport = FakeHTTPTransport(
            response: HTTPTransportResponse(
                statusCode: 500,
                data: Data("server error".utf8)
            )
        )
        let config = LLMCorrectionConfig(
            baseURL: URL(string: "http://localhost:30000/v1")!,
            apiKey: nil,
            model: "local-model"
        )
        let corrector = OpenAICompatibleTranscriptCorrector(config: config, transport: transport)

        await #expect(throws: OpenAICompatibleTranscriptCorrectorError.self) {
            _ = try await corrector.correct(rawTranscript: "raw")
        }
    }

    @Test("reasoning だけで content が null の応答は校正本文として扱わない")
    func nullContentThrows() async throws {
        let transport = FakeHTTPTransport(
            response: HTTPTransportResponse(
                statusCode: 200,
                data: Data(#"{"choices":[{"message":{"role":"assistant","content":null,"reasoning":"thinking only"}}]}"#.utf8)
            )
        )
        let config = LLMCorrectionConfig(
            baseURL: URL(string: "http://localhost:30000/v1")!,
            apiKey: nil,
            model: "local-model"
        )
        let corrector = OpenAICompatibleTranscriptCorrector(config: config, transport: transport)

        await #expect(throws: OpenAICompatibleTranscriptCorrectorError.self) {
            _ = try await corrector.correct(rawTranscript: "raw")
        }
    }

    @Test("maxTokens と thinking 抑制が未指定なら provider-specific body を送らない")
    func omitsOptionalProviderParametersByDefault() async throws {
        let transport = FakeHTTPTransport(
            response: HTTPTransportResponse(
                statusCode: 200,
                data: Data(#"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#.utf8)
            )
        )
        let config = LLMCorrectionConfig(
            baseURL: URL(string: "http://localhost:30000/v1")!,
            apiKey: nil,
            model: "openai-compatible-model"
        )
        let corrector = OpenAICompatibleTranscriptCorrector(config: config, transport: transport)

        _ = try await corrector.correct(rawTranscript: "raw")

        let request = try #require(await transport.lastRequest())
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["max_tokens"] == nil)
        #expect(json["chat_template_kwargs"] == nil)
    }
}

private actor FakeHTTPTransport: HTTPTransport {
    private let response: HTTPTransportResponse
    private var requests: [URLRequest] = []

    init(response: HTTPTransportResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> HTTPTransportResponse {
        requests.append(request)
        return response
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }
}
