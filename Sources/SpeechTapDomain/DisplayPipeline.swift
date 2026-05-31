import Foundation

/// 表示用テキストパイプライン（機能B / ADR-5）。
///
/// 役割: 認識結果（原文）を「言語検出 → 必要なら翻訳 → 表示用テキスト」へ変換するだけの薄い純関数。
///
/// 設計判断（domain 配置の理由）:
/// - SPEC「## システム構成」では presentation 配下に挙げられているが、本コンポーネントは
///   ports（`LanguageDetector` / `Translator`）への薄い合成しか持たず、AppKit / UI に一切依存しない。
/// - 「表示と保存の経路分離」を構造的に担保するには、`TranscriptionService` の保存経路（`TranscriptSink`）
///   とは完全に独立した純粋な変換器として fake テスト可能であることが本質。これを実現するため
///   `DisplayPipeline` は domain ターゲットに置く（Foundation のみ依存）。
/// - 結果として「presentation の `TranscriptWindowController.update` には**表示用文字列**を渡し、
///   保存経路（`TranscriptSink.append`）は不変（原文を渡す）」という固定要件は保たれる。
///
/// 契約:
/// - finalized は「日本語以外と検出された」かつ「Translator.translate が成功した」場合のみ翻訳結果を返す。
/// - その他のすべてのケース（日本語判定 / 判定不能 / 翻訳失敗）は**原文へフォールバック**する
///   （黙って空表示にしない・受け入れ条件）。
/// - **volatile は決して翻訳しない**（常に原文をそのまま返す。ADR-5: 体感遅延・品質・呼び出し量の観点）。
/// - **TranscriptSink には一切触れない**（保存経路を汚染しない / 固定要件）。
public actor DisplayPipeline {
    private let detector: LanguageDetector
    private let translator: Translator
    private let targetLocale: Locale

    public init(detector: LanguageDetector, translator: Translator, targetLocale: Locale) {
        self.detector = detector
        self.translator = translator
        self.targetLocale = targetLocale
    }

    /// 確定（finalized）テキストを表示用テキストへ変換する。
    /// 日本語判定 or 判定不能 or 翻訳失敗時は原文フォールバック。
    public func renderFinalized(_ text: String) async -> String {
        guard let detected = detector.detect(text) else {
            return text // 判定不能は「日本語ではない」とは扱わず原文表示にフォールバック。
        }
        if Self.isSameLanguage(detected, targetLocale) {
            return text
        }
        do {
            return try await translator.translate(text, from: detected, to: targetLocale)
        } catch {
            return text // 翻訳失敗時は原文フォールバック（黙って空表示にしない）。
        }
    }

    /// 暫定（volatile）テキストを表示用テキストへ変換する。
    /// ADR-5: volatile は翻訳せず常に原文をそのまま表示する。
    public func renderVolatile(_ text: String) async -> String {
        return text
    }

    /// ロケールが「実用上同じ言語」かを判定する（言語コード = `languageCode` で比較）。
    /// `ja` / `ja-JP` / `ja_JP` をいずれも日本語と扱う。
    private static func isSameLanguage(_ a: Locale, _ b: Locale) -> Bool {
        // Locale.LanguageCode を使うと Apple-only 型になるため、文字列比較で安全に判定する。
        let codeA = a.identifier.split(separator: "-").first?.split(separator: "_").first.map(String.init)
            ?? a.identifier
        let codeB = b.identifier.split(separator: "-").first?.split(separator: "_").first.map(String.init)
            ?? b.identifier
        return codeA.lowercased() == codeB.lowercased()
    }
}
