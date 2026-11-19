import Foundation

/// Decides when Haiku and Opus run. Everything here is pure so the thresholds can be tested.
struct AdvisorPolicy {
    enum JudgeReason: String { case periodic, trigger, panel }

    enum MenuBarState: Equatable {
        case idle, listening, insight

        var imageName: String {
            switch self {
            case .idle: "MenuBarIdle"
            case .listening: "MenuBarListening"
            case .insight: "MenuBarInsight"
            }
        }

        /// Monochrome states follow the menu bar's appearance; the insight keeps its own color.
        var isTemplate: Bool { self != .insight }
    }

    static func menuBarState(isRunning: Bool, hasUnread: Bool) -> MenuBarState {
        if hasUnread { return .insight }
        return isRunning ? .listening : .idle
    }

    /// Half of what the person looks up is wanted within a minute of being said, so the judge keeps up with that.
    struct Pace {
        var startDelay: TimeInterval = 0
        var periodic: TimeInterval = 60
        var minimumGap: TimeInterval = 30
        var minimumCharacters = 40
    }

    static let automaticConfidence = 0.85
    /// Proposals read the whole discussion with Opus, so only the clearest few start on their own.
    static let automaticLimitPerMeeting = 5
    /// A public fact is looked up before anyone asks: an unanswered question on the panel is no help.
    static let researchLimitPerMeeting = 15

    /// Words the person actually uses when taking something home. Spoken by others they mean nothing.
    static let takeawayWords = ["持ち帰", "確認します", "確認しておき", "確認してみ", "調べます", "調べておき", "調べてみ", "後ほど", "宿題"]
    /// Signs of a discussion that is stuck, from anyone in the room.
    static let directionWords = ["どうしましょう", "どうするか", "悩まし", "悩んで", "決めきれ", "決められ", "どっちが", "どちらが", "方向性", "判断が難しい", "落としどころ", "迷って"]

    /// A question from the other side is worth judging now rather than at the next periodic pass.
    static let questionWords = ["質問なんですが", "質問です", "質問があ", "教えてください", "教えていただ", "お聞きしたい", "聞きたいんですが", "伺いたい", "知りたい"]

    /// Words that ask what was decided or quoted before. The answer sits in the person's notes, not on
    /// the web, and in practice the person typed these questions to Claude while the meeting went on.
    static let recordWords = ["前回", "この前", "こないだ", "以前", "でしたっけ", "だっけ", "見積", "どう決め", "決めてた", "決まってた", "宿題", "ネクストアクション", "経緯"]
    /// Each extra search of the notes costs about as much as the first, so a meeting gets a few.
    static let followUpHistoryLimit = 4
    static let followUpHistoryGap: TimeInterval = 120
    /// The first search starts as soon as there is this much to go on, instead of waiting for the judge.
    static let firstHistoryCharacters = 150

    static func asksRecord(_ line: TranscriptLine) -> Bool {
        recordWords.contains(where: line.text.contains)
    }

    /// The latest line that asks about the past, when another search of the notes is allowed now.
    static func followUpFocus(in lines: [TranscriptLine], now: Date, lastAt: Date?, used: Int, running: Bool) -> TranscriptLine? {
        guard !running, used < followUpHistoryLimit,
              lastAt.map({ now.timeIntervalSince($0) >= followUpHistoryGap }) ?? true else { return nil }
        return lines.last(where: asksRecord)
    }

    var pace = Pace()

    func judgeReason(
        now: Date,
        startedAt: Date,
        lastJudgeAt: Date?,
        unjudgedCharacters: Int,
        triggerPending: Bool,
        panelOpened: Bool
    ) -> JudgeReason? {
        guard unjudgedCharacters >= pace.minimumCharacters,
              now.timeIntervalSince(startedAt) >= pace.startDelay else { return nil }
        if now.timeIntervalSince(lastJudgeAt ?? startedAt) >= pace.periodic { return .periodic }
        let gapOK = lastJudgeAt.map { now.timeIntervalSince($0) >= pace.minimumGap } ?? true
        guard gapOK else { return nil }
        if panelOpened { return .panel }
        if triggerPending { return .trigger }
        return nil
    }

    static func trigger(in line: TranscriptLine) -> String? {
        if line.speaker != .others, let word = takeawayWords.first(where: line.text.contains) { return word }
        if line.speaker == .others, let word = questionWords.first(where: line.text.contains) { return word }
        return directionWords.first(where: line.text.contains)
    }

    /// Lines where the person said they would take something home, found without spending a token.
    static func takeawayLines(in lines: some Sequence<TranscriptLine>) -> [String] {
        lines.filter { $0.speaker != .others && takeawayWords.contains(where: $0.text.contains) }.map(\.text)
    }

    static func shouldRunAutomatically(_ item: JudgeOutput.Item, usedAutomatic: Int, usedResearch: Int) -> Bool {
        switch item.kind {
        case .question, .takeaway, .risk: return item.research && usedResearch < researchLimitPerMeeting
        case .direction: return usedAutomatic < automaticLimitPerMeeting && item.confidence >= automaticConfidence
        case .history, .task: return false
        }
    }

    /// Untouched suggestions the judge itself rated "just in case" would only bury the useful cards.
    static let minimumCandidateConfidence = 0.6
    /// A glance this short is an accidental open, not reading.
    static let minimumSeenSeconds: TimeInterval = 1.5

    /// The one list the panel shows: whatever changed last comes first.
    static func feed(_ cards: [Card]) -> [Card] {
        cards.filter(isShown).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// A question without its answer only repeats what was just said, so it waits until the answer is in.
    /// A takeaway or a contradiction says something on its own and shows at once.
    static func isShown(_ card: Card) -> Bool {
        switch card.state {
        case .done, .failed: return true
        case .running: return card.isRequested
        case .candidate:
            return (card.kind == .takeaway || card.kind == .risk) && card.confidence >= minimumCandidateConfidence
        }
    }

    /// The lookup button reads what was said in the last two minutes, the window in which a person
    /// usually decides something needs checking. A quiet stretch falls back to the latest lines.
    static let lookupWindow: TimeInterval = 120
    static let lookupMinimumCharacters = 80
    static let lookupFallbackCharacters = 1500

    static func lookupLines(_ lines: [TranscriptLine], now: Date) -> [TranscriptLine] {
        let recent = lines.filter { now.timeIntervalSince($0.at) <= lookupWindow }
        if recent.reduce(0, { $0 + $1.text.count }) >= lookupMinimumCharacters { return recent }
        var picked: [TranscriptLine] = []
        var count = 0
        for line in lines.reversed() {
            guard count < lookupFallbackCharacters else { break }
            picked.insert(line, at: 0)
            count += line.text.count
        }
        return picked
    }

    /// The request button reads the last five minutes: a request is usually said, discussed, then agreed.
    static let taskWindow: TimeInterval = 300

    static func taskLines(_ lines: [TranscriptLine], now: Date) -> [TranscriptLine] {
        let recent = lines.filter { now.timeIntervalSince($0.at) <= taskWindow }
        return recent.isEmpty ? Array(lines.suffix(20)) : recent
    }

    static let taskLimitPerPress = 3

    /// The first message of the new session. It never starts with "/", which the input box would take as a command.
    static func handoffText(instruction: String, quote: String, meeting: String?, folder: String?) -> String {
        var lines = [
            "会議中に頼まれた作業です。内容と宛先を確かめてから進めてください。",
            "",
            "やること：\(instruction)",
            "根拠の発言：「\(quote)」",
        ]
        if let meeting, !meeting.isEmpty { lines.append("会議：\(meeting)") }
        if let folder { lines.append("文字起こしの場所：\(folder)") }
        return lines.joined(separator: "\n")
    }

    /// A new session in the Claude app with the text already typed. Sending it is left to the person.
    static func handoffURL(_ text: String) -> URL? {
        // Everything but letters and digits is escaped: a bare "+" would come back as a space.
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        allowed.insert(charactersIn: "-._~")
        guard let query = text.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "claude://code/new?q=\(query)")
    }

    /// True when the card sat in an open panel long enough to have been noticed.
    static func wasSeen(_ card: Card, openedAt: Date, closedAt: Date) -> Bool {
        closedAt.timeIntervalSince(max(openedAt, card.updatedAt)) >= minimumSeenSeconds
    }

    static let titleLimit = 18
    static let answerLimit = 25
    static let pointLimit = 25

    static func titleRequest(_ title: String, kind: CardKind) -> TightenRequest {
        TightenRequest(text: title, limit: titleLimit, asks: kind != .takeaway)
    }

    /// A prompt asks for these limits but cannot enforce them, so the result is measured here.
    static func needsTightening(_ request: TightenRequest) -> Bool {
        if request.text.count > request.limit { return true }
        return request.asks && !(request.text.hasSuffix("？") || request.text.hasSuffix("?"))
    }

    /// Takes the rewrite only when it improves on the original. Nothing is ever cut mid-sentence.
    static func pick(_ request: TightenRequest, rewritten: String) -> String {
        let text = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return request.text }
        let fixed = TightenRequest(text: text, limit: request.limit, asks: request.asks)
        if !needsTightening(fixed) || text.count < request.text.count { return text }
        return request.text
    }

    /// True when `title` asks what an earlier card already asked, allowing for rewording.
    static func isDuplicate(_ title: String, of existing: [String]) -> Bool {
        let grams = bigrams(title)
        return existing.contains { other in
            let otherGrams = bigrams(other)
            guard !grams.isEmpty, !otherGrams.isEmpty else { return title == other }
            let shared = grams.intersection(otherGrams).count
            return Double(shared) / Double(grams.union(otherGrams).count) >= 0.6
        }
    }

    private static func bigrams(_ text: String) -> Set<String> {
        let characters = Array(text.filter { !$0.isWhitespace && !$0.isPunctuation })
        guard characters.count >= 2 else { return [] }
        return Set((0..<(characters.count - 1)).map { String(characters[$0...($0 + 1)]) })
    }
}
