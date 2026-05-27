import AppKit
import SpeechTapDomain
import SpeechTapInfrastructure

/// メニューバー常駐アプリのエントリ。Composition Root として infrastructure Adapter を組み立て、
/// domain の TranscriptionService に注入する（ADR-2）。UI は表示・入出力のみでロジックを持たない。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    // Composition Root が生成する具体実装（ここだけが infrastructure を知る）。
    private let appEnumerator: AppEnumerator = RunningAppProvider()
    private var service: TranscriptionService?
    private var config: LoadedConfig?

    // UI 状態。
    private var apps: [TargetApp] = []
    private var selectedApp: AppId?
    private var latestStateText: String = "idle"
    private var transcriptWindow: TranscriptWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // 設定の外部化（直書きしない）。実設定 → バンドル既定の順に解決する。
        do {
            let cfg = try loadConfig()
            self.config = cfg
            self.selectedApp = cfg.targetAppId

            // domain に port を注入（domain は具体型を知らない＝逆依存なし）。
            let service = TranscriptionService(
                audioSource: ProcessTapAudioSource(),
                recognizer: SpeechAnalyzerAdapter(),
                permissionGate: AudioCapturePermission(),
                sink: FileTranscriptSink(outputPath: cfg.outputPath),
                locale: cfg.locale,
                // domain の観測点を os.Logger 実装で注入（domain は OS 非依存のまま可観測化）。
                eventLogger: OSEventLogger()
            )
            self.service = service

            // 状態変化を UI に反映する（ViewModel 相当の薄い橋渡し）。
            Task {
                await service.setStateChangeHandler { [weak self] state in
                    DispatchQueue.main.async {
                        self?.onStateChanged(state)
                    }
                }
            }
        } catch {
            latestStateText = "config error: \(error)"
            presentConfigError(error)
        }

        rebuildMenu()
        Task { await refreshApps() }
    }

    // MARK: - 設定解決

    private func loadConfig() throws -> LoadedConfig {
        // 優先: ~/.config/speech-tap/config.conf（実値）。無ければバンドル同梱の既定。
        let fm = FileManager.default
        let userPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/speech-tap/config.conf")
        if fm.fileExists(atPath: userPath) {
            return try ConfigLoader.load(from: userPath)
        }
        if let bundled = Bundle.main.path(forResource: "config.default", ofType: "conf") {
            return try ConfigLoader.load(from: bundled)
        }
        throw ConfigLoader.ConfigError.fileNotFound("config.conf / bundled config.default.conf")
    }

    // MARK: - メニューバー UI

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🎙"
        item.button?.toolTip = "SpeechTap"
        item.menu = menu
        self.statusItem = item
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let statusMenuItem = NSMenuItem(title: "状態: \(latestStateText)", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        // 対象アプリ選択（一覧）。
        let pickerHeader = NSMenuItem(title: "対象アプリを選択", action: nil, keyEquivalent: "")
        pickerHeader.isEnabled = false
        menu.addItem(pickerHeader)

        if apps.isEmpty {
            let empty = NSMenuItem(title: "  (一覧を取得中…)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for app in apps {
                let mi = NSMenuItem(title: app.name, action: #selector(selectApp(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = app.id.rawValue
                mi.state = (app.id == selectedApp) ? .on : .off
                menu.addItem(mi)
            }
        }
        let refresh = NSMenuItem(title: "アプリ一覧を更新", action: #selector(refreshAppsAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())

        // 開始 / 停止。
        let start = NSMenuItem(title: "文字化を開始", action: #selector(startAction), keyEquivalent: "s")
        start.target = self
        start.isEnabled = (selectedApp != nil)
        menu.addItem(start)

        let stop = NSMenuItem(title: "文字化を停止", action: #selector(stopAction), keyEquivalent: "t")
        stop.target = self
        menu.addItem(stop)
        menu.addItem(.separator())

        let showWindow = NSMenuItem(title: "文字起こしを表示", action: #selector(showTranscriptAction), keyEquivalent: "w")
        showWindow.target = self
        menu.addItem(showWindow)

        let quit = NSMenuItem(title: "終了", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - アクション

    @objc private func selectApp(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let id = AppId(raw)
        selectedApp = id
        Task { await service?.select(app: id) }
        rebuildMenu()
    }

    @objc private func refreshAppsAction() {
        Task { await refreshApps() }
    }

    private func refreshApps() async {
        let list = (try? await appEnumerator.listAudioCapableApps()) ?? []
        await MainActor.run {
            self.apps = list
            self.rebuildMenu()
        }
    }

    @objc private func startAction() {
        guard let service, let app = selectedApp else {
            presentInfo("対象アプリを選択してください。")
            return
        }
        Task { await service.start(app: app) }
    }

    @objc private func stopAction() {
        Task { await service?.stop() }
    }

    @objc private func showTranscriptAction() {
        if transcriptWindow == nil {
            transcriptWindow = TranscriptWindowController()
        }
        transcriptWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateTranscriptWindow()
    }

    @objc private func quitAction() {
        Task {
            await service?.stop()
            await MainActor.run { NSApp.terminate(nil) }
        }
    }

    // MARK: - 状態反映

    private func onStateChanged(_ state: SessionState) {
        switch state {
        case .idle: latestStateText = "idle"
        case .selected: latestStateText = "選択済み"
        case .checkingPermission: latestStateText = "権限確認中"
        case .awaitingPermission:
            latestStateText = "権限未許可"
            presentPermissionGuidance()
        case .running: latestStateText = "文字化中"
        case .stopping: latestStateText = "停止処理中"
        case .stopped: latestStateText = "停止"
        case .error(let msg): latestStateText = "エラー: \(msg)"
        }
        rebuildMenu()
        updateTranscriptWindow()
    }

    private func updateTranscriptWindow() {
        guard let service, let window = transcriptWindow else { return }
        Task {
            let store = await service.transcriptStore
            let finalized = store.finalizedText
            let volatile = store.volatileText
            await MainActor.run {
                window.update(finalized: finalized, volatile: volatile)
            }
        }
    }

    // MARK: - 案内ダイアログ（権限・設定）

    private func presentPermissionGuidance() {
        let alert = NSAlert()
        alert.messageText = "音声キャプチャの許可が必要です"
        alert.informativeText = "対象アプリの音声を文字化するには、音声キャプチャを許可してください。"
            + "未許可のままでは音声取得を開始しません。システム設定 > プライバシーとセキュリティ から許可できます。"
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "閉じる")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func presentConfigError(_ error: Error) {
        presentInfo("設定の読み込みに失敗しました: \(error)")
    }

    private func presentInfo(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "SpeechTap"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
