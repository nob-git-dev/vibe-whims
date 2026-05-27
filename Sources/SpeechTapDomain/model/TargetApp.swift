import Foundation

/// 文字化の対象となり得るアプリ。AppEnumerator が列挙して返す。
/// pid は Int で保持し、OS 型（pid_t）を domain シグネチャに出さない。
public struct TargetApp: Hashable, Sendable, Identifiable {
    public let id: AppId
    public let name: String
    public let bundleId: String?
    public let pid: Int

    public init(id: AppId, name: String, bundleId: String?, pid: Int) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.pid = pid
    }
}
