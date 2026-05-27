import Foundation
import SpeechTapDomain

/// TranscriptSink 実装: ファイル保存。出力先パスは Config 由来（直書きしない）。
/// 確定（finalized）セグメントのみが append される。停止時 flush で確実に書き切る。
///
/// この実装は OS API（FileManager / FileHandle）への素直な接触のみ。
/// ここでは薄いアダプタとして最小実装する。actor で内部状態をシリアライズする。
public actor FileTranscriptSink: TranscriptSink {
    private let outputURL: URL
    private var buffer: [String] = []

    public init(outputPath: String) {
        // 出力先パスの ~ を展開する（URL(fileURLWithPath:) は展開しないため、
        // 設定例の ~/Documents/... がカレント配下の "~" になる事故を防ぐ）。
        let expanded = (outputPath as NSString).expandingTildeInPath
        self.outputURL = URL(fileURLWithPath: expanded)
    }

    public func append(_ segment: TranscriptSegment) async throws {
        buffer.append(segment.text)
    }

    public func flush() async throws {
        let toWrite = buffer.joined(separator: "\n")
        guard !toWrite.isEmpty else { return }
        let data = Data((toWrite + "\n").utf8)

        // 親ディレクトリが存在しない場合は作成してから書き込む（確定結果の取りこぼし防止）。
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        // 既存内容に追記する形でファイルに書き出す。保存失敗は黙殺せずエラーを伝播する。
        if FileManager.default.fileExists(atPath: outputURL.path) {
            let handle = try FileHandle(forWritingTo: outputURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: outputURL, options: .atomic)
        }
        buffer.removeAll()
    }
}
