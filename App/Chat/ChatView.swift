import SwiftUI

struct ChatView: View {
    static let coordinateSpace = "chat"

    @Environment(ChatStore.self) private var store
    @State private var draft = ""
    @State private var viewportHeight: CGFloat = 0
    @State private var trafficLightsWidth: CGFloat = 0
    @State private var showsAttachMenu = false
    @State private var search = ChatSearch()
    @State private var flashedMessageID: UUID?
    @State private var scrollRequest: ScrollRequest?
    #if os(macOS)
    @State private var scroller = FeedScroller()
    #endif

    var body: some View {
        feed
        .safeAreaInset(edge: .top, spacing: 0) {
            ChatHeader(leadingInset: headerLeadingInset, onSearch: openSearch)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(text: $draft, onAttach: { setAttachMenu(shown: true) }, onSend: send)
                .padding(.top, 4)
        }
        // Floats over the feed under the header, like Telegram's, instead of insetting it.
        .overlay(alignment: .top) {
            if search.isActive {
                SearchBar(search: search, dateRange: dateRange, onJumpToDate: jump(toDay:), onClose: closeSearch)
                    .padding(.leading, headerLeadingInset)
                    .padding(.trailing, Metrics.sideMargin)
                    .padding(.top, Metrics.headerTop + Metrics.chromeHeight + Metrics.chromeSpacing)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .overlay {
            if showsAttachMenu {
                ZStack(alignment: .bottomLeading) {
                    // Clicks anywhere outside the menu close it, including on the paperclip.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { setAttachMenu(shown: false) }
                    // Opens over the paperclip, offset from its bottom-leading corner as in Telegram.
                    AttachMenu { _ in setAttachMenu(shown: false) }
                        .padding(.leading, Metrics.sideMargin + 12.5)
                        .padding(.bottom, Metrics.composerBottom + 8)
                        .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
        }
        #if os(macOS)
        .onExitCommand {
            if showsAttachMenu {
                setAttachMenu(shown: false)
            } else if search.isActive {
                closeSearch()
            }
        }
        #endif
        .onChange(of: search.query) { search.update(in: store.messages) }
        .onChange(of: store.messages) { if search.isActive { search.update(in: store.messages) } }
        .onChange(of: search.current) { _, id in
            if let id { jump(to: id) }
        }
        .environment(\.searchTerms, search.isActive ? search.terms : [])
        .background(Theme.background)
        .coordinateSpace(.named(Self.coordinateSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .environment(\.chatViewportHeight, viewportHeight)
        #if os(macOS)
        .background {
            TrafficLightsAligner(centerY: Metrics.headerTop + Metrics.chromeHeight / 2, width: $trafficLightsWidth)
        }
        .ignoresSafeArea()
        .frame(minWidth: 380, minHeight: 320)
        #endif
        .preferredColorScheme(.dark)
    }

    private var feed: some View {
        ScrollViewReader { proxy in
            scrollView
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(request.id, anchor: request.anchor) }
                }
        }
    }

    private var scrollView: some View {
        ScrollView {
            // Not lazy: the send slide needs exact heights, and LazyVStack only estimates rows it hasn't shown.
            // Like Telegram, the feed should load a window of messages at a time rather than everything.
            VStack(spacing: 0) {
                ForEach(FeedItem.build(from: store.messages)) { item in
                    switch item {
                    case .day(let date):
                        DaySeparator(date: date)
                    case .message(let message, let position):
                        MessageBubble(message: message, position: position, isFlashed: flashedMessageID == message.id)
                    }
                }
            }
            .padding(.vertical, 4)
            #if os(macOS)
            .background(FeedScrollerAnchor(scroller: scroller))
            #endif
        }
        // No `.scrollPosition` binding: it holds on to its last value and snaps back to it, undoing jumps.
        // Not for `.sizeChanges`: that snaps the feed up the instant a message is added,
        // before `send()` can scroll to it smoothly.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
    }

    /// Header content starts after the traffic lights, which are hidden in full screen.
    private var headerLeadingInset: CGFloat {
        trafficLightsWidth > 0 ? trafficLightsWidth + 12 : Metrics.sideMargin
    }

    /// Days the calendar can jump to: from the first message through today.
    private var dateRange: ClosedRange<Date> {
        let dates = store.messages.map(\.date) + [.now]
        return dates.min()!...dates.max()!
    }

    private func openSearch() {
        withAnimation(.easeOut(duration: 0.2)) { search.isActive = true }
    }

    private func closeSearch() {
        withAnimation(.easeOut(duration: 0.2)) { search.close() }
    }

    /// Centers a search result and flashes its bubble, like Telegram.
    private func jump(to id: UUID) {
        scroll(to: id.uuidString, anchor: .center)
        flashedMessageID = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard flashedMessageID == id else { return }
            withAnimation(.easeOut(duration: 0.4)) { flashedMessageID = nil }
        }
    }

    /// Scrolls to the first message on or after `date`.
    private func jump(toDay date: Date) {
        let calendar = Calendar.current
        guard let message = store.messages.first(where: { $0.date >= calendar.startOfDay(for: date) }) else { return }
        scroll(to: FeedItem.day(calendar.startOfDay(for: message.date)).id, anchor: .top)
    }

    private func scroll(to id: String, anchor: UnitPoint) {
        scrollRequest = ScrollRequest(id: id, anchor: anchor, serial: (scrollRequest?.serial ?? 0) + 1)
    }

    private func setAttachMenu(shown: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            showsAttachMenu = shown
        }
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        #if os(macOS)
        scroller.willInsert()
        #endif
        store.send(draft)
        draft = ""
        #if os(macOS)
        // Next pass, once the new row is laid out and the document view has grown.
        Task { @MainActor in scroller.slideToBottom() }
        #else
        if let last = store.messages.last { scroll(to: last.id.uuidString, anchor: .bottom) }
        #endif
    }
}

/// A jump for the ScrollViewReader to perform. `serial` makes repeated jumps to the same row fire again.
private struct ScrollRequest: Equatable {
    let id: String
    let anchor: UnitPoint
    let serial: Int
}

private struct DaySeparator: View {
    let date: Date

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .chromeBackground(Capsule())
            .padding(.vertical, 8)
    }
}

extension EnvironmentValues {
    /// Height of the chat viewport, which the bubble gradient spans.
    @Entry var chatViewportHeight: CGFloat = 800
    /// Folded search terms to highlight in bubbles; empty when search is closed.
    @Entry var searchTerms: [String] = []
}
