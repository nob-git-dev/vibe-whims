import Foundation

/// domain 層の観測点（オブザーバビリティ設計の port）。
///
/// 固定要件: domain は OS API（os.Logger / OSLog）を import してはならない。
/// そこで domain には「何を記録したいか」だけを表すこの薄い protocol を置き、
/// 実体（os.Logger ラッパ）は infrastructure に置いて Composition Root で注入する。
/// これにより 3層一方向依存（domain は OS 非依存）を壊さずに domain を可観測にできる。
///
/// 既定実装は no-op（`NullEventLogger`）。テストや観測不要時は注入しなくてよい。
public protocol EventLogger: Sendable {
    /// 状態遷移・分岐などの通常イベント。
    func log(_ message: String)
    /// 異常・失敗イベント（error 遷移・保存失敗など）。
    func error(_ message: String)
}

/// 何も記録しない既定実装（注入されない場合のフォールバック）。
public struct NullEventLogger: EventLogger {
    public init() {}
    public func log(_ message: String) {}
    public func error(_ message: String) {}
}
