import Testing
import Foundation
@testable import SpeechTapInfrastructure
import SpeechTapDomain

/// 機能A（ADR-6）: DownloadsSessionExporter の本質テスト。
///
/// 本質:
/// - セッション分の確定テキストを独立 1 ファイルとして書き出す（1 セグメント = 1 行 / UTF-8）。
/// - ファイル名規則: `speech-tap-YYYYMMDD-HHmmss.txt`（stoppedAt ベース / ローカルタイム / 24h）。
/// - 秒精度衝突時は `-2`, `-3`, ... のサフィックスを拡張子の直前に付与し**上書き禁止**。
/// - 既存メインファイル（FileTranscriptSink）の挙動には一切触れない（別経路として独立）。
struct DownloadsSessionExporterTests {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechtap-export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("セッション分の確定テキストを 1 セグメント = 1 行で UTF-8 書き出す（タイムスタンプ付きファイル名）")
    func exportsSegmentsAsLines() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exporter = DownloadsSessionExporter(outputDirectory: dir)
        let startedAt = Self.localDate(year: 2026, month: 5, day: 31, hour: 15, minute: 30, second: 0)
        let stoppedAt = Self.localDate(year: 2026, month: 5, day: 31, hour: 15, minute: 30, second: 45)
        let session = TranscriptSession(
            segments: [
                TranscriptSegment(text: "一行目。", range: nil),
                TranscriptSegment(text: "二行目。", range: nil),
                TranscriptSegment(text: "三行目。", range: nil)
            ],
            startedAt: startedAt,
            stoppedAt: stoppedAt
        )

        let url = try await exporter.export(session)

        // ファイル名は speech-tap-YYYYMMDD-HHmmss.txt（stoppedAt ベース・ローカルタイム）。
        #expect(url.lastPathComponent == "speech-tap-20260531-153045.txt")
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved == "一行目。\n二行目。\n三行目。\n")
    }

    @Test("秒精度の衝突時は -2, -3 のサフィックスで回避し既存ファイルを上書きしない")
    func collisionAppendsSuffix() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exporter = DownloadsSessionExporter(outputDirectory: dir)
        let stoppedAt = Self.localDate(year: 2026, month: 5, day: 31, hour: 15, minute: 30, second: 45)
        let mkSession: (String) -> TranscriptSession = { text in
            TranscriptSession(
                segments: [TranscriptSegment(text: text, range: nil)],
                startedAt: stoppedAt.addingTimeInterval(-60),
                stoppedAt: stoppedAt
            )
        }

        let url1 = try await exporter.export(mkSession("first"))
        let url2 = try await exporter.export(mkSession("second"))
        let url3 = try await exporter.export(mkSession("third"))

        #expect(url1.lastPathComponent == "speech-tap-20260531-153045.txt")
        #expect(url2.lastPathComponent == "speech-tap-20260531-153045-2.txt")
        #expect(url3.lastPathComponent == "speech-tap-20260531-153045-3.txt")

        // 既存ファイルは上書きされない（最初の内容が保たれている）。
        let saved1 = try String(contentsOf: url1, encoding: .utf8)
        #expect(saved1 == "first\n")
        let saved2 = try String(contentsOf: url2, encoding: .utf8)
        #expect(saved2 == "second\n")
        let saved3 = try String(contentsOf: url3, encoding: .utf8)
        #expect(saved3 == "third\n")
    }

    @Test("空セッション（segments 0 件）でも空ファイルが作成される（上書き禁止は維持）")
    func emptySessionWritesEmptyFile() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exporter = DownloadsSessionExporter(outputDirectory: dir)
        let stoppedAt = Self.localDate(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5)
        let session = TranscriptSession(
            segments: [],
            startedAt: stoppedAt.addingTimeInterval(-10),
            stoppedAt: stoppedAt
        )

        let url = try await exporter.export(session)
        #expect(url.lastPathComponent == "speech-tap-20260102-030405.txt")
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved == "")
    }

    // MARK: - ヘルパ

    /// テストで再現可能なローカルタイム Date を組み立てる（テスト環境タイムゾーン依存。
    /// exporter は同じカレントタイムゾーンでファイル名を組むため、テスト内で整合する）。
    static func localDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        c.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}
