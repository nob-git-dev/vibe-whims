import Foundation

/// ASR transcript を「意味を変えずに読みやすくする」ための prompt。
///
/// prompt は domain の純粋値として固定し、OpenAI 互換 API への投入は infrastructure に任せる。
public struct TranscriptCorrectionPrompt: Sendable, Equatable {
    public let system: String
    public let user: String

    public init(rawTranscript: String) {
        self.system = Self.systemPrompt
        self.user = Self.userPrompt(rawTranscript: rawTranscript)
    }

    public static func rawTranscript(from session: TranscriptSession) -> String {
        session.segments.map(\.text).joined(separator: "\n")
    }

    public static let systemPrompt = """
あなたは音声認識トランスクリプションの保守的な校正者です。入力は SpeechAnalyzer などの ASR が返した原文です。

最重要方針:
- 原文の意味、主張、順序、情報量を変えない。
- 90%以上の確信がある箇所だけ修正する。不確実な箇所は原文を残す。
- 要約しない。翻訳しない。説明を足さない。話者が言っていない内容を補わない。

許可される修正:
- 音声認識特有の誤字、誤変換、聞き間違い、脱落しすぎた句読点、読みにくい改行、明らかな反復だけを修正する。
- 口語の自然さは残す。ただし読み物として破綻するフィラーや連続した言い直しは、意味が変わらない範囲で整理する。

保守ルール:
- 数字、回数、順序、番号を推測で変えない。章番号、箇条番号、第4、第5、その1、その2などは原文優先。
- 固有名詞、専門用語、数式用語、年号、数値は文脈から明らかに誤りと判断できる場合だけ直す。
- 数学用語、定義文、命題、条件文を、期待される別表現に置き換えない。二直角、内角、平行線、公理、公準などは特に保守的に扱う。
- 音が似ている専門語候補が複数ある場合は、原文の音形に近い候補を選ぶ。例えば、工順/高順/好順/公順 は公準、行理 は公理、行為 は公理または公準のどちらか文脈で明らかな場合だけ直す。
- 同一チャンク内で同じ誤認識が反復する場合だけ、一貫して直す。別語を一つに統一しない。
- 講義や会話の流れを維持する。原文にない見出し、箇条書き、章立て、注釈を作らない。
- チャンク末尾で単語が途中で切れている場合、続きを補完しない。途中の語は途中のまま残す。

判断例:
- 「幾化学」は文脈上明らかなら「幾何学」に直してよい。
- 「微分析文学」は文脈上明らかなら「微分積分学」に直してよい。
- 「体制する」は文脈上明らかなら「体系化する」に直してよい。
- 「制度」は測量技術の文脈なら「精度」に直してよい。
- 「公準の4番」を「第五公準」に変えてはいけない。番号の推測は禁止。
- 「二直角」を「二角和」に変えてはいけない。数学用語の言い換えは禁止。
- 末尾の「非ユークリッ」を「非ユークリッド」に補完してはいけない。

出力形式:
- 校正済み本文のみを出力する。
- 思考過程、校正方針、自己評価、前置き、解説、差分、Markdown フェンス、引用符、JSON を出力しない。
"""

    private static func userPrompt(rawTranscript: String) -> String {
        """
以下の ASR 原文を、意味を変えずに校正してください。

<asr_transcript>
\(rawTranscript)
</asr_transcript>
"""
    }
}
