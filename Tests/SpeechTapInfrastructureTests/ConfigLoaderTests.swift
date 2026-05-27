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
    }

    @Test("LOCALE 省略時は ja-JP を既定にする")
    func defaultsLocale() throws {
        let path = try writeTempConfig("OUTPUT_PATH=/tmp/o.txt")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let config = try ConfigLoader.load(from: path)
        #expect(config.locale.identifier == "ja-JP")
        #expect(config.targetAppId == nil)
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
}
