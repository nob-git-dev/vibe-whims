import Foundation

/// セッション分の確定テキストとセッション境界時刻を保持する値型（機能A / ADR-6）。
///
/// セッション境界（ADR-6）: `TranscriptionService.start` → `TranscriptionService.stop` までを 1 セッション。
/// プロセス再起動を跨いだ場合も別セッション。
///
/// 用途: `SessionExporter.export` の入力。Downloads セッション複本書き出しで使う。
/// 保存内容は**原文のみ**（機能B の翻訳結果は含めない / 固定要件「画面表示と保存の経路分離」）。
///
/// 設計判断（ADR-6）: 時刻は `Date` で値として渡す。`Clock` port は今回導入しない
/// （`TranscriptionService` 内の 1 箇所で `Date()` を呼び、値で受け渡せばテスト可能なため YAGNI）。
public struct TranscriptSession: Sendable, Equatable {
    public let segments: [TranscriptSegment]
    public let startedAt: Date
    public let stoppedAt: Date

    public init(segments: [TranscriptSegment], startedAt: Date, stoppedAt: Date) {
        self.segments = segments
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
    }
}
