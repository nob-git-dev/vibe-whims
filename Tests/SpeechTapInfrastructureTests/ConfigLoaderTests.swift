import Testing
import Foundation
@testable import SpeechTapInfrastructure
import SpeechTapDomain

/// ConfigLoader の本質: 設定（対象アプリ識別子・認識言語・出力先）を外部ファイルから読み、
/// コード直書きしないこと（固定要件: 設定の外部化）。
struct ConfigLoaderTests {

    private func writeTempConfig(_ contents: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("speechtap-test-\(UUID().uuidString).env")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @Test(".env 風ファイルから targetAppId / locale / outputPath を読み込む")
    func loadsAllKeys() throws {
        let path = try writeTempConfig("""
        # speech-tap config
        TARGET_APP_ID=com.example.meet
        LOCALE=en-US
        OUTPUT_PATH=/tmp/out.txt
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try ConfigLoader.load(from: path)
        #expect(config.targetAppId == AppId("com.example.meet"))
        #expect(config.locale.identifier == "en-US")
        #expect(config.outputPath == "/tmp/out.txt")
        #expect(config.llmCorrection == nil)
    }

    @Test("LOCALE 省略時は ja-JP を既定にする")
    func defaultsLocale() throws {
        let path = try writeTempConfig("OUTPUT_PATH=/tmp/o.txt")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let config = try ConfigLoader.load(from: path)
        #expect(config.locale.identifier == "ja-JP")
        #expect(config.targetAppId == nil)
        #expect(config.llmCorrection == nil)
    }

    @Test("OUTPUT_PATH が無いとエラー（保存先が無いと確定結果を保存できない）")
    func missingOutputThrows() throws {
        let path = try writeTempConfig("LOCALE=ja-JP")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(throws: ConfigLoader.ConfigError.self) {
            _ = try ConfigLoader.load(from: path)
        }
    }

    @Test("存在しないファイルはエラー")
    func missingFileThrows() {
        #expect(throws: ConfigLoader.ConfigError.self) {
            _ = try ConfigLoader.load(from: "/nonexistent/speechtap-\(UUID().uuidString).env")
        }
    }

    @Test("LLM 校正を有効にすると OpenAI 互換 API 設定を読み込む")
    func loadsLLMCorrectionConfigWhenEnabled() throws {
        let path = try writeTempConfig("""
        OUTPUT_PATH=/tmp/out.txt
        LLM_CORRECTION_ENABLED=true
        LLM_API_BASE_URL=http://192.168.3.18:30000/v1
        LLM_API_KEY=local-key
        LLM_MODEL=qwen3.5-122b
        LLM_TEMPERATURE=0.1
        LLM_TIMEOUT_SECONDS=240
        LLM_MAX_TOKENS=32768
        LLM_DISABLE_THINKING=true
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try ConfigLoader.load(from: path)

        let llm = try #require(config.llmCorrection)
        #expect(llm.baseURL.absoluteString == "http://192.168.3.18:30000/v1")
        #expect(llm.apiKey == "local-key")
        #expect(llm.model == "qwen3.5-122b")
        #expect(llm.temperature == 0.1)
        #expect(llm.timeoutSeconds == 240)
        #expect(llm.maxTokens == 32768)
        #expect(llm.disableThinking == true)
    }

    @Test("LLM 校正が無効なら LLM_API_BASE_URL / LLM_MODEL が空でも通る")
    func disabledLLMCorrectionDoesNotRequireAPIConfig() throws {
        let path = try writeTempConfig("""
        OUTPUT_PATH=/tmp/out.txt
        LLM_CORRECTION_ENABLED=false
        LLM_API_BASE_URL=
        LLM_MODEL=
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try ConfigLoader.load(from: path)

        #expect(config.llmCorrection == nil)
    }

    @Test("LLM 校正が有効で base URL が無い場合はエラー")
    func enabledLLMCorrectionRequiresBaseURL() throws {
        let path = try writeTempConfig("""
        OUTPUT_PATH=/tmp/out.txt
        LLM_CORRECTION_ENABLED=true
        LLM_MODEL=qwen3.5-122b
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(throws: ConfigLoader.ConfigError.self) {
            _ = try ConfigLoader.load(from: path)
        }
    }

    @Test("LLM_MAX_TOKENS が空なら未指定として扱う")
    func emptyLLMMaxTokensIsNil() throws {
        let path = try writeTempConfig("""
        OUTPUT_PATH=/tmp/out.txt
        LLM_CORRECTION_ENABLED=true
        LLM_API_BASE_URL=http://192.168.3.18:30000/v1
        LLM_MODEL=qwen3.5-122b
        LLM_MAX_TOKENS=
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try ConfigLoader.load(from: path)

        let llm = try #require(config.llmCorrection)
        #expect(llm.maxTokens == nil)
    }

    @Test("LLM_MAX_TOKENS が正の整数でなければエラー")
    func invalidLLMMaxTokensThrows() throws {
        let path = try writeTempConfig("""
        OUTPUT_PATH=/tmp/out.txt
        LLM_CORRECTION_ENABLED=true
        LLM_API_BASE_URL=http://192.168.3.18:30000/v1
        LLM_MODEL=qwen3.5-122b
        LLM_MAX_TOKENS=0
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(throws: ConfigLoader.ConfigError.self) {
            _ = try ConfigLoader.load(from: path)
        }
    }
}
