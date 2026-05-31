import Foundation

/// テキストの言語検出の境界（実装は infrastructure: NLLanguageRecognizer / NaturalLanguage）。
/// 機能B / ADR-5: DisplayPipeline が「翻訳すべきか否か」を判断するために使う。
///
/// 契約:
/// - 同期で OK（短い文字列の判定はリアルタイム性に影響しない）。
/// - **判定不能時は `nil` を返す**（例: 空文字列・極端に短い文字列・低 confidence）。
///   呼び出し側は「日本語ではない」とは扱わず、原文表示にフォールバックして良い（安全側）。
/// - **OS 型を漏らさない**: `NLLanguage` / `NLLanguageRecognizer` は出さず、Foundation の `Locale` で返す。
public protocol LanguageDetector: Sendable {
    /// テキストの言語を判定する。判定不能時は nil（原文表示フォールバックを呼び出し側で判断する）。
    func detect(_ text: String) -> Locale?
}
