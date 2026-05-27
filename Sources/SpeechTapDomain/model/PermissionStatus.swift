import Foundation

/// 音声キャプチャ権限の状態。OS 固有の権限型に依存しない domain 中立表現。
public enum PermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case undetermined
}
