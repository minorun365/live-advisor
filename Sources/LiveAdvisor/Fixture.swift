#if DEBUG
import Foundation

/// A made-up meeting for checking the panel's look. Debug builds only.
enum Fixture {
    static var cards: [Card] {
        var direction = Card(
            kind: .direction,
            title: "データベースの更新方式をどちらにするか",
            note: "止められる時間が決まらず議論が堂々巡り",
            research: false,
            confidence: 0.9,
            createdAt: Date()
        )
        direction.state = .done
        direction.recommendation = "検証環境で両方式の停止時間を測ってから方式を決める"
        direction.reasoning = "「止められるのは30分」に根拠がなく、どちらの方式も停止時間を測っていない。実測があれば、費用を含めて比べられる。"
        direction.options = [
            DirectionOption(name: "一括で更新", good: "手順が単純で準備が短い", bad: "更新の間はサイトを止める"),
            DirectionOption(name: "複製して切り替え", good: "停止を短くできる", bad: "準備と確認の手間が増える"),
        ]
        direction.askNext = "予約サイトは何分までなら止められますか"
        direction.unknowns = "使っている拡張機能が新しい版に対応しているか"

        var answer = Card(
            kind: .question,
            title: "PostgreSQL 14 のサポートはいつまでか",
            note: "相手からの質問",
            research: true,
            confidence: 0.92,
            createdAt: Date()
        )
        answer.state = .done
        answer.startedAutomatically = true
        answer.conclusion = "2026年11月12日が最後のリリース予定で、以後は修正が出ない"
        answer.detail = "公式のバージョン方針の一覧で確認した。"
        answer.sources = [CardSource(title: "Versioning Policy（PostgreSQL 公式）", url: "https://www.postgresql.org/support/versioning/")]

        let candidate = Card(
            kind: .question,
            title: "論理レプリケーションで複製されないものは何か",
            note: "切り替え方式の案から",
            research: true,
            confidence: 0.7,
            createdAt: Date()
        )
        let takeaway = Card(
            kind: .takeaway,
            title: "次回までに更新費用の概算を出す",
            note: "本人が持ち帰ると発言",
            research: false,
            confidence: 0.8,
            createdAt: Date()
        )
        return [direction, answer, candidate, takeaway]
    }
}
#endif
