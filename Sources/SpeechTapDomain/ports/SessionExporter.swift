import Foundation

/// セッション分の確定テキスト列を独立 1 ファイルとして書き出す境界（実装は infrastructure: ~/Downloads）。
/// 機能A / ADR-6: メインファイル append 経路（FileTranscriptSink）には**触れない**副経路として動く。
///
/// 契約:
/// - **保存内容は原文のみ**（機能B の翻訳結果を含めない / 固定要件「画面表示と保存の経路分離」）。
/// - **既存 `transcript.txt` の append 経路には触れない**（停止フローの主経路 finalize → drain → flush は不変）。
/// - **失敗時の意味**: error を throw する。停止フロー全体は巻き戻さず、
///   呼び出し側（StopFlowCoordinator）が「メイン保存は完了済み」を前提にユーザー通知する。
/// - **戻り値**: 書き出した先の URL（UI 提示・後続検証に使う）。
public protocol SessionExporter: Sendable {
    /// セッション分の確定テキスト列を独立 1 ファイルとして書き出す。
    /// ファイル名規則（ADR-6）: 実装側で `~/Downloads/speech-tap-YYYYMMDD-HHmmss[-N].txt` 等を生成する。
    func export(_ session: TranscriptSession) async throws -> URL
}
