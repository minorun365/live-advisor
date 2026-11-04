import SwiftUI

private enum Palette {
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let secondary = Color(red: 0.42, green: 0.43, blue: 0.47)
    static let hairline = Color(red: 0.92, green: 0.92, blue: 0.94)
    static let soft = Color(red: 0.965, green: 0.97, blue: 0.98)
    static let accent = Color(red: 0.10, green: 0.36, blue: 0.87)
    static let question = Color(red: 0.059, green: 0.247, blue: 0.651)
    static let answer = Color(red: 0.227, green: 0.231, blue: 0.259)
    static let quiet = Color(red: 0.357, green: 0.365, blue: 0.40)
    static let unread = Color(red: 1.0, green: 0.975, blue: 0.82)
    static let unreadEdge = Color(red: 0.96, green: 0.90, blue: 0.62)
}

struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AdvisorPanel: View {
    @ObservedObject var engine: AdvisorEngine
    var onQuit: () -> Void
    var onHeightChange: (CGFloat) -> Void
    var expandsAllCards = false

    static let width: CGFloat = 400
    static let maximumBodyHeight: CGFloat = 560

    @State private var bodyHeight: CGFloat = 0

    private var feed: [Card] { AdvisorPolicy.feed(engine.cards) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if hasBody {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        content
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height)
                            })
                    }
                    .frame(height: min(bodyHeight, Self.maximumBodyHeight))
                    .onPreferenceChange(PanelHeightKey.self) { bodyHeight = $0 }
                    .onChange(of: engine.openCount) { proxy.scrollTo("top", anchor: .top) }
                }
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
        !feed.isEmpty || engine.phase == .paused || engine.transcriberMissing
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
            if engine.phase == .running {
                RequestButton(isBusy: engine.isRequesting) { engine.requestNow() }
            }
            Menu {
                if engine.phase == .running {
                    Button("この会議では止める") { engine.disableForThisMeeting() }
                }
                Toggle("スクリーンショットを撮れるようにする", isOn: $engine.allowsCapture)
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
        if engine.transcriberMissing { return "準備が必要です" }
        if engine.allowsCapture { return "画面共有にも映ります" }
        switch engine.phase {
        case .idle: return "待機中"
        case .running: return "会議を見ています"
        case .paused: return "この会議では止めています"
        case .finished: return "前回の会議の記録"
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0).id("top")
            VStack(spacing: 8) {
                if engine.transcriberMissing {
                    TranscriberRow()
                }
                if engine.phase == .paused {
                    ResumeRow { engine.enableForThisMeeting() }
                }
                ForEach(feed) { card in
                    FeedCard(card: card, startsExpanded: expandsAllCards, run: engine.run, markRead: engine.markRead)
                }
            }
            .padding(10)
            .animation(.snappy(duration: 0.25), value: feed.map(\.id))
        }
    }
}

/// Everything here starts from the transcriber's recording, so its absence comes first.
private struct TranscriberRow: View {
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("文字起こしちゃんが必要です")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("その文字起こしを読んで動きます")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            if let url = URL(string: AppConfig.transcriberPage) {
                Link(destination: url) {
                    Text("導入ページ")
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct RequestButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView().controlSize(.mini).tint(.white)
                }
                Text(isBusy ? "考え中" : "今すぐ提案")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.accent.opacity(isBusy ? 0.6 : 1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .fixedSize()
    }
}

private struct ResumeRow: View {
    let enable: () -> Void

    var body: some View {
        Button(action: enable) {
            Text("再開する")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Palette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One topic. The first line is everything needed mid-meeting; a press opens the rest.
/// Pressing a suggestion also starts it, so reading more and asking for more are one gesture.
private struct FeedCard: View {
    let card: Card
    let run: (String) -> Void
    let markRead: (String) -> Void
    @State private var expanded: Bool

    init(card: Card, startsExpanded: Bool, run: @escaping (String) -> Void, markRead: @escaping (String) -> Void) {
        self.card = card
        self.run = run
        self.markRead = markRead
        _expanded = State(initialValue: startsExpanded)
    }

    private var answer: String? { card.recommendation ?? card.conclusion }

    private var canExpand: Bool {
        switch card.state {
        case .candidate: return card.canRun || !card.note.isEmpty
        case .running: return !card.note.isEmpty
        case .failed: return false
        case .done:
            return [card.reasoning, card.detail, card.askNext, card.unknowns].contains { $0?.isEmpty == false }
                || !card.options.isEmpty || !card.sources.isEmpty || card.points?.isEmpty == false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                summary.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)
            if expanded, canExpand {
                details
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isSlim ? 7 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.isUnread ? Palette.unread : Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(card.isUnread ? Palette.unreadEdge : Palette.hairline)
        )
        .animation(.easeOut(duration: 0.3), value: card.isUnread)
    }

    private func toggle() {
        withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
        markRead(card.id)
        if expanded, card.state == .candidate, card.canRun {
            run(card.id)
        }
    }

    /// Nothing has been worked out yet, so it stays out of the way of the cards that have answers.
    private var isSlim: Bool { card.state == .candidate && !expanded }

    @ViewBuilder
    private var summary: some View {
        if isSlim {
            slimSummary
        } else {
            fullSummary
        }
    }

    private var slimSummary: some View {
        HStack(spacing: 8) {
            Text(card.title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.quiet)
                .lineLimit(1)
            Spacer(minLength: 0)
            if card.canRun {
                Text(card.kind == .direction ? "考える" : "調べる")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            } else if canExpand {
                chevron
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
    }

    private var fullSummary: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.question)
                    .fixedSize(horizontal: false, vertical: true)
                if let answer {
                    Text(answer)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.answer)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if card.state == .running {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(card.kind == .direction ? "考えています" : "調べています")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.secondary)
                    }
                    .padding(.top, 2)
                }
                if card.state == .failed {
                    HStack(spacing: 8) {
                        Text(card.failure ?? "")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("もう一度") { run(card.id) }
                            .buttonStyle(QuietButtonStyle())
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if canExpand {
                chevron.padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            if card.state != .done {
                if !card.note.isEmpty {
                    BodyText(card.note)
                }
            } else {
                if let points = card.points, !points.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(points, id: \.self) { point in
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("・")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Palette.secondary)
                                BodyText(point)
                            }
                        }
                    }
                }
                if let reasoning = card.reasoning, !reasoning.isEmpty {
                    BodyText(reasoning)
                }
                if let detail = card.detail, !detail.isEmpty {
                    BodyText(detail)
                }
                if let ask = card.askNext, !ask.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("次に聞く")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondary)
                        Text(ask)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                ForEach(card.options, id: \.self) { option in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        OptionLine(label: "良い", text: option.good)
                        OptionLine(label: "弱い", text: option.bad)
                    }
                }
                if let unknowns = card.unknowns, !unknowns.isEmpty {
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

private struct BodyText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.quiet)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OptionLine: View {
    let label: String
    let text: String

    var body: some View {
        Text("\(label)　\(text)")
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
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
