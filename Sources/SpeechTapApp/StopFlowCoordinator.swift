import AppKit
import SpeechTapDomain

/// 停止フローの presentation 駆動コーディネータ（機能A / ADR-6）。
///
/// 責務:
/// - `TranscriptionService` の `.stopped` 遷移を検知して以下を順に実行する:
///   1. `SessionExporter.export(...)` で Downloads にセッション複本を書き出す（失敗はユーザー通知）。
///   2. 「表示クリアしますか？」ダイアログを表示する。
///   3. Yes なら `TranscriptStore.clearDisplay()` ＋ `TranscriptWindowController.clear()` を呼ぶ。
///   4. No なら表示を残す。**どちらの場合もメインファイル `transcript.txt` の内容には影響しない**。
///
/// 重要（固定要件「メインファイル append 非破壊」/ ADR-6）:
/// - 本 coordinator は **`TranscriptSink` には触れない**（保存経路は不変）。
/// - Downloads 書き出しが失敗してもメインファイル保存（FileTranscriptSink）の状況は不変。
///   失敗はモーダルでユーザーに通知し、停止フロー全体は巻き戻さない。
@MainActor
final class StopFlowCoordinator {
    private let exporter: SessionExporter
    private let transcriptCorrector: TranscriptCorrector?
    private let correctedExporter: CorrectedTranscriptExporter?
    private let service: TranscriptionService
    /// 文字起こしウィンドウ（遅延生成されるため、生成後に setWindow で渡す）。
    private weak var window: TranscriptWindowController?
    /// 状態行に翻訳/エクスポート関連の通知文字列を追記するためのコールバック（AppDelegate が提供）。
    private let onStatusMessage: (String) -> Void

    init(
        exporter: SessionExporter,
        transcriptCorrector: TranscriptCorrector? = nil,
        correctedExporter: CorrectedTranscriptExporter? = nil,
        service: TranscriptionService,
        window: TranscriptWindowController?,
        onStatusMessage: @escaping (String) -> Void
    ) {
        self.exporter = exporter
        self.transcriptCorrector = transcriptCorrector
        self.correctedExporter = correctedExporter
        self.service = service
        self.window = window
        self.onStatusMessage = onStatusMessage
    }

    /// 遅延生成された TranscriptWindowController を後から登録する（AppDelegate から呼ぶ）。
    func setWindow(_ window: TranscriptWindowController?) {
        self.window = window
    }

    /// `service.setStateChangeHandler` から呼ぶ。`.stopped` 遷移時のみ複本書き出し→ダイアログを起動する。
    func handleStateChange(_ state: SessionState) {
        guard case .stopped = state else { return }
        Task { @MainActor in
            await self.runStopFlow()
        }
    }

    private func runStopFlow() async {
        // 1. セッション情報を組み立てる（startedAt / stoppedAt + 現セッション確定列）。
        let store = await service.transcriptStore
        guard let times = await service.currentSessionTimes else {
            // 時刻が取れない場合（通常起きない）は安全側で何もしない。
            return
        }
        let session = store.snapshotCurrentSession(startedAt: times.startedAt, stoppedAt: times.stoppedAt)

        // 2. Downloads にセッション複本を書き出す。失敗してもメイン保存は完了済み。
        var exportURL: URL?
        do {
            exportURL = try await exporter.export(session)
        } catch {
            // 失敗通知（モーダル）。停止フロー全体は巻き戻さない。
            presentInfo("セッション複本の書き出しに失敗しました: \(error)")
            onStatusMessage("セッション複本の書き出しに失敗（メイン保存は完了済み）")
            // 表示クリア確認は続行しない（書き出し失敗時はクリアダイアログを出さない方が安全）。
            return
        }
        if let url = exportURL {
            onStatusMessage("セッション複本を書き出しました: \(url.lastPathComponent)")
        }

        // 3. LLM 校正が明示的に有効なら corrected 複本を書き出す。
        await runCorrectionIfEnabled(session: session)

        // 4. 表示クリア確認ダイアログ（メインファイルには影響しない旨をメッセージに明記）。
        let shouldClear = await askClearDisplay()
        if shouldClear {
            store.clearDisplay()
            window?.clear()
        }
    }

    private func runCorrectionIfEnabled(session: TranscriptSession) async {
        guard let transcriptCorrector, let correctedExporter else { return }
        let rawTranscript = TranscriptCorrectionPrompt.rawTranscript(from: session)
        guard !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        onStatusMessage("LLM 校正中...")
        do {
            let corrected = try await transcriptCorrector.correct(rawTranscript: rawTranscript)
            let url = try await correctedExporter.export(correctedText: corrected, originalSession: session)
            onStatusMessage("LLM 校正を書き出しました: \(url.lastPathComponent)")
        } catch {
            presentInfo("LLM 校正に失敗しました: \(error)")
            onStatusMessage("LLM 校正に失敗（原文保存は完了済み）")
        }
    }

    private func askClearDisplay() async -> Bool {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "表示をクリアしますか？"
            alert.informativeText = "ウィンドウ上の文字起こしを消去します。"
                + "保存済みのメインファイル（transcript.txt）には影響しません。"
            alert.addButton(withTitle: "クリアする")
            alert.addButton(withTitle: "残す")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    private func presentInfo(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "SpeechTap"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
