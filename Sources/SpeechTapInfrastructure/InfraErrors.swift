import Foundation

/// infrastructure 共通のエラー型。
/// 実機 API 接触が未実装のスケルトンが投げる「未実装」エラーをここに集約する。
enum NotImplemented: Error {
    case processTap
    case speechAnalyzer
}
