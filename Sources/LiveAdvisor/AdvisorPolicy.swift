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

    struct Pace {
        var startDelay: TimeInterval = 180
        var periodic: TimeInterval = 180
        var minimumGap: TimeInterval = 60
        var minimumCharacters = 40
    }

    static let automaticConfidence = 0.85
    static let automaticLimitPerMeeting = 5

    /// Words the person actually uses when taking something home. Spoken by others they mean nothing.
    static let takeawayWords = ["持ち帰", "確認します", "確認しておき", "確認してみ", "調べます", "調べておき", "調べてみ", "後ほど", "宿題"]
    /// Signs of a discussion that is stuck, from anyone in the room.
    static let directionWords = ["どうしましょう", "どうするか", "悩まし", "悩んで", "決めきれ", "決められ", "どっちが", "どちらが", "方向性", "判断が難しい", "落としどころ", "迷って"]

    /// A question from the other side is worth judging now rather than at the next periodic pass.
    static let questionWords = ["質問なんですが", "質問です", "質問があ", "教えてください", "教えていただ", "お聞きしたい", "聞きたいんですが", "伺いたい", "知りたい"]

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

    static func shouldRunAutomatically(_ item: JudgeOutput.Item, usedAutomatic: Int) -> Bool {
        guard usedAutomatic < automaticLimitPerMeeting else { return false }
        switch item.kind {
        case .takeaway: return item.declared_by_self && item.research
        case .question: return item.asked_by_others && item.research && item.confidence >= automaticConfidence
        case .direction: return item.confidence >= automaticConfidence
        case .risk: return false
        }
    }

    /// Untouched suggestions the judge itself rated "just in case" would only bury the useful cards.
    static let minimumCandidateConfidence = 0.6
    /// A glance this short is an accidental open, not reading.
    static let minimumSeenSeconds: TimeInterval = 1.5

    /// The one list the panel shows: whatever changed last comes first.
    static func feed(_ cards: [Card]) -> [Card] {
        cards
            .filter { $0.state != .candidate || $0.confidence >= minimumCandidateConfidence }
            .sorted { $0.updatedAt > $1.updatedAt }
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
