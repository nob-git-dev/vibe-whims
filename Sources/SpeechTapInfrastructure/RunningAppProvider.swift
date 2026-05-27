import Foundation
import SpeechTapDomain
#if canImport(AppKit)
import AppKit
#endif

/// AppEnumerator 実装: NSWorkspace で起動中アプリを列挙する。
/// PID を持つ TargetApp に変換する（ProcessTapAudioSource が PID → AudioObjectID 変換に使う）。
///
/// AppId.rawValue には bundleId を採用する（config の TARGET_APP_ID と突き合わせるため）。
/// bundleId が無いアプリは "pid:<n>" を識別子にフォールバックする。
///
/// 実機検証項目（SPEC 手動検証項目）:
/// - 列挙したアプリのうち、実際に音声を出すものに対しタップが構成できるか
/// - 対象アプリが複数プロセス（例: ブラウザのヘルパープロセス）に分かれる場合の挙動
public final class RunningAppProvider: AppEnumerator, @unchecked Sendable {
    public init() {}

    public func listAudioCapableApps() async throws -> [TargetApp] {
        #if canImport(AppKit)
        // 通常 UI を持つ起動中アプリ（.regular）を列挙する。
        // 厳密な「音声出力中」判定は Core Audio process list との突き合わせが必要だが、
        // walking skeleton では起動中アプリ一覧をユーザーに提示し、選択されたものをタップ対象とする。
        let running = NSWorkspace.shared.runningApplications
        let apps: [TargetApp] = running.compactMap { app in
            guard app.activationPolicy == .regular else { return nil }
            let pid = Int(app.processIdentifier)
            guard pid > 0 else { return nil }
            let bundleId = app.bundleIdentifier
            let name = app.localizedName ?? bundleId ?? "PID \(pid)"
            let idValue = bundleId ?? "pid:\(pid)"
            return TargetApp(id: AppId(idValue), name: name, bundleId: bundleId, pid: pid)
        }
        // 表示安定のため名前順にソートし、同名 bundleId 重複は最初の 1 件に寄せる。
        var seen = Set<String>()
        return apps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .filter { seen.insert($0.id.rawValue).inserted }
        #else
        return []
        #endif
    }
}
