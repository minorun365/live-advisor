#if DEBUG
import Foundation

/// A made-up meeting for checking the panel's look. Debug builds only.
enum Fixture {
    static var cards: [Card] {
        var direction = Card(
            kind: .direction,
            title: "更新方式はどちらにする？",
            note: "止められる時間が決まらず議論が堂々巡り",
            research: false,
            confidence: 0.9,
            createdAt: Date().addingTimeInterval(-60)
        )
        direction.finishedAt = Date()
        direction.state = .done
        direction.recommendation = "両方式の停止時間を測ってから決める"
        direction.points = ["「30分」に根拠がない", "どちらの方式も未計測", "実測があれば費用も比べられる"]
        direction.options = [
            DirectionOption(name: "一括で更新", good: "手順が単純で準備が短い", bad: "更新の間はサイトを止める"),
            DirectionOption(name: "複製して切り替え", good: "停止を短くできる", bad: "準備と確認の手間が増える"),
        ]
        direction.askNext = "予約サイトは何分までなら止められますか"
        direction.unknowns = "使っている拡張機能が新しい版に対応しているか"

        var answer = Card(
            kind: .question,
            title: "PostgreSQL 14 はいつまで？",
            note: "相手からの質問",
            research: true,
            confidence: 0.92,
            createdAt: Date().addingTimeInterval(-300)
        )
        answer.finishedAt = Date().addingTimeInterval(-120)
        answer.state = .done
        answer.startedAutomatically = true
        answer.conclusion = "2026年11月12日で終了予定"
        answer.points = ["以後は修正が出ない"]
        answer.sources = [CardSource(title: "Versioning Policy（PostgreSQL 公式）", url: "https://www.postgresql.org/support/versioning/")]

        var candidate = Card(
            kind: .question,
            title: "論理複製で移らないものは？",
            note: "切り替え方式の案から",
            research: true,
            confidence: 0.7,
            createdAt: Date().addingTimeInterval(-400)
        )
        candidate.readAt = Date()
        var takeaway = Card(
            kind: .takeaway,
            title: "次回までに更新費用の概算を出す",
            note: "本人が持ち帰ると発言",
            research: false,
            confidence: 0.8,
            createdAt: Date().addingTimeInterval(-500)
        )
        takeaway.readAt = Date()

        var history = Card(
            kind: .history,
            title: "前回、何を決めた？",
            note: "",
            research: false,
            confidence: 1,
            createdAt: Date().addingTimeInterval(-600)
        )
        history.finishedAt = Date().addingTimeInterval(-600)
        history.state = .done
        history.readAt = Date()
        history.conclusion = "更新先は PostgreSQL 17 が第一候補"
        history.points = ["空くのは火曜の深夜2〜4時", "こちらの宿題：止められる時間の目安", "先方の宿題：検証環境の用意"]
        history.askNext = "検証環境は用意できそうですか"
        history.sources = [CardSource(title: "soramame-space/notes-2026-10-20.md", url: "file:///tmp/notes-2026-10-20.md")]
        return [direction, answer, candidate, takeaway, history]
    }
}
#endif
