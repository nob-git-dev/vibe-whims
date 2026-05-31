import Foundation
#if canImport(CoreAudio)
import CoreAudio
#endif

/// ADR-8（マルチプロセスタップ）の**集約判定ロジック**を純粋関数として切り出したもの。
///
/// 【最重要本質=非混入】対象アプリに属するプロセスのみを集める。Core Audio / NSRunningApplication 等の
/// OS API 接触は呼び出し側（`ProcessTapAudioSource`）が行い、ここでは「収集済みのプロセス情報」に対する
/// マッチング判定のみを担う。これにより非混入の判定ロジックを OS なしでユニットテストできる。
///
/// 判定基準（いずれかに**明確に**該当するもののみ採用。曖昧は**除外側に倒す**）:
/// - (基準1) メイン PID 一致: 対象アプリのメイン PID と一致（従来の対象を必ず含む）。
/// - (基準2) responsiblePID が対象メイン PID: ブラウザのレンダラー/ヘルパー（責任プロセスが本体）を集める。
/// - (基準3・補助) bundleId が対象に属する: bundleId が対象アプリと一致、または
///   対象 bundleId の名前空間配下（例: `com.google.Chrome.helper.Renderer` は `com.google.Chrome.` 始まり）。
///   これは対象アプリの reverse-DNS 名前空間に閉じるため、他アプリ（例 `com.apple.Music`）を巻き込まない
///   （非混入を維持しつつ、独立 bundleId を持つヘルパーを捕捉する）。
///
/// 偽陽性で他アプリ音を混ぜるより、偽陰性で一部ヘルパーを取りこぼす方が本質的に安全（非混入を最優先）。
enum ProcessMatcher {
    /// 対象アプリの識別情報（メイン PID + bundleId）。
    struct Target {
        let mainPID: pid_t
        let bundleId: String?
        init(mainPID: pid_t, bundleId: String?) {
            self.mainPID = mainPID
            self.bundleId = bundleId
        }
    }

    /// 収集済みのオーディオプロセス情報。
    /// - audioObjectID: Core Audio のプロセスオブジェクト ID（集約結果として返す値）。
    /// - pid: そのプロセスの PID（kAudioProcessPropertyPID 由来）。
    /// - bundleId: NSRunningApplication(processIdentifier:) 由来の bundleId（取得不能なら nil）。
    /// - responsiblePID: 責任プロセスの PID（取得不能なら nil）。
    struct ProcessInfo {
        let audioObjectID: AudioObjectID
        let pid: pid_t
        let bundleId: String?
        let responsiblePID: pid_t?
        init(audioObjectID: AudioObjectID, pid: pid_t, bundleId: String?, responsiblePID: pid_t?) {
            self.audioObjectID = audioObjectID
            self.pid = pid
            self.bundleId = bundleId
            self.responsiblePID = responsiblePID
        }
    }

    /// 対象アプリに属するプロセスの AudioObjectID 配列を返す。該当なしなら空配列。
    static func select(from processes: [ProcessInfo], target: Target) -> [AudioObjectID] {
        processes
            .filter { belongs($0, to: target) }
            .map(\.audioObjectID)
    }

    /// 採用判定の結果と理由（実機切り分け用の診断ログに使う。判定ロジックの単一の真実源）。
    enum Decision: Equatable {
        case includedByMainPID            // 基準1: メイン PID 一致
        case includedByResponsiblePID     // 基準2: 責任プロセスが対象メイン PID（レンダラー捕捉）
        case includedByBundleNamespace    // 基準3: bundleId が対象 or 名前空間配下
        case excludedAmbiguousOrOther     // いずれにも明確に該当せず（他アプリ・曖昧）→ 除外

        var isIncluded: Bool {
            switch self {
            case .includedByMainPID, .includedByResponsiblePID, .includedByBundleNamespace:
                return true
            case .excludedAmbiguousOrOther:
                return false
            }
        }
    }

    /// プロセスが対象アプリに属するか（いずれかの基準に明確に該当するか）を判定する。
    static func belongs(_ process: ProcessInfo, to target: Target) -> Bool {
        decision(for: process, to: target).isIncluded
    }

    /// 採用/除外の判定とその理由を返す（純粋関数・OS 非接触。`belongs` の真実源）。
    static func decision(for process: ProcessInfo, to target: Target) -> Decision {
        // 基準1: メイン PID 一致（従来対象を必ず含む）。
        if process.pid == target.mainPID { return .includedByMainPID }
        // 基準2: 責任プロセスが対象メイン PID（ブラウザのヘルパー/レンダラー）。
        if let responsible = process.responsiblePID, responsible == target.mainPID {
            return .includedByResponsiblePID
        }
        // 基準3（補助）: bundleId が対象に属する（双方取得できている場合のみ。曖昧=nil は除外側）。
        // 完全一致、または対象 bundleId の名前空間配下（"<target>." 始まり）のみ採用する。
        if let bid = process.bundleId, let targetBid = target.bundleId, !targetBid.isEmpty {
            if bid == targetBid { return .includedByBundleNamespace }
            if bid.hasPrefix(targetBid + ".") { return .includedByBundleNamespace }
        }
        // いずれにも明確に該当しない（他アプリ・曖昧）→ 除外（非混入優先）。
        return .excludedAmbiguousOrOther
    }
}

#if !canImport(CoreAudio)
// CoreAudio 非対応環境でも ProcessMatcher を型として成立させるための別名
// （AudioObjectID は CoreAudio 由来。テストは CoreAudio のある macOS で走る前提だが構造的に保護する）。
typealias AudioObjectID = UInt32
#endif
