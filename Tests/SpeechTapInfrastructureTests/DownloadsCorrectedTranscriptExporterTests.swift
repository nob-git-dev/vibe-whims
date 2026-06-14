import Testing
import Foundation
@testable import SpeechTapInfrastructure
import SpeechTapDomain

struct DownloadsCorrectedTranscriptExporterTests {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechtap-corrected-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("校正済み transcript を corrected サフィックス付きで書き出す")
    func exportsCorrectedTranscript() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exporter = DownloadsCorrectedTranscriptExporter(outputDirectory: dir)
        let stoppedAt = DownloadsSessionExporterTests.localDate(
            year: 2026,
            month: 6,
            day: 4,
            hour: 7,
            minute: 17,
            second: 40
        )
        let session = TranscriptSession(
            segments: [TranscriptSegment(text: "原文")],
            startedAt: stoppedAt.addingTimeInterval(-60),
            stoppedAt: stoppedAt
        )

        let url = try await exporter.export(correctedText: "校正済み本文。", originalSession: session)

        #expect(url.lastPathComponent == "speech-tap-20260604-071740-corrected.txt")
        #expect(try String(contentsOf: url, encoding: .utf8) == "校正済み本文。\n")
    }

    @Test("corrected ファイルも衝突時は -2, -3 で上書きしない")
    func collisionAppendsSuffix() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exporter = DownloadsCorrectedTranscriptExporter(outputDirectory: dir)
        let stoppedAt = DownloadsSessionExporterTests.localDate(
            year: 2026,
            month: 6,
            day: 4,
            hour: 7,
            minute: 17,
            second: 40
        )
        let session = TranscriptSession(
            segments: [TranscriptSegment(text: "原文")],
            startedAt: stoppedAt.addingTimeInterval(-60),
            stoppedAt: stoppedAt
        )

        let url1 = try await exporter.export(correctedText: "first", originalSession: session)
        let url2 = try await exporter.export(correctedText: "second", originalSession: session)
        let url3 = try await exporter.export(correctedText: "third", originalSession: session)

        #expect(url1.lastPathComponent == "speech-tap-20260604-071740-corrected.txt")
        #expect(url2.lastPathComponent == "speech-tap-20260604-071740-corrected-2.txt")
        #expect(url3.lastPathComponent == "speech-tap-20260604-071740-corrected-3.txt")
        #expect(try String(contentsOf: url1, encoding: .utf8) == "first\n")
        #expect(try String(contentsOf: url2, encoding: .utf8) == "second\n")
        #expect(try String(contentsOf: url3, encoding: .utf8) == "third\n")
    }
}
