import Foundation
import SpeechTapDomain

/// PermissionGate 実装: 音声キャプチャ権限（NSAudioCaptureUsageDescription / ADR-1）。
/// 画面収録権限・マイク権限は不要。私的 TCC API に依存せず、公開 API とエラーハンドリングで未許可検出する。
///
/// TODO（実機検証が必要なため未実装。SPEC 手動検証項目参照）:
/// - currentStatus: タップ生成の試行可否や保存済み状態から granted/denied/undetermined を判定
/// - request: 初回キャプチャ開始時に OS が表示する権限ダイアログ結果を待ち、拒否時は denied を返す
/// - Info.plist に NSAudioCaptureUsageDescription を設定（→ /deploy）
public final class AudioCapturePermission: PermissionGate, @unchecked Sendable {
    public init() {}

    public func currentStatus() -> PermissionStatus {
        // TODO: 公開 API / タップ生成試行で現在の権限状態を判定する。
        .undetermined
    }

    public func request() async -> PermissionStatus {
        // TODO: 権限ダイアログを提示し結果を待つ。拒否なら denied。
        .undetermined
    }
}
