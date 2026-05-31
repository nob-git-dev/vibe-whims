import Foundation
import SpeechTapDomain
#if canImport(Translation)
import Translation
#endif

/// Translator 実装: Apple Translation framework（オンデバイス / 機能B / ADR-5）。
///
/// 固定要件:
/// - **クラウド送信を一切行わない**。URLSession / ネットワーク API を import しない（実装は OS の
///   オンデバイス翻訳エンジンに完全に委譲）。
/// - **OS 型を漏らさない**: シグネチャは Foundation の `Locale` のみ。`TranslationSession` / `Configuration` 等は
///   この infra adapter 内部にのみ存在する。
///
/// 実機検証で確定する事項（SPEC「### 実機検証で確定する事項」）:
/// - macOS 26 における `TranslationSession` / `Configuration` / `availableLanguages` の正確な API シグネチャ。
/// - Sendable / actor 制約（`TranslationSession` の保持戦略）。
/// - 言語パックダウンロードの実機 UX（OS が出すダイアログの安定性）。
///
/// 現状の実装方針:
/// - macOS 26 の Translation framework の安定 API シグネチャが文書化されきっていないため、
///   コンパイル可能なスケルトン実装に留め、`TranslationSession` を保持する設計の骨組みだけを示す。
/// - 実機検証で API が確定したら `#if canImport(Translation)` ブロック内の TODO を埋める。
/// - 未確定の間は `translate` / `ensureAvailable` ともに throw でフォールバック経路（DisplayPipeline の原文表示）
///   を駆動する（黙って空表示にしない / 受け入れ条件）。
public actor AppleTranslator: Translator {
    /// 翻訳が利用不可（言語パック未取得・未対応・実機検証未確定 API）を表す error。
    /// DisplayPipeline が catch して原文表示へフォールバックする。
    public enum TranslationError: Error, CustomStringConvertible {
        case unsupportedLanguage(Locale)
        case packUnavailable(Locale)
        case notImplemented

        public var description: String {
            switch self {
            case .unsupportedLanguage(let l): return "翻訳: 非対応言語 (\(l.identifier))"
            case .packUnavailable(let l): return "翻訳: 言語パック未取得 (\(l.identifier))"
            case .notImplemented: return "翻訳: 実機検証未確定（macOS 26 API）"
            }
        }
    }

    public init() {}

    public func translate(_ text: String, from source: Locale, to target: Locale) async throws -> String {
        #if canImport(Translation)
        // TODO（実機検証）: macOS 26 の Translation framework の正確な API で実装する。
        // 期待される一般的な構造（未確定のためコンパイル通る最小実装に留める）:
        //   let session = TranslationSession(configuration: .init(source: source, target: target))
        //   let response = try await session.translate(text)
        //   return response.targetText
        // クラウド送信を一切行わない実装方針: URLSession / ネットワーク API を import せず、
        // OS のオンデバイス翻訳エンジンにのみ委譲する。
        throw TranslationError.notImplemented
        #else
        throw TranslationError.notImplemented
        #endif
    }

    public func ensureAvailable(for source: Locale) async throws {
        #if canImport(Translation)
        // TODO（実機検証）: 言語パックの利用可否確認 + 必要なら OS のダウンロード許諾フローを起動する。
        // 期待される一般的な構造（未確定のためコンパイル通る最小実装に留める）:
        //   let configuration = TranslationSession.Configuration(source: source, target: Locale(identifier: "ja-JP"))
        //   try await configuration.prepareTranslation()
        throw TranslationError.notImplemented
        #else
        throw TranslationError.notImplemented
        #endif
    }
}
