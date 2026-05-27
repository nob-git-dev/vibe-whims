import Foundation
#if canImport(os)
import os
#endif

/// 診断ログの中枢（オブザーバビリティ設計）。
///
/// 目的: 「実機で状態は running になるのに認識結果が 1 件も出ない」という黒箱を可観測にする。
/// 音声フレームがパイプラインのどこまで流れ、どこで消えるかを構造化ログで追跡する。
///
/// 設計方針:
/// - subsystem は全ログで統一（`com.example.speech-tap`）。category で観測点を分離する。
/// - infrastructure / presentation 層のみが os.Logger を使う（OS API 依存可）。
///   domain 層は Foundation のみ依存を厳守するため `EventLogger` port 経由で観測する。
/// - リアルタイムスレッド（IOProc）では Logger を直接呼ばず、カウンタ集約 + 間引き出力に留める。
///
/// 収集方法（runbook は SPEC.md「## オブザーバビリティ設計」を参照）:
///   log stream --predicate 'subsystem == "com.example.speech-tap"' --info --debug
public enum AppLog {
    /// 全ログ共通の subsystem。`log stream --predicate 'subsystem == "..."'` で一括観測する。
    public static let subsystem = "com.example.speech-tap"

    /// 観測点（category）。各値が「パイプラインのどの段か」を表す。
    public enum Category: String {
        /// Process Tap の構成・起動（PID 解決 / ASBD / Aggregate Device / AudioDeviceStart）。
        case tap = "tap"
        /// IOProc コールバック（リアルタイムスレッド。バッファ構造・サンプル数）。
        case ioproc = "ioproc"
        /// SpeechAnalyzer への供給・結果受信（analyzerFormat / feed / yield / results）。
        case analyzer = "analyzer"
        /// フォーマット変換（入力 format / target format / 成功・失敗）。
        case converter = "converter"
        /// アプリ状態遷移（presentation）。
        case app = "app"
    }

    #if canImport(os)
    /// category 別の Logger を生成する。
    public static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
    #endif
}
