import SwiftUI

private enum Palette {
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let secondary = Color(red: 0.42, green: 0.43, blue: 0.47)
    static let hairline = Color(red: 0.92, green: 0.92, blue: 0.94)
    static let soft = Color(red: 0.965, green: 0.97, blue: 0.98)
    static let accent = Color(red: 0.10, green: 0.36, blue: 0.87)
}

struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AdvisorPanel: View {
    @ObservedObject var engine: AdvisorEngine
    var onQuit: () -> Void
    var onHeightChange: (CGFloat) -> Void

    static let width: CGFloat = 400
    static let maximumBodyHeight: CGFloat = 560

    @State private var bodyHeight: CGFloat = 0

    private var visible: [Card] { engine.cards.filter { !$0.dismissed } }
    private var directions: [Card] { visible.filter { $0.kind == .direction && $0.state != .candidate } }
    private var answers: [Card] { visible.filter { $0.kind != .direction && $0.state != .candidate } }
    private var candidates: [Card] { Array(visible.filter { $0.state == .candidate }.prefix(6)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if hasBody {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                ScrollView {
                    content
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
                        })
                }
                .frame(height: min(bodyHeight, Self.maximumBodyHeight))
                .onPreferenceChange(PanelHeightKey.self) { bodyHeight = $0 }
            }
        }
        .frame(width: Self.width)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .light)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { onHeightChange($0) }
    }

    private var hasBody: Bool {
        !visible.isEmpty || !engine.keywords.isEmpty || engine.phase == .paused
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSImage(named: "FaceIcon") ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("助言さん")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(engine.problem == nil ? Palette.secondary : Color(red: 0.72, green: 0.27, blue: 0.1))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if engine.isJudging || engine.cards.contains(where: { $0.state == .running }) {
                ProgressView().controlSize(.small)
            }
            Menu {
                if engine.phase == .running {
                    Button("この会議では止める") { engine.disableForThisMeeting() }
                }
                Button("終了", action: onQuit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusText: String {
        if let problem = engine.problem { return problem }
        switch engine.phase {
        case .idle: return "待機中"
        case .running: return "会議を見ています"
        case .paused: return "この会議では止めています"
        case .finished: return "前回の会議の記録"
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if engine.phase == .paused {
                ResumeRow { engine.enableForThisMeeting() }
            }
            if !directions.isEmpty {
                SectionTitle("進め方の提案")
                ForEach(directions) { DirectionRow(card: $0, retry: engine.run, dismiss: engine.dismiss) }
            }
            if !answers.isEmpty {
                SectionTitle("調べた結果")
                ForEach(answers) { AnswerRow(card: $0, retry: engine.run, dismiss: engine.dismiss) }
            }
            if !candidates.isEmpty {
                SectionTitle("候補")
                ForEach(candidates) { CandidateRow(card: $0, run: engine.run, dismiss: engine.dismiss) }
            }
            if !engine.keywords.isEmpty {
                SectionTitle("聞こえた言葉")
                ForEach(engine.keywords) { keyword in
                    Text(keyword.excerpt)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.bottom, 10)
    }
}

private struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }
}

private struct ResumeRow: View {
    let enable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: enable) {
                Text("再開する")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
}

/// Shared frame: a row with a hover close button and a hairline under it.
private struct Row<Content: View>: View {
    let dismiss: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if hovering, let dismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .onHover { hovering = $0 }
    }
}

private struct RunningLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.secondary)
    }
}

private struct FailureLine: View {
    let card: Card
    let retry: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(card.failure ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("もう一度") { retry(card.id) }
                .buttonStyle(QuietButtonStyle())
        }
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(configuration.isPressed ? Palette.soft : Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.hairline))
    }
}

private struct SourcesLine: View {
    let sources: [CardSource]

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sources.prefix(3), id: \.self) { source in
                    if let url = URL(string: source.url) {
                        Link(source.title, destination: url)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.accent)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct DirectionRow: View {
    let card: Card
    let retry: (String) -> Void
    let dismiss: (String) -> Void
    @State private var showsComparison = false

    var body: some View {
        Row(dismiss: { dismiss(card.id) }) {
            VStack(alignment: .leading, spacing: 7) {
                Text(card.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                switch card.state {
                case .running:
                    RunningLine(text: "進め方を考えています")
                case .failed:
                    FailureLine(card: card, retry: retry)
                default:
                    if let recommendation = card.recommendation {
                        Text(recommendation)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let reasoning = card.reasoning {
                        Text(reasoning)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.ink.opacity(0.82))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let ask = card.askNext, !ask.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("次に聞くこと")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.secondary)
                            Text(ask)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    if !card.options.isEmpty {
                        Button(showsComparison ? "比較を閉じる" : "比較した案を見る") {
                            showsComparison.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.accent)
                    }
                    if showsComparison {
                        ForEach(card.options, id: \.self) { option in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                Text("良い点　\(option.good)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.ink.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("弱い点　\(option.bad)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.ink.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let unknowns = card.unknowns {
                        Text("未確認　\(unknowns)")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SourcesLine(sources: card.sources)
                }
            }
        }
    }
}

private struct AnswerRow: View {
    let card: Card
    let retry: (String) -> Void
    let dismiss: (String) -> Void

    var body: some View {
        Row(dismiss: { dismiss(card.id) }) {
            VStack(alignment: .leading, spacing: 5) {
                Text(card.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                switch card.state {
                case .running:
                    RunningLine(text: "調べています")
                case .failed:
                    FailureLine(card: card, retry: retry)
                default:
                    if let conclusion = card.conclusion {
                        Text(conclusion)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let detail = card.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.ink.opacity(0.78))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SourcesLine(sources: card.sources)
                }
            }
        }
    }
}

private struct CandidateRow: View {
    let card: Card
    let run: (String) -> Void
    let dismiss: (String) -> Void

    var body: some View {
        Row(dismiss: { dismiss(card.id) }) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(card.kind.label)　\(card.note)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if card.canRun {
                    Button(card.kind == .direction ? "考える" : "調べる") { run(card.id) }
                        .buttonStyle(QuietButtonStyle())
                        .padding(.trailing, 16)
                }
            }
        }
    }
}
