import Foundation

enum Prompts {
    static let judgeSystem = """
    会議の文字起こしの差分を読み、本人が会議中に知っておくと助かることだけを拾う。
    拾うのは次の4種類だけ。
    question=相手から出た、その場で答えに詰まりそうな事実確認。
    takeaway=本人が持ち帰ると言ったこと。
    risk=前の発言や要点メモと食い違っていること。
    direction=複数の案で決めきれない、論点が堂々巡りしている、判断基準が曖昧なまま進んでいる議論。
    雑談・一般論・すでに答えが出た話は拾わない。無ければ cards は空にする。既出の項目と同じ論点は、言い方や種類を変えても拾わない。同じ話を question と takeaway の両方で出さず、本人が持ち帰ると言ったなら takeaway の1枚にまとめる。direction は1回に1枚まで。
    research は、公開情報を調べれば答えが出るものだけ true にする。製品の対応リージョン・上限・料金のように公式情報で分かる持ち帰りは、takeaway でも true にする。
    declared_by_self は「自分：」の行で本人が持ち帰りを宣言したときだけ true。asked_by_others は「相手：」の行の質問のときだけ true。話者が無い文字起こしでは文脈で判断し、迷えば false。
    search_questions は Web検索へ渡す問いの文。direction は判断材料になる問いを0〜2本、research が true の項目は1本書く。
    search_questions には会社名・人名・案件名・製品の社内呼称・金額を絶対に入れず、公開情報として一般化して書く。それ以外の項目は空配列。
    confidence は今すぐ答えがあると助かる度合い（0〜1）。0.9 は相手が本人へはっきり質問して本人が答えられていないとき、参加者が結論を求めたまま議論が止まっているとき。0.7 は知っておくと助かる程度。0.5 以下は念のため。title は25字以内、note は60字以内。memo は要点メモを250字以内で更新したもの。
    """

    static let judgeSchema = #"""
    {"type":"object","properties":{"memo":{"type":"string"},"cards":{"type":"array","items":{"type":"object","properties":{"kind":{"enum":["question","takeaway","risk","direction"]},"title":{"type":"string"},"note":{"type":"string"},"research":{"type":"boolean"},"confidence":{"type":"number"},"declared_by_self":{"type":"boolean"},"asked_by_others":{"type":"boolean"},"search_questions":{"type":"array","items":{"type":"string"}}},"required":["kind","title","note","research","confidence","declared_by_self","asked_by_others","search_questions"],"additionalProperties":false}}},"required":["memo","cards"],"additionalProperties":false}
    """#

    static func judgePrompt(memo: String, seen: [String], takeawayLines: [String], transcript: String) -> String {
        """
        本人の持ち帰り発言（既出の項目と同じ話でなければ、必ず takeaway として拾い declared_by_self を true にする）:
        \(takeawayLines.isEmpty ? "（無し）" : takeawayLines.map { "- \($0)" }.joined(separator: "\n"))

        要点メモ:
        \(memo.isEmpty ? "（まだ無い）" : memo)

        既出の項目:
        \(seen.isEmpty ? "（無し）" : seen.map { "- \($0)" }.joined(separator: "\n"))

        新しい文字起こし:
        \(transcript)
        """
    }

    static let researchSystem = """
    質問に、公式情報を確かめて短く答える。
    conclusion は結論を2文以内で、会議中に一目で読める長さにする。detail は判断に要る補足を120字以内。sources は確かめたページを1〜3本。
    分からなければ conclusion に分からないと書き、推測で埋めない。
    """

    static let researchSchema = #"""
    {"type":"object","properties":{"conclusion":{"type":"string"},"detail":{"type":"string"},"sources":{"type":"array","items":{"type":"object","properties":{"title":{"type":"string"},"url":{"type":"string"}},"required":["title","url"],"additionalProperties":false}}},"required":["conclusion","detail","sources"],"additionalProperties":false}
    """#

    static let directionSystem = """
    会議で詰まっている論点について、本人が次に議論をどちらへ進めるとよいかを提案する。
    論点を整理するだけで終わらせず、推奨を1つに決める。根拠は会議の発言と調査結果に限り、無い事実を足さない。
    recommendation は進める方向を60字以内で言い切る。why はそう判断した理由を120字以内。
    options は比較した案を2〜3個。name は15字以内、good と bad は各40字以内。
    ask_next はこの場で相手へ聞くとよい1問を50字以内。unknowns は判断を変えうる未確認事項を60字以内。無ければ空文字。
    体言止めや言い切りで書く。
    """

    static let directionSchema = #"""
    {"type":"object","properties":{"recommendation":{"type":"string"},"why":{"type":"string"},"options":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"good":{"type":"string"},"bad":{"type":"string"}},"required":["name","good","bad"],"additionalProperties":false}},"ask_next":{"type":"string"},"unknowns":{"type":"string"}},"required":["recommendation","why","options","ask_next","unknowns"],"additionalProperties":false}
    """#

    static func directionPrompt(card: Card, memo: String, transcript: String, findings: [String]) -> String {
        """
        論点:
        \(card.title)（\(card.note)）

        会議の要点メモ:
        \(memo)

        直近の発言:
        \(transcript)

        公開情報の調査結果:
        \(findings.isEmpty ? "（調査なし）" : findings.joined(separator: "\n"))
        """
    }
}
