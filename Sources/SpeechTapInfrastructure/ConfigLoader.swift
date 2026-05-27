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

    public init(targetAppId: AppId?, locale: Locale, outputPath: String) {
        self.targetAppId = targetAppId
        self.locale = locale
        self.outputPath = outputPath
    }
}

public enum ConfigLoader {
    public enum ConfigError: Error {
        case fileNotFound(String)
        case missingRequiredKey(String)
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

        return LoadedConfig(
            targetAppId: appId,
            locale: Locale(identifier: localeId),
            outputPath: output
        )
    }
}
