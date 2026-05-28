import Foundation
import SpeechTapDomain

/// TranscriptSink 実装: ファイル保存（ADR-4: クラッシュ耐性のための即時 append）。
///
/// 契約（ADR-4 / SPEC「### Port セマンティクス」）:
/// - `append(_:)`: 受信した時点で**末尾追記して durably に永続化**する。
///   メモリバッファに溜めて停止時に flush で書き出す実装は禁止（クラッシュで確定済みも失うため）。
/// - `flush()`: 「保留中があれば確実に書き出す安全網」。即時 append のため実質 no-op に近いが
///   契約として残す（domain の停止フロー finalize → drain → flush を壊さない）。
///
/// 実装方針:
/// - 親ディレクトリ未存在時は append 側で作成（flush を呼ばずとも書ける必要があるため）。
/// - 追記モードで毎回開閉する単純な実装（文字化レートでは I/O コストは無視できる・堅牢性重視）。
/// - 各セグメント末尾に改行を付与（旧 flush の `joined(separator: "\n") + "\n"` と同等の見え方）。
/// - 書き込み失敗は throws で伝播（黙殺しない）。
/// - actor で append がシリアライズされ順序保持される。
public actor FileTranscriptSink: TranscriptSink {
    private let outputURL: URL

    public init(outputPath: String) {
        // 出力先パスの ~ を展開する（URL(fileURLWithPath:) は展開しないため、
        // 設定例の ~/Documents/... がカレント配下の "~" になる事故を防ぐ）。
        let expanded = (outputPath as NSString).expandingTildeInPath
        self.outputURL = URL(fileURLWithPath: expanded)
    }

    /// 確定セグメントを即時にファイル末尾へ追記する（ADR-4）。
    /// flush を待たず、その時点でディスクに反映される（クラッシュ時にも確定済み分は残る）。
    public func append(_ segment: TranscriptSegment) async throws {
        let data = Data((segment.text + "\n").utf8)

        // 親ディレクトリが未存在なら作成（flush に頼らず append 単独で書ける必要がある）。
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            // 既存ファイルへ末尾追記（POSIX append 相当、短い書き込みは原子的に期待できる）。
            let handle = try FileHandle(forWritingTo: outputURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            // 初回 append: ファイル作成 + 内容書き込み。上書き系（.atomic 等）は使わず単純な write。
            try data.write(to: outputURL)
        }
    }

    /// 安全網: append が即時永続化するため通常は no-op。契約として残す（ADR-4）。
    public func flush() async throws {
        // 即時 append 設計のため保留中は存在しない。契約上の no-op。
    }
}
