import Foundation

/// 対象アプリを一意に識別する値型。
/// OS 型（pid_t 等）を domain に漏らさないため、識別子を中立な値として扱う。
public struct AppId: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
