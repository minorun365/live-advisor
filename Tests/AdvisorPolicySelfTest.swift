import Foundation

@main
struct AdvisorPolicySelfTest {
    static func main() throws {
        try judgeTiming()
        try automaticRules()
        try duplicates()
        try config()
        try tailer()
        try feed()
        try menuBar()
        print("AdvisorPolicySelfTest OK")
    }

    static func judgeTiming() throws {
        let policy = AdvisorPolicy()
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func reason(at seconds: TimeInterval, last: TimeInterval? = nil, characters: Int = 500, trigger: Bool = false, panel: Bool = false) -> AdvisorPolicy.JudgeReason? {
            policy.judgeReason(
                now: start.addingTimeInterval(seconds),
                startedAt: start,
                lastJudgeAt: last.map { start.addingTimeInterval($0) },
                unjudgedCharacters: characters,
                triggerPending: trigger,
                panelOpened: panel
            )
        }
        try check(reason(at: 179, panel: true) == nil, "最初の3分はパネルを開いても動かない")
        try check(reason(at: 180) == .periodic, "3分で最初の定期判定")
        try check(reason(at: 180, characters: 10) == nil, "新しい文字が少なければ動かない")
        try check(reason(at: 300, last: 200) == nil, "前回から3分までは定期判定しない")
        try check(reason(at: 300, last: 200, panel: true) == .panel, "1分あければパネルで動く")
        try check(reason(at: 300, last: 200, trigger: true) == .trigger, "1分あければきっかけ語で動く")
        try check(reason(at: 250, last: 200, trigger: true) == nil, "きっかけ語でも1分はあける")
        try check(reason(at: 380, last: 200) == .periodic, "前回から3分で定期判定")

        let me = TranscriptLine(at: start, speaker: .me, text: "それは持ち帰って確認します")
        let them = TranscriptLine(at: start, speaker: .others, text: "それは持ち帰って確認します")
        let stuck = TranscriptLine(at: start, speaker: .others, text: "どちらがいいか判断が難しいですね")
        try check(AdvisorPolicy.trigger(in: me) != nil, "本人の持ち帰りはきっかけになる")
        try check(AdvisorPolicy.trigger(in: them) == nil, "相手の持ち帰りはきっかけにしない")
        try check(AdvisorPolicy.trigger(in: stuck) != nil, "議論の詰まりは誰の発言でもきっかけになる")
        let asked = TranscriptLine(at: start, speaker: .others, text: "そこで質問なんですが、今の版はいつまで使えますか")
        let askedByMe = TranscriptLine(at: start, speaker: .me, text: "そこで質問なんですが、今の版はいつまで使えますか")
        try check(AdvisorPolicy.trigger(in: asked) != nil, "相手の質問はきっかけになる")
        try check(AdvisorPolicy.trigger(in: askedByMe) == nil, "本人の質問はきっかけにしない")
    }

    static func automaticRules() throws {
        func item(_ kind: CardKind, research: Bool = true, confidence: Double = 0.9, own: Bool = false, others: Bool = false) -> JudgeOutput.Item {
            JudgeOutput.Item(kind: kind, title: "t", note: "n", research: research, confidence: confidence, declared_by_self: own, asked_by_others: others, search_questions: [])
        }
        try check(AdvisorPolicy.shouldRunAutomatically(item(.takeaway, own: true), usedAutomatic: 0), "本人の持ち帰りは自動")
        try check(!AdvisorPolicy.shouldRunAutomatically(item(.takeaway, research: false, own: true), usedAutomatic: 0), "調べて答えが出ない持ち帰りは自動にしない")
        try check(!AdvisorPolicy.shouldRunAutomatically(item(.takeaway), usedAutomatic: 0), "宣言のない持ち帰りは自動にしない")
        try check(AdvisorPolicy.shouldRunAutomatically(item(.question, others: true), usedAutomatic: 0), "確信度の高い相手の質問は自動")
        try check(!AdvisorPolicy.shouldRunAutomatically(item(.question, confidence: 0.84, others: true), usedAutomatic: 0), "確信度0.85未満は候補")
        try check(!AdvisorPolicy.shouldRunAutomatically(item(.question), usedAutomatic: 0), "相手の質問でなければ候補")
        try check(AdvisorPolicy.shouldRunAutomatically(item(.direction, research: false), usedAutomatic: 0), "確信度の高い論点は自動")
        try check(!AdvisorPolicy.shouldRunAutomatically(item(.direction, confidence: 0.6), usedAutomatic: 0), "確信度の低い論点は候補")
        try check(!AdvisorPolicy.shouldRunAutomatically(item(.risk), usedAutomatic: 0), "食い違いは自動にしない")
        try check(!AdvisorPolicy.shouldRunAutomatically(item(.takeaway, own: true), usedAutomatic: 5), "1会議5回まで")
    }

    static func duplicates() throws {
        try check(AdvisorPolicy.isDuplicate("PostgreSQL 14のサポート期限はいつか", of: ["PostgreSQL 14のサポート期限はいつですか"]), "言い回し違いは同じ問い")
        try check(!AdvisorPolicy.isDuplicate("料金の概算はいくらか", of: ["PostgreSQL 14のサポート期限はいつか"]), "別の問いは通す")
    }

    static func config() throws {
        try check(AppConfig.parse(Data("{}".utf8)).claudeCommand == "claude", "設定が無ければ claude")
        try check(AppConfig.parse(Data("{\"claudeCommand\":\"\"}".utf8)).claudeCommand == "claude", "空なら claude")
        try check(AppConfig.parse(Data("壊れた設定".utf8)).claudeCommand == "claude", "壊れた設定は既定へ戻す")
        try check(AppConfig.parse(Data("{\"claudeCommand\":\"my-claude\"}".utf8)).claudeCommand == "my-claude", "指定を読む")

        let installed: Set<String> = ["/home/.local/bin/claude", "/opt/tools/my-claude", "/home/bin/my-claude"]
        func resolve(_ command: String) -> String? {
            AppConfig.resolve(command: command, searchPath: ["/home/.local/bin", "/usr/bin"], home: "/home", isExecutable: installed.contains)
        }
        try check(resolve("claude") == "/home/.local/bin/claude", "名前は探索パスから引く")
        try check(resolve("missing") == nil, "無ければ nil")
        try check(resolve("/opt/tools/my-claude") == "/opt/tools/my-claude", "絶対パスはそのまま")
        try check(resolve("~/bin/my-claude") == "/home/bin/my-claude", "チルダを展開する")
    }

    static func tailer() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("advisor-tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        func event(_ text: String, final: Bool, speaker: String? = "others") -> String {
            var payload = ["text": text, "final": String(final)]
            payload["speaker"] = speaker
            let data = try! JSONSerialization.data(withJSONObject: ["type": "recognition", "timestamp": "2026-11-02T05:00:00Z", "payload": payload], options: [.withoutEscapingSlashes])
            return String(data: data, encoding: .utf8)! + "\n"
        }
        try (event("途中", final: false) + event("確定一", final: true)).write(to: file, atomically: true, encoding: .utf8)
        let tailer = EventTailer(url: file)
        let first = tailer.poll()
        try check(first.lines.map(\.text) == ["確定一"], "確定の行だけ読む")
        try check(first.lines.first?.speaker == .others, "話者を読む")
        try check(!first.stopped, "まだ止まっていない")

        let handle = try FileHandle(forWritingTo: file)
        _ = try handle.seekToEnd()
        let second = event("確定二", final: true, speaker: nil)
        let bytes = Data(second.utf8)
        try handle.write(contentsOf: bytes.prefix(10))
        try check(tailer.poll().lines.isEmpty, "書きかけの行は読まない")
        try handle.write(contentsOf: bytes.dropFirst(10))
        let completed = tailer.poll()
        try check(completed.lines.map(\.text) == ["確定二"], "続きから1行だけ読む")
        try check(completed.lines.first?.speaker == .unknown, "話者なしは不明扱い")
        try check(completed.lines.first?.rendered == "確定二", "話者なしはラベルを付けない")
        try handle.write(contentsOf: Data("{\"type\":\"session_stopped\",\"payload\":{},\"timestamp\":\"2026-11-02T05:00:00Z\"}\n".utf8))
        try handle.close()
        try check(tailer.poll().stopped, "停止を検知する")
        try check(!tailer.poll().grew, "増えていなければ何もしない")
    }

    static func feed() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        func card(_ title: String, at offset: TimeInterval, state: CardState = .done, confidence: Double = 0.9) -> Card {
            var card = Card(kind: .question, title: title, note: "", research: true, confidence: confidence, createdAt: start.addingTimeInterval(offset))
            card.state = state
            return card
        }
        var finishedLate = card("先に出て後から答えが出た", at: 0)
        finishedLate.finishedAt = start.addingTimeInterval(100)
        let order = AdvisorPolicy.feed([card("古い", at: 10), card("新しい", at: 50), finishedLate]).map(\.title)
        try check(order == ["先に出て後から答えが出た", "新しい", "古い"], "最後に変わったものが一番上に来る")
        try check(AdvisorPolicy.feed([card("念のため", at: 0, state: .candidate, confidence: 0.5)]).isEmpty, "確信度の低い候補は並べない")
        try check(AdvisorPolicy.feed([card("念のための結果", at: 0, state: .done, confidence: 0.5)]).count == 1, "答えが出たものは確信度によらず並べる")

        var unread = card("未読", at: 0)
        try check(unread.isUnread, "読むまでは未読")
        unread.readAt = start.addingTimeInterval(10)
        try check(!unread.isUnread, "読めば既読")
        unread.finishedAt = start.addingTimeInterval(20)
        try check(unread.isUnread, "読んだ後に答えが出たらまた未読")

        let shown = card("開く前からある", at: 0)
        let opened = start.addingTimeInterval(100)
        try check(!AdvisorPolicy.wasSeen(shown, openedAt: opened, closedAt: opened.addingTimeInterval(1)), "開いてすぐ閉じたら既読にしない")
        try check(AdvisorPolicy.wasSeen(shown, openedAt: opened, closedAt: opened.addingTimeInterval(3)), "開いて少し経てば既読")
        let arrived = card("閉じる直前に来た", at: 102)
        try check(!AdvisorPolicy.wasSeen(arrived, openedAt: opened, closedAt: opened.addingTimeInterval(3)), "閉じる直前に来たものは未読のまま")
    }

    static func menuBar() throws {
        try check(AdvisorPolicy.menuBarState(isRunning: false, hasUnread: false) == .idle, "動いていなければ待機中")
        try check(AdvisorPolicy.menuBarState(isRunning: true, hasUnread: false) == .listening, "動いていれば会議中")
        try check(AdvisorPolicy.menuBarState(isRunning: true, hasUnread: true) == .insight, "未読があれば会議中より優先")
        try check(AdvisorPolicy.menuBarState(isRunning: false, hasUnread: true) == .insight, "会議の後でも未読があれば知らせる")
        try check(AdvisorPolicy.MenuBarState.listening.isTemplate, "単色の状態はバーの明暗へ合わせる")
        try check(!AdvisorPolicy.MenuBarState.insight.isTemplate, "インサイトは色を保つ")
    }

    static func check(_ condition: Bool, _ label: String) throws {
        guard condition else { throw TestFailure(label: label) }
    }

    struct TestFailure: Error, CustomStringConvertible {
        let label: String
        var description: String { "NG: \(label)" }
    }
}
