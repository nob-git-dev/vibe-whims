import AppKit

/// 文字起こし結果を表示する簡易ウィンドウ（表示のみ・ロジックを持たない）。
/// finalized（確定）を上に積み、volatile（暫定）を末尾にグレー表示する。
///
/// 機能C（ピン / ADR にせず実装メモで方針記録）:
/// - タイトルバー右側に NSTitlebarAccessoryViewController でピンボタンを配置。
/// - `window.level = .floating / .normal` をトグル。
/// - **状態は永続化しない**（isRestorable = false、UserDefaults 等にも保存しない）。
/// - 再起動ごとに OFF で開始する（固定要件）。
///
/// 機能A（表示クリア / ADR-6）:
/// - StopFlowCoordinator が停止後に「表示クリアしますか？」ダイアログを出し、Yes なら `clear()` を呼ぶ。
/// - `clear()` はウィンドウ上の文字列だけクリアし、保存経路（メインファイル）には触れない。
final class TranscriptWindowController: NSWindowController {
    private let textView = NSTextView()

    /// ピン状態（永続化しない・機能C）。
    private(set) var isPinned: Bool = false
    private var pinButton: NSButton?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpeechTap 文字起こし"
        window.center()
        // 機能C: 状態を OS の自動復元に乗せない（再起動ごとに OFF を構造的に担保）。
        window.isRestorable = false
        self.init(window: window)

        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        textView.isEditable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: 14)
        scroll.documentView = textView
        window.contentView?.addSubview(scroll)

        installPinAccessory(on: window)
    }

    /// 表示更新（presentation のみ。保存は domain/infra 側で完結している）。
    /// finalized には DisplayPipeline で翻訳済みの**表示用テキスト**が渡され、
    /// volatile は常に原文（ADR-5: volatile は翻訳しない）。
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

    /// 機能A: 表示用テキストをクリアする（メインファイル `transcript.txt` には触れない）。
    /// StopFlowCoordinator が「表示クリアしますか？」ダイアログで Yes を選んだ時に呼ぶ。
    func clear() {
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    // MARK: - 機能C: ピン（最前面トグル・非永続化）

    private func installPinAccessory(on window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        let button = NSButton(image: pinImage(pinned: false), target: self, action: #selector(togglePin))
        button.bezelStyle = .accessoryBarAction
        button.setButtonType(.toggle)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = "ウィンドウを最前面に固定（ピン）"
        button.keyEquivalent = "p"
        button.keyEquivalentModifierMask = [.command]
        button.frame = NSRect(x: 0, y: 0, width: 28, height: 22)
        self.pinButton = button

        let container = NSView(frame: button.frame)
        container.addSubview(button)
        accessory.view = container
        accessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(accessory)
    }

    /// ピン状態をトグルする。`window.level` を切り替え、ボタンの見た目も更新する。
    /// 単体テスト可能（NSWindow があれば実行できる）。
    @objc func togglePin() {
        isPinned.toggle()
        window?.level = isPinned ? .floating : .normal
        pinButton?.image = pinImage(pinned: isPinned)
        pinButton?.state = isPinned ? .on : .off
    }

    private func pinImage(pinned: Bool) -> NSImage {
        let name = pinned ? "pin.fill" : "pin"
        return NSImage(systemSymbolName: name, accessibilityDescription: pinned ? "ピン解除" : "ピン")
            ?? NSImage(named: NSImage.statusAvailableName)!
    }
}
