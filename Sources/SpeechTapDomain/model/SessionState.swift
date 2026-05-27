import Foundation

/// 文字化セッションの状態（SPEC「## 状態遷移」）。
/// idle ─選択→ selected ─開始→ checkingPermission ─granted→ running / ─denied→ awaitingPermission
/// running ─停止/終了→ stopping ─finalize+flush→ stopped / ─エラー→ error
public enum SessionState: Sendable, Equatable {
    case idle
    case selected(AppId)
    case checkingPermission(AppId)
    case awaitingPermission(AppId)
    case running(AppId)
    case stopping(AppId)
    case stopped
    case error(String)
}
