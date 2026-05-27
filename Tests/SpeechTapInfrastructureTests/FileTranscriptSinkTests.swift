import Testing
import Foundation
@testable import SpeechTapInfrastructure
import SpeechTapDomain

/// FileTranscriptSink の本質: 確定（finalized）結果を取りこぼさず保存する。
/// 保存失敗を黙殺しない（エラーを伝播）。親ディレクトリが無くても作成して書き込む。
/// infrastructure だが OS 非依存に近く、一時ディレクトリでテスト可能。
struct FileTranscriptSinkTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("speechtap-sink-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("親ディレクトリが存在しなくても作成してから保存する（取りこぼし防止）")
    func createsParentDirectoryAndWrites() async throws {
        let dir = tempDir()
        // 親ディレクトリはまだ存在しない（ネスト含む）。
        let output = dir.appendingPathComponent("nested/out.txt")
        defer { try? FileManager.default.removeItem(at: dir) }

        let sink = FileTranscriptSink(outputPath: output.path)
        try await sink.append(TranscriptSegment(text: "確定その1。", range: nil))
        try await sink.append(TranscriptSegment(text: "確定その2。", range: nil))
        try await sink.flush()

        let saved = try String(contentsOf: output, encoding: .utf8)
        #expect(saved == "確定その1。\n確定その2。\n")
    }

    @Test("flush を 2 回行うと既存内容に追記される（停止時 flush で取りこぼさない）")
    func appendsAcrossFlushes() async throws {
        let dir = tempDir()
        let output = dir.appendingPathComponent("out.txt")
        defer { try? FileManager.default.removeItem(at: dir) }

        let sink = FileTranscriptSink(outputPath: output.path)
        try await sink.append(TranscriptSegment(text: "一回目。", range: nil))
        try await sink.flush()
        try await sink.append(TranscriptSegment(text: "二回目。", range: nil))
        try await sink.flush()

        let saved = try String(contentsOf: output, encoding: .utf8)
        #expect(saved == "一回目。\n二回目。\n")
    }

    @Test("保存できない場合はエラーを伝播し黙殺しない（保存失敗を握り潰さない）")
    func propagatesWriteError() async {
        // 既存のファイルをディレクトリとして指定すると書き込みに失敗する（作成済みディレクトリへ write）。
        let dir = tempDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // 出力先パスを「ディレクトリそのもの」にすると data.write が失敗する。
        let sink = FileTranscriptSink(outputPath: dir.path)

        await #expect(throws: (any Error).self) {
            try await sink.append(TranscriptSegment(text: "失敗するはず。", range: nil))
            try await sink.flush()
        }
    }

    @Test("出力先パスの ~ を展開して保存する（チルダ展開）")
    func expandsTilde() async throws {
        // ホーム配下にユニークな一時ディレクトリを作り、~ 形式のパスで指定する。
        let unique = "speechtap-tilde-\(UUID().uuidString)"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let absDir = home.appendingPathComponent(unique, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: absDir) }

        let tildePath = "~/\(unique)/out.txt"
        let sink = FileTranscriptSink(outputPath: tildePath)
        try await sink.append(TranscriptSegment(text: "チルダ展開。", range: nil))
        try await sink.flush()

        // 展開先（ホーム配下の実パス）に書かれていること。カレント配下の "~" には作らない。
        let expanded = absDir.appendingPathComponent("out.txt")
        let saved = try String(contentsOf: expanded, encoding: .utf8)
        #expect(saved == "チルダ展開。\n")
        #expect(FileManager.default.fileExists(atPath: "~/\(unique)/out.txt") == false)
    }
}
