import Foundation
import SpeechTapDomain
#if canImport(CoreAudio)
import CoreAudio
#endif

/// PermissionGate 実装: 音声キャプチャ権限（NSAudioCaptureUsageDescription / ADR-1）。
/// 画面収録権限・マイク権限は不要。私的 TCC API に依存せず、公開 API（タップ生成の試行）とエラーで判定する。
///
/// 判定方針（SPEC「### TCC 権限」(a)(b)）:
/// - グローバルタップの生成を試み、成功すれば granted、権限関連エラーなら denied/undetermined と判定する。
/// - 初回試行時に OS が権限ダイアログを表示する（request 経路）。
/// - 一度ダイアログに応答すると以降は同じ結果が返るため、状態を確認できる。
///
/// 実機検証項目（SPEC 手動検証項目・ユニットテスト不能）:
/// - 実機で権限ダイアログが出るか。未許可検出が戻り値で成立するか。
public final class AudioCapturePermission: PermissionGate, @unchecked Sendable {
    public init() {}

    public func currentStatus() -> PermissionStatus {
        #if canImport(CoreAudio)
        return probe()
        #else
        return .undetermined
        #endif
    }

    public func request() async -> PermissionStatus {
        #if canImport(CoreAudio)
        // タップ生成を試みると、未応答ならこの呼び出しで OS の権限ダイアログが表示される。
        // ダイアログ応答後の結果を返す（拒否なら denied）。
        return probe()
        #else
        return .undetermined
        #endif
    }

    #if canImport(CoreAudio)
    /// 軽量なグローバルタップ（ミュート）を生成して即破棄し、戻り値から権限状態を推定する。
    /// プロセス指定タップと同じ音声キャプチャ権限を要求するため、権限確認のプローブとして使える。
    private func probe() -> PermissionStatus {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        if status == noErr, tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            return .granted
        }
        // 権限拒否時は OSStatus が権限/許可エラーになる。
        // 私的 TCC API に依存せず、生成不可＝未許可（denied）として扱う。
        // （undetermined と denied の厳密な区別は公開 API では困難。実機で挙動確定する。）
        return .denied
    }
    #endif
}
