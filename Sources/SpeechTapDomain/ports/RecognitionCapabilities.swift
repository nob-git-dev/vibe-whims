import Foundation

/// 認識器がオンデバイスで対応する言語ロケール一覧を供給する境界（実装は infrastructure: SpeechTranscriber.supportedLocales）。
/// ADR-7（認識言語選択）: presentation の「認識言語」サブメニュー構築に使う。
///
/// 契約:
/// - **OS 型を漏らさない**: `SpeechTranscriber` / `SpeechTranscriber.supportedLocales` の OS 型は出さず、
///   Foundation の `[Locale]` に正規化して返す（domain は OS/UI 非依存を維持）。
/// - **空配列の扱い**: 取得失敗・未対応時は空配列を返してよい
///   （presentation は「日本語 / 英語」の既定項目を最低限提示し、空表示にしない）。
///
/// 別 port にする理由（ADR-7 棄却案 (d)）: `SpeechRecognizer` は「音声→文字化」の責務で、
/// 能力照会は別関心事。port を肥大化させず単一責務に保つため独立 port にする。
public protocol RecognitionCapabilities: Sendable {
    /// 認識器がオンデバイスで対応する言語ロケール一覧を返す。取得失敗時は空配列。
    func supportedLocales() async -> [Locale]
}
