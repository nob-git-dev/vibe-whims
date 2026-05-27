import Foundation

/// 音声キャプチャ権限の確認・要求の境界（実装は infrastructure）。
/// 本質: 未許可を黙って失敗させず検出し、許可されるまで音声取得を開始させない。
public protocol PermissionGate: Sendable {
    func currentStatus() -> PermissionStatus
    func request() async -> PermissionStatus
}
