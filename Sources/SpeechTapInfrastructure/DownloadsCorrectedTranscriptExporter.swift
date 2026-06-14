import Foundation
import SpeechTapDomain

/// LLM 校正済み transcript を Downloads に別ファイルとして書き出す。
///
/// 通常の `DownloadsSessionExporter` は原文複本専用なので流用しない。
/// corrected ファイルは `speech-tap-YYYYMMDD-HHmmss-corrected[-N].txt` として保存する。
public actor DownloadsCorrectedTranscriptExporter: CorrectedTranscriptExporter {
    private let outputDirectory: URL

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            self.outputDirectory = url
        } else {
            self.outputDirectory = home.appendingPathComponent("Downloads", isDirectory: true)
        }
    }

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    public func export(correctedText: String, originalSession: TranscriptSession) async throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let baseName = Self.baseFileName(for: originalSession.stoppedAt)
        let url = uniqueURL(baseName: baseName, ext: "txt")
        let body = correctedText.hasSuffix("\n") ? correctedText : correctedText + "\n"
        try Data(body.utf8).write(to: url, options: [.withoutOverwriting])
        return url
    }

    private static func baseFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "speech-tap-\(formatter.string(from: date))-corrected"
    }

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
