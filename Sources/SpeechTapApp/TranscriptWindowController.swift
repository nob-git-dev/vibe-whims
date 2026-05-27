import AppKit

/// 文字起こし結果を表示する簡易ウィンドウ（表示のみ・ロジックを持たない）。
/// finalized（確定）を上に積み、volatile（暫定）を末尾にグレー表示する。
final class TranscriptWindowController: NSWindowController {
    private let textView = NSTextView()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpeechTap 文字起こし"
        window.center()
        self.init(window: window)

        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        textView.isEditable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: 14)
        scroll.documentView = textView
        window.contentView?.addSubview(scroll)
    }

    /// 表示更新（presentation のみ。保存は domain/infra 側で完結している）。
    func update(finalized: String, volatile: String) {
        let storage = NSMutableAttributedString(
            string: finalized,
            attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 14)]
        )
        if !volatile.isEmpty {
            let sep = finalized.isEmpty ? "" : "\n"
            storage.append(NSAttributedString(
                string: sep + volatile,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 14)]
            ))
        }
        textView.textStorage?.setAttributedString(storage)
        textView.scrollToEndOfDocument(nil)
    }
}
