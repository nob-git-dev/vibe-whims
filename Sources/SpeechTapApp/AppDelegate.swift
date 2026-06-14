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

    // 機能B（ADR-5）: 表示パイプライン（保存パスとは独立）。
    private var displayPipeline: DisplayPipeline?
    // 機能A（ADR-6）: 停止フロー駆動。
    private var stopFlowCoordinator: StopFlowCoordinator?
    // 翻訳/エクスポート関連の状態通知（メニュー「状態」行に表示）。
    private var translationStatus: String = ""

    // ADR-7: 認識言語選択。RecognitionCapabilities で取得した対応ロケール一覧と現在選択中ロケール。
    private var recognitionCaps: RecognitionCapabilities?
    private var supportedLocales: [Locale] = []
    private var selectedLocale: Locale?

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
            // ADR-7: config の LOCALE を初期選択（既定値）として尊重する（設定外部化を維持）。
            self.selectedLocale = cfg.locale

            // ADR-7: SpeechAnalyzerAdapter は SpeechRecognizer と RecognitionCapabilities を兼ねる。
            // 同一インスタンスを domain（認識）と presentation（対応ロケール照会）で共用する。
            let analyzerAdapter = SpeechAnalyzerAdapter()
            self.recognitionCaps = analyzerAdapter

            // domain に port を注入（domain は具体型を知らない＝逆依存なし）。
            // 注: TranscriptionService のコンストラクタは ADR-5/6/7 でも不変
            //     （翻訳・エクスポートはサービス外で組み立てる / 認識言語は setRecognitionLocale で実行時上書き）。
            let service = TranscriptionService(
                audioSource: ProcessTapAudioSource(),
                recognizer: analyzerAdapter,
                permissionGate: AudioCapturePermission(),
                sink: FileTranscriptSink(outputPath: cfg.outputPath),
                // ADR-7: 初期選択の既定値。メニュー選択で setRecognitionLocale が次回 start から上書きする。
                locale: cfg.locale,
                // domain の観測点を os.Logger 実装で注入（domain は OS 非依存のまま可観測化）。
                eventLogger: OSEventLogger()
            )
            self.service = service

            // 機能B / ADR-5: 表示パイプライン（言語検出 → 必要なら翻訳 → 表示用テキスト）。
            // 保存経路（TranscriptSink）には触れない（経路分離・固定要件）。
            let translator = AppleTranslator()
            let languageDetector = AppleLanguageDetector()
            self.displayPipeline = DisplayPipeline(
                detector: languageDetector,
                translator: translator,
                targetLocale: Locale(identifier: "ja-JP")
            )

            // 機能A / ADR-6: 停止フロー駆動（Downloads 複本書き出し → 表示クリア確認）。
            // TranscriptionService.stop() の API は不変、`.stopped` 遷移を観測して駆動する。
            let exporter = DownloadsSessionExporter()
            let transcriptCorrector = cfg.llmCorrection.map { OpenAICompatibleTranscriptCorrector(config: $0) }
            let correctedExporter = cfg.llmCorrection.map { _ in DownloadsCorrectedTranscriptExporter() }
            // window はまだ作っていないので nil 始まりで OK（最初に表示要求が来た時に作る）。
            let coordinator = StopFlowCoordinator(
                exporter: exporter,
                transcriptCorrector: transcriptCorrector,
                correctedExporter: correctedExporter,
                service: service,
                window: nil,
                onStatusMessage: { [weak self] message in
                    DispatchQueue.main.async {
                        self?.translationStatus = message
                        self?.rebuildMenu()
                    }
                }
            )
            self.stopFlowCoordinator = coordinator

            // 状態変化を UI に反映する（ViewModel 相当の薄い橋渡し）。
            Task {
                await service.setStateChangeHandler { [weak self] state in
                    DispatchQueue.main.async {
                        self?.onStateChanged(state)
                        // 機能A: .stopped で Downloads 複本書き出し + 表示クリア確認を起動。
                        self?.stopFlowCoordinator?.handleStateChange(state)
                    }
                }
                // running 中にストリーミングで届く volatile/finalized を表示へリアルタイム反映する。
                // 状態変化時だけでなく、結果更新のたびに updateTranscriptWindow を呼ぶ（Fix2）。
                await service.setTranscriptUpdateHandler { [weak self] in
                    DispatchQueue.main.async {
                        self?.updateTranscriptWindow()
                    }
                }
            }
        } catch {
            latestStateText = "config error: \(error)"
            presentConfigError(error)
        }

        rebuildMenu()
        Task { await refreshApps() }
        // ADR-7: 起動時に対応ロケール一覧を取得し、「認識言語」サブメニューを構築する。
        Task { await refreshSupportedLocales() }
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
        item.menu = menu
        self.statusItem = item
        updateStatusItemIcon(recording: false)
    }

    private func updateStatusItemIcon(recording: Bool) {
        guard let button = statusItem?.button else { return }
        button.toolTip = recording ? "SpeechTap - REC" : "SpeechTap"
        button.imagePosition = .imageOnly
        button.title = ""

        let symbolName = recording ? "mic.fill" : "mic"
        if let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: recording ? "SpeechTap recording" : "SpeechTap"
        ) {
            image.isTemplate = true
            button.attributedTitle = NSAttributedString(string: "")
            button.image = image
            button.contentTintColor = recording ? .systemRed : .labelColor
            return
        }

        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = NSAttributedString(
            string: recording ? "REC" : "🎙",
            attributes: [
                .foregroundColor: recording ? NSColor.systemRed : NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
        )
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let statusMenuItem = NSMenuItem(title: "状態: \(latestStateText)", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        if !translationStatus.isEmpty {
            // 機能A/B 関連の通知（翻訳パック未取得・複本書き出し結果等）。黙って空表示にしない。
            let extra = NSMenuItem(title: "  \(translationStatus)", action: nil, keyEquivalent: "")
            extra.isEnabled = false
            menu.addItem(extra)
        }
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

        // ADR-7: 認識言語サブメニュー。選択は次回 start から有効（実行中の即時切替は行わない）。
        let languageItem = NSMenuItem(title: "認識言語", action: nil, keyEquivalent: "")
        languageItem.submenu = buildLanguageSubmenu()
        menu.addItem(languageItem)
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

    // MARK: - 認識言語サブメニュー（ADR-7）

    /// メニューに出す認識言語の一覧を組み立てる。
    /// 最低限「日本語 / 英語」を先頭に提示し、RecognitionCapabilities から取得できた「その他」を続ける
    /// （重複は除去）。取得できない環境でも空表示にしない（受け入れ条件）。
    private func languageMenuLocales() -> [Locale] {
        let defaults = [Locale(identifier: "ja-JP"), Locale(identifier: "en-US")]
        var seen = Set<String>()
        var result: [Locale] = []
        for loc in defaults + supportedLocales {
            let key = loc.identifier
            if seen.insert(key).inserted {
                result.append(loc)
            }
        }
        return result
    }

    private func buildLanguageSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let current = selectedLocale?.identifier
        for loc in languageMenuLocales() {
            let title = localizedLanguageName(loc)
            let item = NSMenuItem(title: title, action: #selector(selectLocale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = loc.identifier
            item.state = (loc.identifier == current) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    /// ロケールの表示名（その言語の現地名 + 識別子）。
    private func localizedLanguageName(_ locale: Locale) -> String {
        let display = Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
        return "\(display)（\(locale.identifier)）"
    }

    @objc private func selectLocale(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let locale = Locale(identifier: raw)
        selectedLocale = locale
        // 次回 start から有効（実行中の即時切替は行わない・ADR-7）。
        Task { await service?.setRecognitionLocale(locale) }
        rebuildMenu()
    }

    private func refreshApps() async {
        let list = (try? await appEnumerator.listAudioCapableApps()) ?? []
        await MainActor.run {
            self.apps = list
            self.rebuildMenu()
        }
    }

    /// ADR-7: 認識器が対応する言語ロケール一覧を取得し、「認識言語」サブメニューを再構築する。
    /// 取得できない場合でも presentation 側で最低限「日本語 / 英語」を提示する（空表示にしない）。
    private func refreshSupportedLocales() async {
        let locales = await recognitionCaps?.supportedLocales() ?? []
        await MainActor.run {
            self.supportedLocales = locales
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
            let window = TranscriptWindowController()
            transcriptWindow = window
            // 機能A: 停止フローからのクリア要求を届けるため、coordinator に window を登録する。
            stopFlowCoordinator?.setWindow(window)
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
        var recording = false
        switch state {
        case .idle: latestStateText = "idle"
        case .selected: latestStateText = "選択済み"
        case .checkingPermission: latestStateText = "権限確認中"
        case .awaitingPermission:
            latestStateText = "権限未許可"
            presentPermissionGuidance()
        case .running:
            latestStateText = "文字化中"
            recording = true
        case .stopping: latestStateText = "停止処理中"
        case .stopped: latestStateText = "停止"
        case .error(let msg): latestStateText = "エラー: \(msg)"
        }
        updateStatusItemIcon(recording: recording)
        rebuildMenu()
        updateTranscriptWindow()
    }

    private func updateTranscriptWindow() {
        guard let service, let window = transcriptWindow else { return }
        let pipeline = self.displayPipeline
        Task {
            let store = await service.transcriptStore
            // 保存経路（TranscriptSink）には常に原文が渡る（domain 側で完結済み）。
            // ここでは表示用にのみ DisplayPipeline で言語検出→必要なら翻訳した文字列を組み立てる
            // （機能B / ADR-5: 表示と保存の経路分離・volatile は翻訳しない）。
            let segments = store.finalizedSegments
            let volatile = store.volatileText
            var displayLines: [String] = []
            if let pipeline {
                for seg in segments {
                    let rendered = await pipeline.renderFinalized(seg.text)
                    displayLines.append(rendered)
                }
            } else {
                displayLines = segments.map(\.text)
            }
            let finalizedDisplay = displayLines.joined(separator: " ")
            await MainActor.run {
                window.update(finalized: finalizedDisplay, volatile: volatile)
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
