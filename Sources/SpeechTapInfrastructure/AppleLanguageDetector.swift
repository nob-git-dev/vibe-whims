import Foundation
import SpeechTapDomain
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// LanguageDetector 実装: NaturalLanguage / NLLanguageRecognizer（機能B / ADR-5）。
///
/// 契約（port「LanguageDetector」）:
/// - 同期で言語コードを判定する。判定不能時（極端に短い・低 confidence・空文字列）は `nil` を返す。
/// - **OS 型を漏らさない**: `NLLanguage` を Foundation `Locale` に変換して返す（domain は OS/UI 非依存）。
///
/// 実機検証で確定する事項（決め打ちしない）:
/// - 短い発話・カタカナ・固有名詞での誤判定対策（confidence しきい値の最終値）。
/// - 現状はしきい値 0.5 を採用（フォールバック先=原文表示で安全側に倒すため低めに設定）。
public final class AppleLanguageDetector: LanguageDetector, @unchecked Sendable {
    /// 低 confidence を判定不能（nil）として扱うためのしきい値（暫定）。
    private let confidenceThreshold: Double

    public init(confidenceThreshold: Double = 0.5) {
        self.confidenceThreshold = confidenceThreshold
    }

    public func detect(_ text: String) -> Locale? {
        // 空文字列・極端に短い文字列は判定不能扱い（誤検出防止）。
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }

        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let (lang, confidence) = hypotheses.max(by: { $0.value < $1.value }) else {
            return nil
        }
        guard confidence >= confidenceThreshold else { return nil }
        return Locale(identifier: lang.rawValue)
        #else
        return nil
        #endif
    }
}
