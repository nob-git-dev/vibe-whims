import Testing
import Foundation
@testable import SpeechTapInfrastructure

/// ADR-8（マルチプロセスタップ）の**集約判定ロジック**を純粋関数として検証する。
///
/// 【最重要本質=非混入】対象アプリに属するプロセスのみを集める。曖昧なプロセスは**除外側に倒す**
/// （偽陽性で他アプリ音を混ぜるより、偽陰性で一部ヘルパーを取りこぼす方が本質的に安全）。
///
/// Core Audio 実機接触部分（kAudioHardwarePropertyProcessObjectList / kAudioProcessPropertyPID /
/// responsiblePID の実取得・CATapDescription への配列受け渡し）は実機検証項目とし、
/// ここではマッチング判定（PID / bundleId / responsiblePID）のみをテストする。
struct ProcessMatcherTests {

    private let targetPID: pid_t = 1000
    private let targetBundleId = "com.google.Chrome"

    private func target() -> ProcessMatcher.Target {
        ProcessMatcher.Target(mainPID: targetPID, bundleId: targetBundleId)
    }

    @Test("対象アプリのメイン PID / 同一 bundleId / responsiblePID 一致のプロセスのみ選ばれる（他アプリは除外）")
    func selectsOnlyTargetOwnedProcesses() {
        let processes = [
            // 基準1: メイン PID 一致 → 含む。
            ProcessMatcher.ProcessInfo(audioObjectID: 11, pid: targetPID, bundleId: targetBundleId, responsiblePID: targetPID),
            // 基準2: responsiblePID が対象メイン PID → ヘルパーとして含む。
            ProcessMatcher.ProcessInfo(audioObjectID: 12, pid: 1001, bundleId: "com.google.Chrome.helper", responsiblePID: targetPID),
            // 基準3: 同一 bundleId → 含む。
            ProcessMatcher.ProcessInfo(audioObjectID: 13, pid: 1002, bundleId: targetBundleId, responsiblePID: 9999),
            // 他アプリ（bundleId 別・responsiblePID 別） → 絶対に含めない（非混入）。
            ProcessMatcher.ProcessInfo(audioObjectID: 99, pid: 2000, bundleId: "com.apple.Music", responsiblePID: 2000)
        ]
        let selected = ProcessMatcher.select(from: processes, target: target())
        #expect(Set(selected) == Set([11, 12, 13]))
        #expect(!selected.contains(99))
    }

    @Test("bundleId 不明・どの基準にも明確に該当しないプロセスは集約に含めない（曖昧は除外側に倒す）")
    func excludesAmbiguousProcesses() {
        let processes = [
            // 対象メイン PID → 含む。
            ProcessMatcher.ProcessInfo(audioObjectID: 11, pid: targetPID, bundleId: targetBundleId, responsiblePID: targetPID),
            // bundleId 取得不能・responsiblePID も対象でない → 曖昧。除外。
            ProcessMatcher.ProcessInfo(audioObjectID: 50, pid: 3000, bundleId: nil, responsiblePID: 3000),
            // bundleId 取得不能・responsiblePID も nil → 曖昧。除外。
            ProcessMatcher.ProcessInfo(audioObjectID: 51, pid: 3001, bundleId: nil, responsiblePID: nil)
        ]
        let selected = ProcessMatcher.select(from: processes, target: target())
        #expect(selected == [11])
    }

    @Test("関連プロセスがメイン 1 つだけのアプリでも、メイン PID の AudioObjectID が集約に含まれる（単一プロセス互換）")
    func singleProcessAppStillIncludesMainPID() {
        let processes = [
            ProcessMatcher.ProcessInfo(audioObjectID: 11, pid: targetPID, bundleId: targetBundleId, responsiblePID: targetPID),
            // 別アプリのプロセスが居ても対象は 1 つだけ。
            ProcessMatcher.ProcessInfo(audioObjectID: 88, pid: 5000, bundleId: "com.apple.Safari", responsiblePID: 5000)
        ]
        let selected = ProcessMatcher.select(from: processes, target: target())
        #expect(selected == [11])
    }

    @Test("responsiblePID が対象アプリのメイン PID を指すヘルパーは集約に含まれる（ブラウザ無音問題の根治）")
    func helperWithResponsiblePIDIsIncluded() {
        let processes = [
            // メイン本体は音を出さない場合でも、メイン PID プロセスは基準1で含む。
            ProcessMatcher.ProcessInfo(audioObjectID: 11, pid: targetPID, bundleId: targetBundleId, responsiblePID: targetPID),
            // 音を出すレンダラー（別 PID・独立 bundleId）だが責任プロセスは Chrome 本体 → 含む。
            ProcessMatcher.ProcessInfo(audioObjectID: 12, pid: 1500, bundleId: "com.google.Chrome.helper.Renderer", responsiblePID: targetPID)
        ]
        let selected = ProcessMatcher.select(from: processes, target: target())
        #expect(Set(selected) == Set([11, 12]))
    }

    @Test("対象 bundleId の名前空間配下のヘルパー（<target>. 始まり）は含み、他アプリは除外（非混入を維持）")
    func bundleIdNamespaceHelpersAreIncludedButOtherAppsExcluded() {
        let processes = [
            // 対象 bundleId 名前空間配下のヘルパー（別 PID・responsiblePID 不明）→ 含む。
            ProcessMatcher.ProcessInfo(audioObjectID: 21, pid: 1200, bundleId: "com.google.Chrome.helper.Renderer", responsiblePID: nil),
            // たまたま似た接頭辞だが別アプリ（"com.google.Chrome" で始まらない）→ 除外。
            ProcessMatcher.ProcessInfo(audioObjectID: 22, pid: 1300, bundleId: "com.google.ChromeRemoteDesktop", responsiblePID: nil),
            // 完全に別アプリ → 除外。
            ProcessMatcher.ProcessInfo(audioObjectID: 23, pid: 1400, bundleId: "com.apple.Music", responsiblePID: nil)
        ]
        let selected = ProcessMatcher.select(from: processes, target: target())
        #expect(selected == [21])
    }

    @Test("対象プロセスが 1 つも無い場合は空配列を返す（呼び出し側で従来どおり失敗扱い）")
    func emptyWhenNoTargetProcess() {
        let processes = [
            ProcessMatcher.ProcessInfo(audioObjectID: 99, pid: 2000, bundleId: "com.apple.Music", responsiblePID: 2000)
        ]
        let selected = ProcessMatcher.select(from: processes, target: target())
        #expect(selected.isEmpty)
    }
}
