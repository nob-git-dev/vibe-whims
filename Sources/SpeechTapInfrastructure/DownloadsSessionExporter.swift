import Foundation
import SpeechTapDomain

/// SessionExporter 実装: `~/Downloads/speech-tap-YYYYMMDD-HHmmss[-N].txt` を生成する（機能A / ADR-6）。
///
/// 契約（ADR-6 / SessionExporter）:
/// - ファイル名: `stoppedAt` ベース / ローカルタイム / 24 時間表記。
/// - 秒精度の衝突時は `-2`, `-3`, ... を拡張子の直前に付与（**上書き禁止**）。
/// - 保存内容: 1 セグメント = 1 行（末尾 `\n`）/ UTF-8 / 原文のみ（翻訳結果は含めない）。
/// - 既存 `transcript.txt` の append 経路（FileTranscriptSink）には**一切触れない**（副経路）。
///
/// 既定の出力先は `FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)`。
/// テスト容易性のため init で任意のディレクトリを指定できる（テストは一時ディレクトリを渡す）。
public actor DownloadsSessionExporter: SessionExporter {
    private let outputDirectory: URL

    /// 既定: ~/Downloads。
    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            self.outputDirectory = url
        } else {
            self.outputDirectory = home.appendingPathComponent("Downloads", isDirectory: true)
        }
    }

    /// テスト用: 任意の出力ディレクトリを指定する。
    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    public func export(_ session: TranscriptSession) async throws -> URL {
        // 親ディレクトリ未存在時は作成（書き出し前提）。
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let baseName = Self.baseFileName(for: session.stoppedAt)
        let url = uniqueURL(baseName: baseName, ext: "txt")

        // 1 セグメント = 1 行で結合し UTF-8 で書き出す（既存 FileTranscriptSink の見え方と同等）。
        let body = session.segments.map { $0.text + "\n" }.joined()
        let data = Data(body.utf8)
        // 上書き禁止: uniqueURL で既存ファイルを避けてから write。
        try data.write(to: url, options: [.withoutOverwriting])
        return url
    }

    /// `speech-tap-YYYYMMDD-HHmmss`（ローカルタイム / 24h）のベース名を組む。
    private static func baseFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX") // 数値書式の固定
        formatter.timeZone = TimeZone.current               // ローカルタイム（ADR-6）
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "speech-tap-\(formatter.string(from: date))"
    }

    /// 既存ファイルと衝突しない URL を返す（`-2`, `-3`, ... のサフィックスを拡張子の直前に付与）。
    private func uniqueURL(baseName: String, ext: String) -> URL {
        let primary = outputDirectory.appendingPathComponent("\(baseName).\(ext)")
        if !FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }
        var n = 2
        while true {
            let candidate = outputDirectory.appendingPathComponent("\(baseName)-\(n).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            n += 1
        }
    }
}
