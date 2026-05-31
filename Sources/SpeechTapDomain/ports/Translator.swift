import Foundation

/// オンデバイス翻訳の境界（実装は infrastructure: Apple Translation framework）。
/// 機能B / ADR-5: 表示パスにのみ使い、保存パス（TranscriptSink）には決して翻訳結果を流さない。
///
/// 契約:
/// - **外部送信禁止**: 実装は外部ネットワークに音声・テキストを送信してはならない（固定要件）。
/// - **不可時の throw 契約**: 翻訳パック未インストール / 利用不可な場合は明確な error を throw する
///   （黙って空文字列・原文返却にしない）。呼び出し側（DisplayPipeline）が「原文フォールバック + 状態通知」を判断する。
/// - **OS 型を漏らさない**: シグネチャに Apple Translation framework の `TranslationSession` 等を出さない。
///   Foundation の `Locale` のみで意味を扱う（domain は OS/UI 非依存）。
public protocol Translator: Sendable {
    /// 原文 `text` を `source` から `target` のロケールへオンデバイスで翻訳する。
    /// 翻訳不可時は throw する（呼び出し側が原文フォールバックを判断する）。
    func translate(_ text: String, from source: Locale, to target: Locale) async throws -> String

    /// 指定言語の翻訳が利用可能かを確認する（必要なら言語パックダウンロード許諾を促す）。
    /// 呼び出しタイミング: 起動時ではなく**初回検出時**（非日本語が検出された最初の機会）に呼ぶ
    /// （複数言語の事前一括ダウンロードを強制しないため・ADR-5）。
    /// 言語非対応・ダウンロード未許諾等で利用不可な場合は throw する。
    func ensureAvailable(for source: Locale) async throws
}
