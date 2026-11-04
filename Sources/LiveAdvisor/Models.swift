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
    /// Set when the person has seen this version of the card. A later result makes it unread again.
    var readAt: Date?
    /// Asked for with the button, not picked by the judge. Optional so older saved cards still load.
    var requested: Bool?

    var conclusion: String?
    /// Older saved cards keep their prose here. New results use `points`.
    var detail: String?
    /// Short lines shown when the card opens. Optional so older saved cards still load.
    var points: [String]?
    var sources: [CardSource] = []

    var recommendation: String?
    var reasoning: String?
    var options: [DirectionOption] = []
    var askNext: String?
    var unknowns: String?

    var failure: String?

    var canRun: Bool { kind == .direction || research }
    var isRequested: Bool { requested == true }
    var updatedAt: Date { finishedAt ?? createdAt }
    var isUnread: Bool { readAt.map { $0 < updatedAt } ?? true }
}

/// What Haiku returns for one pass over the new transcript.
struct JudgeOutput: Decodable {
    struct Item: Decodable {
        let kind: CardKind
        var title: String
        let note: String
        let research: Bool
        let confidence: Double
        let declared_by_self: Bool
        let asked_by_others: Bool
        let search_questions: [String]
    }

    let memo: String
    var cards: [Item]
}

/// One line to shorten, with the limit it has to fit.
struct TightenRequest: Equatable {
    let text: String
    let limit: Int
    var asks = false
}

struct TightenOutput: Decodable {
    let items: [String]
}

struct ResearchOutput: Decodable {
    let conclusion: String
    let points: [String]
    let sources: [CardSource]
}

struct DirectionOutput: Decodable {
    /// Only the button's proposal names its own topic. A judged card already has one.
    var title: String?
    let recommendation: String
    let points: [String]
    let options: [DirectionOption]
    let ask_next: String
    let unknowns: String
}
