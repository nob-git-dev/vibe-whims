import Foundation
import SpeechTapDomain
#if canImport(os)
import os
#endif

/// domain の `EventLogger` port を os.Logger で実装する（Composition Root で注入）。
/// domain は OS 非依存のままこのラッパ経由で可観測になる。
/// category は `AppLog.Category.app`（状態遷移）に集約する。
public struct OSEventLogger: EventLogger {
    public init() {}

    public func log(_ message: String) {
        #if canImport(os)
        AppLog.logger(.app).info("\(message, privacy: .public)")
        #endif
    }

    public func error(_ message: String) {
        #if canImport(os)
        AppLog.logger(.app).error("\(message, privacy: .public)")
        #endif
    }
}
