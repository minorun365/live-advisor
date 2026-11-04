import Foundation

struct TranscriptLine: Equatable {
    enum Speaker: String { case me, others, unknown }

    let at: Date
    let speaker: Speaker
    let text: String

    /// The form the judge reads. Sessions without speaker labels stay unlabeled instead of guessing.
    var rendered: String {
        switch speaker {
        case .me: return "自分：\(text)"
        case .others: return "相手：\(text)"
        case .unknown: return text
        }
    }
}

enum CardKind: String, Codable {
    case question, takeaway, risk, direction

    var label: String {
        switch self {
        case .question: return "相手の質問"
        case .takeaway: return "持ち帰り"
        case .risk: return "食い違い"
        case .direction: return "論点"
        }
    }
}

enum CardState: String, Codable {
    case candidate, running, done, failed
}

struct CardSource: Codable, Hashable {
    let title: String
    let url: String
}

struct DirectionOption: Codable, Hashable {
    let name: String
    let good: String
    let bad: String
}

struct Card: Codable, Identifiable {
    var id = UUID().uuidString
    var kind: CardKind
    var title: String
    var note: String
    var research: Bool
    var confidence: Double
    var searchQuestions: [String] = []
    var state: CardState = .candidate
    var startedAutomatically = false
    var createdAt: Date
    var finishedAt: Date?
    var dismissed = false

    var conclusion: String?
    var detail: String?
    var sources: [CardSource] = []

    var recommendation: String?
    var reasoning: String?
    var options: [DirectionOption] = []
    var askNext: String?
    var unknowns: String?

    var failure: String?

    var canRun: Bool { kind == .direction || research }
}

/// What Haiku returns for one pass over the new transcript.
struct JudgeOutput: Decodable {
    struct Item: Decodable {
        let kind: CardKind
        let title: String
        let note: String
        let research: Bool
        let confidence: Double
        let declared_by_self: Bool
        let asked_by_others: Bool
        let search_questions: [String]
    }

    let memo: String
    let cards: [Item]
}

struct ResearchOutput: Decodable {
    let conclusion: String
    let detail: String
    let sources: [CardSource]
}

struct DirectionOutput: Decodable {
    let recommendation: String
    let why: String
    let options: [DirectionOption]
    let ask_next: String
    let unknowns: String
}
