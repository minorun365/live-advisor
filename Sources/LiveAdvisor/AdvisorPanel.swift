import SwiftUI

/// Monochrome on white: the only marks that stand out are the unread dot and the lookup button.
private enum Palette {
    static let ink = Color(red: 0.094, green: 0.094, blue: 0.106)        // #18181b
    static let secondary = Color(red: 0.443, green: 0.443, blue: 0.478)  // #71717a
    static let label = Color(red: 0.631, green: 0.631, blue: 0.667)      // #a1a1aa
    static let hairline = Color(red: 0.925, green: 0.925, blue: 0.937)   // #ececef
    static let soft = Color(red: 0.957, green: 0.957, blue: 0.961)       // #f4f4f5
    static let slim = Color(red: 0.98, green: 0.98, blue: 0.98)          // #fafafa
    static let callout = soft
    static let accent = ink
    static let question = ink
    static let answer = Color(red: 0.322, green: 0.322, blue: 0.357)     // #52525b
    static let quiet = answer
    static let unreadDot = ink
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
    /// Only one card stays open, so the list stays short enough to scan during a meeting.
    @State private var openCardID: String?

    private var feed: [Card] { AdvisorPolicy.feed(engine.cards) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if hasBody {
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
                    .onChange(of: openCardID) { _, id in
                        // Closing a longer card above would otherwise push the opened one out of view.
                        guard let id else { return }
                        withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
        }
        .frame(width: Self.width)
        .background {
            // The blur keeps the meeting window faintly visible behind; the white keeps text contrast steady over any wallpaper.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.white.opacity(0.86)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
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
                TaskButton(isBusy: engine.isRequesting) { engine.findTasks() }
                RequestButton(isBusy: engine.isRequesting) { engine.requestNow() }
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
                    // A plain button only takes clicks on the drawn dots, so the whole square has to be the shape.
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var statusText: String {
        if let problem = engine.problem { return problem }
        if engine.transcriberMissing { return "準備が必要です" }
        switch engine.phase {
        case .idle: return "待機中"
        case .running: return "会議を見ています"
        case .paused: return "この会議では止めています"
        case .finished: return "前回の会議の記録"
        }
    }

    private func toggleCard(_ id: String) {
        withAnimation(.snappy(duration: 0.2)) {
            openCardID = openCardID == id ? nil : id
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
                    FeedCard(
                        card: card,
                        expanded: expandsAllCards || openCardID == card.id,
                        toggle: { toggleCard(card.id) },
                        run: engine.run,
                        markRead: engine.markRead,
                        handOff: engine.handOff
                    )
                    .id(card.id)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 10)
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
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
            .background(Palette.accent.opacity(isBusy ? 0.55 : 1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help("直近2分の話を調べます（\(LookupHotKey.label) でも押せます）")
        .fixedSize()
    }
}

/// Quieter than the lookup button: it is pressed far less often, and only when something was asked of the person.
private struct TaskButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button("依頼を確認", action: action)
            .buttonStyle(OutlineButtonStyle(isBusy: isBusy))
            .disabled(isBusy)
            .help("直近5分の発言から、Claude に任せられる依頼を探します")
            .fixedSize()
    }
}

private struct OutlineButtonStyle: ButtonStyle {
    let isBusy: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.ink.opacity(isBusy ? 0.4 : 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Palette.hairline : Palette.soft, in: Capsule())
    }
}

/// Opens a new session in the Claude app with the request typed in. Sending it there is the go-ahead.
private struct HandoffRow: View {
    let handedOff: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if handedOff {
                Text("Claude アプリへ渡しました")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondary)
            }
            Button(handedOff ? "もう一度渡す" : "Claude に渡す", action: action)
                .buttonStyle(QuietButtonStyle())
        }
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
    let expanded: Bool
    let toggle: () -> Void
    let run: (String) -> Void
    let markRead: (String) -> Void
    let handOff: (String) -> Void

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
            if canExpand {
                Button(action: press) {
                    summary.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // A disabled button greys its label, and a card with nothing more to open still has to read clearly.
                summary.onTapGesture { markRead(card.id) }
            }
            if card.kind == .task, card.handoffPrompt != nil {
                HandoffRow(handedOff: card.handedOffAt != nil) { handOff(card.id) }
                    .padding(.top, 8)
            }
            if expanded, canExpand {
                details
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isSlim ? 7 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSlim ? Palette.slim : Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
        .animation(.easeOut(duration: 0.3), value: card.isUnread)
    }

    private func press() {
        let opening = !expanded
        toggle()
        markRead(card.id)
        if opening, card.state == .candidate, card.canRun {
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
            if card.isUnread { unreadDot }
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

    private var unreadDot: some View {
        Circle().fill(Palette.unreadDot).frame(width: 7, height: 7)
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
                HStack(spacing: 6) {
                    if card.isUnread { unreadDot }
                    Text(card.kind.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.label)
                }
                Text(card.title)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Palette.question)
                    .fixedSize(horizontal: false, vertical: true)
                if let answer {
                    Text(answer)
                        .font(.system(size: 13.5))
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
                    .background(Palette.callout, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? Palette.hairline : Palette.soft, in: Capsule())
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
                            .foregroundStyle(Palette.answer)
                            .underline(color: Palette.label)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
