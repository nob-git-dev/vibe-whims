import Foundation
import SpeechTapDomain

/// Config 実装: config ファイル（.env / config.yaml）読み込み（固定要件: 設定の外部化）。
/// targetAppId / locale / outputPath をコード直書きせず外部ファイルから供給する。
///
/// 最小実装として KEY=VALUE 形式（.env 風）をパースする。
/// 対応キー: TARGET_APP_ID / LOCALE / OUTPUT_PATH。
public struct LoadedConfig: Config, Sendable {
    public let targetAppId: AppId?
    public let locale: Locale
    public let outputPath: String
    public let llmCorrection: LLMCorrectionConfig?

    public init(
        targetAppId: AppId?,
        locale: Locale,
        outputPath: String,
        llmCorrection: LLMCorrectionConfig? = nil
    ) {
        self.targetAppId = targetAppId
        self.locale = locale
        self.outputPath = outputPath
        self.llmCorrection = llmCorrection
    }
}

public enum ConfigLoader {
    public enum ConfigError: Error {
        case fileNotFound(String)
        case missingRequiredKey(String)
        case invalidValue(String, String)
    }

    /// .env 風（KEY=VALUE、# はコメント）の設定ファイルを読み込む。
    public static func load(from path: String) throws -> LoadedConfig {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ConfigError.fileNotFound(path)
        }
        var dict: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            dict[key] = value
        }

        // 出力先は必須（保存先が無いと確定結果を保存できない）。
        guard let output = dict["OUTPUT_PATH"], !output.isEmpty else {
            throw ConfigError.missingRequiredKey("OUTPUT_PATH")
        }
        let appId = dict["TARGET_APP_ID"].flatMap { $0.isEmpty ? nil : AppId($0) }
        let localeId = dict["LOCALE"] ?? "ja-JP"
        let llmCorrection = try loadLLMCorrection(from: dict)

        return LoadedConfig(
            targetAppId: appId,
            locale: Locale(identifier: localeId),
            outputPath: output,
            llmCorrection: llmCorrection
        )
    }

    private static func loadLLMCorrection(from dict: [String: String]) throws -> LLMCorrectionConfig? {
        let enabled = try parseBool(dict["LLM_CORRECTION_ENABLED"] ?? "false", key: "LLM_CORRECTION_ENABLED")
        guard enabled else { return nil }

        guard let baseURLValue = dict["LLM_API_BASE_URL"], !baseURLValue.isEmpty else {
            throw ConfigError.missingRequiredKey("LLM_API_BASE_URL")
        }
        guard let baseURL = URL(string: baseURLValue), baseURL.scheme != nil, baseURL.host != nil else {
            throw ConfigError.invalidValue("LLM_API_BASE_URL", baseURLValue)
        }
        guard let model = dict["LLM_MODEL"], !model.isEmpty else {
            throw ConfigError.missingRequiredKey("LLM_MODEL")
        }

        let apiKey = dict["LLM_API_KEY"].flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let temperature = try parseDouble(
            dict["LLM_TEMPERATURE"] ?? "0",
            key: "LLM_TEMPERATURE"
        )
        let timeoutSeconds = try parseDouble(
            dict["LLM_TIMEOUT_SECONDS"] ?? "180",
            key: "LLM_TIMEOUT_SECONDS"
        )
        guard timeoutSeconds > 0 else {
            throw ConfigError.invalidValue("LLM_TIMEOUT_SECONDS", "\(timeoutSeconds)")
        }
        let maxTokens = try parseOptionalInt(dict["LLM_MAX_TOKENS"], key: "LLM_MAX_TOKENS")
        if let maxTokens, maxTokens <= 0 {
            throw ConfigError.invalidValue("LLM_MAX_TOKENS", "\(maxTokens)")
        }
        let disableThinking = try parseBool(
            dict["LLM_DISABLE_THINKING"] ?? "false",
            key: "LLM_DISABLE_THINKING"
        )

        return LLMCorrectionConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            temperature: temperature,
            timeoutSeconds: timeoutSeconds,
            maxTokens: maxTokens,
            disableThinking: disableThinking
        )
    }

    private static func parseBool(_ value: String, key: String) throws -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "on": return true
        case "false", "0", "no", "off", "": return false
        default: throw ConfigError.invalidValue(key, value)
        }
    }

    private static func parseDouble(_ value: String, key: String) throws -> Double {
        guard let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ConfigError.invalidValue(key, value)
        }
        return parsed
    }

    private static func parseOptionalInt(_ value: String?, key: String) throws -> Int? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard let parsed = Int(trimmed) else {
            throw ConfigError.invalidValue(key, trimmed)
        }
        return parsed
    }
}
