import Foundation
import SpeechTapDomain

/// AppEnumerator 実装: NSWorkspace + Core Audio process list。
/// PID → AudioObjectID 変換に必要なため Core Audio process list を併用する（移行影響マップ）。
///
/// TODO（実機検証が必要なため未実装。SPEC 手動検証項目参照）:
/// - NSWorkspace.shared.runningApplications で起動中アプリ列挙
/// - kAudioHardwarePropertyProcessObjectList で音声出力プロセスを併用判定
/// - TargetApp（id/name/bundleId/pid）へ正規化（OS 型を domain に漏らさない）
public final class RunningAppProvider: AppEnumerator, @unchecked Sendable {
    public init() {}

    public func listAudioCapableApps() async throws -> [TargetApp] {
        // TODO: NSWorkspace + Core Audio process list から TargetApp を構築する。
        []
    }
}
