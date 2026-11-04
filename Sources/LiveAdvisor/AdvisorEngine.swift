import Foundation

/// The three layers in one place: a watcher that spends nothing, Haiku picks what matters,
/// Opus answers the few things that earn it.
@MainActor
final class AdvisorEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case paused
        case running
        case finished
    }

    struct Keyword: Identifiable {
        let id = UUID()
        let word: String
        let excerpt: String
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var cards: [Card] = []
    @Published private(set) var keywords: [Keyword] = []
    @Published private(set) var isJudging = false
    @Published private(set) var problem: String?
    @Published private(set) var hasUnread = false

    private let environment = ProcessInfo.processInfo.environment
    private lazy var home = FileManager.default.homeDirectoryForCurrentUser
    private lazy var sessionsRoot: URL = environment["LIVE_ADVISOR_SESSIONS_ROOT"].map { URL(fileURLWithPath: $0) }
        ?? home.appendingPathComponent("Library/Application Support/LiveTranslator/Sessions", isDirectory: true)

    private var policy: AdvisorPolicy = {
        var policy = AdvisorPolicy()
        if ProcessInfo.processInfo.environment["LIVE_ADVISOR_FAST"] == "1" {
            policy.pace = .init(startDelay: 10, periodic: 30, minimumGap: 15, minimumCharacters: 40)
        }
        return policy
    }()

    private var watcher: SessionWatcher?
    private var ticker: Timer?
    private var folder: URL?
    private var startedAt = Date()
    private var transcript: [TranscriptLine] = []
    private var judgedCount = 0
    private var memo = ""
    private var lastJudgeAt: Date?
    private var triggerPending = false
    private var panelOpenPending = false
    private var automaticUsed = 0
    private var queue: [String] = []
    private var jobRunning = false
    private var panelVisible = false

    func start() {
        loadPreviousCards()
        let watcher = SessionWatcher(root: sessionsRoot)
        watcher.onStart = { [weak self] folder, startedAt in
            Task { @MainActor in self?.recordingStarted(folder: folder, startedAt: startedAt) }
        }
        watcher.onLines = { [weak self] lines in
            Task { @MainActor in self?.received(lines) }
        }
        watcher.onEnd = { [weak self] in
            Task { @MainActor in self?.recordingEnded() }
        }
        watcher.start()
        self.watcher = watcher
    }

    // MARK: Recording lifecycle

    private func recordingStarted(folder: URL, startedAt: Date) {
        self.folder = folder
        self.startedAt = startedAt
        transcript = []
        judgedCount = 0
        memo = ""
        lastJudgeAt = nil
        triggerPending = false
        panelOpenPending = false
        automaticUsed = 0
        queue = []
        cards = []
        keywords = []
        problem = nil
        hasUnread = false

        phase = .running

        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    private func received(_ lines: [TranscriptLine]) {
        transcript.append(contentsOf: lines)
        for line in lines {
            guard let word = AdvisorPolicy.trigger(in: line) else { continue }
            triggerPending = true
            if phase != .running {
                keywords.insert(Keyword(word: word, excerpt: String(line.text.prefix(60))), at: 0)
                keywords = Array(keywords.prefix(8))
            }
        }
        evaluate()
    }

    private func recordingEnded() {
        ticker?.invalidate()
        ticker = nil
        phase = .finished
        save()
        writeSummary()
    }

    // MARK: User actions

    func panelOpened() {
        panelVisible = true
        hasUnread = false
        panelOpenPending = true
        evaluate()
    }

    func panelClosed() {
        panelVisible = false
    }

    func enableForThisMeeting() {
        guard phase == .paused else { return }
        phase = .running
        evaluate()
    }

    func disableForThisMeeting() {
        guard phase == .running else { return }
        phase = .paused
    }

    func run(cardID: String) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }), cards[index].state != .running else { return }
        cards[index].state = .running
        cards[index].failure = nil
        enqueue(cardID)
        save()
    }

    func dismiss(cardID: String) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index].dismissed = true
        save()
    }

    // MARK: Judge

    private func evaluate() {
        guard phase == .running, !isJudging else { return }
        let pending = transcript[min(judgedCount, transcript.count)...]
        let characters = pending.reduce(0) { $0 + $1.text.count }
        let reason = policy.judgeReason(
            now: Date(),
            startedAt: startedAt,
            lastJudgeAt: lastJudgeAt,
            unjudgedCharacters: characters,
            triggerPending: triggerPending,
            panelOpened: panelOpenPending
        )
        panelOpenPending = false
        guard reason != nil else { return }
        judge(
            upTo: transcript.count,
            takeawayLines: AdvisorPolicy.takeawayLines(in: pending),
            text: Self.tail(pending.map(\.rendered).joined(separator: "\n"), limit: 6000)
        )
    }

    private func judge(upTo end: Int, takeawayLines: [String], text: String) {
        isJudging = true
        triggerPending = false
        lastJudgeAt = Date()
        let seen = cards.map(\.title)
        let call = ClaudeCall(
            job: .judge,
            model: "haiku",
            effort: "low",
            system: Prompts.judgeSystem,
            schema: Prompts.judgeSchema,
            timeout: 60,
            prompt: Prompts.judgePrompt(memo: memo, seen: seen, takeawayLines: takeawayLines, transcript: text)
        )
        Task {
            let result = await ClaudeRunner.run(call)
            isJudging = false
            guard let data = result.structured,
                  let output = try? JSONDecoder().decode(JudgeOutput.self, from: data) else {
                report(result.failure)
                return
            }
            problem = nil
            judgedCount = end
            memo = output.memo
            accept(output.cards)
            if !takeawayLines.isEmpty, !output.cards.contains(where: { $0.kind == .takeaway }) {
                startLatestResearchCandidate()
            }
            save()
            // The last judge can land after the meeting ended.
            if phase == .finished { writeSummary() }
        }
    }

    private func accept(_ items: [JudgeOutput.Item]) {
        for item in items where !AdvisorPolicy.isDuplicate(item.title, of: cards.map(\.title)) {
            // A stuck discussion keeps rewording itself. Only the latest untouched suggestion stays.
            if item.kind == .direction {
                cards.removeAll { $0.kind == .direction && $0.state == .candidate && !$0.dismissed }
            }
            var card = Card(
                kind: item.kind,
                title: item.title,
                note: item.note,
                research: item.research,
                confidence: item.confidence,
                searchQuestions: item.search_questions,
                createdAt: Date()
            )
            var runNow = AdvisorPolicy.shouldRunAutomatically(item, usedAutomatic: automaticUsed)
            // One discussion should not buy the same advice twice. Later rewordings wait for a press.
            if item.kind == .direction, hasRecentDirection { runNow = false }
            #if DEBUG
            // The end-to-end test presses the button a person would press on a suggestion.
            if environment["LIVE_ADVISOR_PRESS_DIRECTION"] == "1", item.kind == .direction { runNow = true }
            #endif
            if runNow {
                automaticUsed += 1
                card.startedAutomatically = true
                card.state = .running
                cards.insert(card, at: 0)
                enqueue(card.id)
            } else {
                cards.insert(card, at: 0)
            }
        }
    }

    /// A question often becomes a candidate just before the person says "I'll check". The judge then
    /// sees the same topic and stays silent, so the promise is honoured here instead of by the model.
    private func startLatestResearchCandidate() {
        guard automaticUsed < AdvisorPolicy.automaticLimitPerMeeting,
              let card = cards.first(where: {
                  $0.kind == .question && $0.state == .candidate && !$0.dismissed && $0.research
              }) else { return }
        automaticUsed += 1
        update(card.id) { $0.startedAutomatically = true }
        run(cardID: card.id)
    }

    private var hasRecentDirection: Bool {
        cards.contains {
            $0.kind == .direction && !$0.dismissed && ($0.state == .running || $0.state == .done)
                && Date().timeIntervalSince($0.createdAt) < 600
        }
    }

    // MARK: Opus jobs

    private func enqueue(_ id: String) {
        queue.append(id)
        runNextJob()
    }

    /// One job at a time, so a burst of questions cannot spend the meeting's allowance at once.
    private func runNextJob() {
        guard !jobRunning, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let card = cards.first(where: { $0.id == id }) else {
            runNextJob()
            return
        }
        jobRunning = true
        Task {
            if card.kind == .direction {
                await runDirection(card)
            } else {
                await runResearch(card)
            }
            jobRunning = false
            save()
            // A job can outlive the meeting, so the summary is rewritten when it lands.
            if phase == .finished { writeSummary() }
            runNextJob()
        }
    }

    private func runResearch(_ card: Card) async {
        guard let question = card.searchQuestions.first ?? (card.research ? card.title : nil) else {
            finish(card.id, failure: "調査に渡せる問いがありません")
            return
        }
        recordQuery(question)
        let result = await ClaudeRunner.run(webCall(question: question))
        guard let data = result.structured, let output = try? JSONDecoder().decode(ResearchOutput.self, from: data) else {
            finish(card.id, failure: Self.message(for: result.failure))
            return
        }
        update(card.id) {
            $0.conclusion = output.conclusion
            $0.detail = output.detail
            $0.sources = output.sources
        }
        finish(card.id, failure: nil)
    }

    /// Two stages so the search route never sees the meeting: the web stage gets anonymous questions
    /// only, and the reasoning stage that reads the discussion has no tools at all.
    private func runDirection(_ card: Card) async {
        // What this meeting already found counts, so the advice does not call it unknown.
        var findings = cards.compactMap { other -> String? in
            guard other.id != card.id, other.state == .done, let conclusion = other.conclusion else { return nil }
            return "問い：\(other.title)\n結論：\(conclusion)"
        }
        for question in card.searchQuestions.prefix(2) {
            recordQuery(question)
            let result = await ClaudeRunner.run(webCall(question: question))
            if let data = result.structured, let output = try? JSONDecoder().decode(ResearchOutput.self, from: data) {
                findings.append("問い：\(question)\n結論：\(output.conclusion)\n補足：\(output.detail)")
                update(card.id) { $0.sources = Array(($0.sources + output.sources.prefix(2)).prefix(4)) }
            }
        }

        let recent = Self.tail(transcript.map(\.rendered).joined(separator: "\n"), limit: 4000)
        let call = ClaudeCall(
            job: .direction,
            model: "opus",
            effort: "medium",
            system: Prompts.directionSystem,
            schema: Prompts.directionSchema,
            budgetUSD: 0.15,
            timeout: 60,
            prompt: Prompts.directionPrompt(card: card, memo: memo, transcript: recent, findings: findings)
        )
        let result = await ClaudeRunner.run(call)
        guard let data = result.structured, let output = try? JSONDecoder().decode(DirectionOutput.self, from: data) else {
            finish(card.id, failure: Self.message(for: result.failure))
            return
        }
        update(card.id) {
            $0.recommendation = output.recommendation
            $0.reasoning = output.why
            $0.options = output.options
            $0.askNext = output.ask_next
            $0.unknowns = output.unknowns.isEmpty ? nil : output.unknowns
        }
        finish(card.id, failure: nil)
    }

    private func webCall(question: String) -> ClaudeCall {
        ClaudeCall(
            job: .research,
            model: "opus",
            effort: "low",
            system: Prompts.researchSystem,
            schema: Prompts.researchSchema,
            tools: ["WebSearch", "WebFetch"],
            budgetUSD: 0.30,
            timeout: 90,
            prompt: question
        )
    }

    private func update(_ id: String, _ change: (inout Card) -> Void) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        change(&cards[index])
    }

    private func finish(_ id: String, failure: String?) {
        update(id) {
            $0.state = failure == nil ? .done : .failed
            $0.failure = failure
            $0.finishedAt = Date()
        }
        if failure == nil, !panelVisible {
            hasUnread = true
        }
    }

    private func report(_ failure: ClaudeResult.Failure?) {
        problem = Self.message(for: failure)
    }

    private static func message(for failure: ClaudeResult.Failure?) -> String {
        switch failure {
        case .timeout: return "時間内に終わらなかったので打ち切りました"
        case .budget: return "上限額に達したので打ち切りました"
        case .notFound: return "claude コマンドが見つかりません"
        case .notLoggedIn: return "Claude Code にログインしてください"
        case .limitReached: return "Claude の利用上限に達した可能性があります"
        default: return "判定を呼び出せませんでした"
        }
    }

    private static func tail(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.suffix(limit))
    }

    // MARK: Files in the meeting folder

    private func recordQuery(_ question: String) {
        guard let folder else { return }
        let record: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "question": question]
        guard var line = try? JSONSerialization.data(withJSONObject: record) else { return }
        line.append(0x0A)
        let file = folder.appendingPathComponent("advisor-queries.jsonl")
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        } else {
            try? line.write(to: file)
        }
    }

    private func save() {
        guard let folder else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(cards) {
            try? data.write(to: folder.appendingPathComponent("advisor-cards.json"), options: .atomic)
        }
    }

    /// A readable record beside the transcript. Marked as AI output so it never passes for a decision.
    private func writeSummary() {
        guard let folder else { return }
        let visible = cards.filter { !$0.dismissed }
        guard !visible.isEmpty else { return }
        var lines = ["# 助言さんの記録", "", "会議中に AI が提案した内容で、決定事項ではない。", ""]
        if !memo.isEmpty { lines += ["## 要点メモ", "", memo, ""] }
        for card in visible {
            lines.append("## [\(card.kind.label)] \(card.title)")
            lines.append("")
            lines.append(card.note)
            if let recommendation = card.recommendation { lines.append("- 推奨：\(recommendation)") }
            if let reasoning = card.reasoning { lines.append("- 理由：\(reasoning)") }
            for option in card.options { lines.append("- 案「\(option.name)」：\(option.good) ／ \(option.bad)") }
            if let ask = card.askNext, !ask.isEmpty { lines.append("- 聞くとよいこと：\(ask)") }
            if let unknowns = card.unknowns { lines.append("- 未確認：\(unknowns)") }
            if let conclusion = card.conclusion { lines.append("- 結論：\(conclusion)") }
            if let detail = card.detail, !detail.isEmpty { lines.append("- 補足：\(detail)") }
            for source in card.sources { lines.append("- 出典：\(source.title) \(source.url)") }
            lines.append("")
        }
        try? lines.joined(separator: "\n").write(
            to: folder.appendingPathComponent("advisor.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// After a restart, show the results from the last 12 hours until the next recording starts.
    /// Only finished results come back: the transcript behind a candidate is gone.
    private func loadPreviousCards() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: sessionsRoot.path),
              let newest = names.filter({ $0.first?.isNumber == true }).sorted(by: >).first,
              let started = SessionWatcher.startDate(fromFolderName: newest),
              Date().timeIntervalSince(started) < 12 * 3600 else { return }
        let file = sessionsRoot.appendingPathComponent(newest).appendingPathComponent("advisor-cards.json")
        guard let data = try? Data(contentsOf: file) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = ((try? decoder.decode([Card].self, from: data)) ?? []).filter { $0.state == .done && !$0.dismissed }
        if !saved.isEmpty {
            cards = saved
            phase = .finished
        }
    }

    #if DEBUG
    func loadFixture() {
        phase = .running
        cards = Fixture.cards
    }

    func previewMenuBar(_ state: String) {
        phase = state == "idle" ? .idle : .running
        hasUnread = state == "insight"
    }
    #endif
}
