import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @State private var draft = ""
    @State private var trafficLightsWidth: CGFloat = 0
    @State private var showsAttachMenu = false
    @State private var search = ChatSearch()
    @FocusState private var focus: ChatFocus?
    @State private var flashedMessageID: UUID?
    @State private var scrollRequest: ScrollRequest?
    /// The oldest message's date, read when search opens, so the calendar can reach back through all history.
    @State private var oldestDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var feedFollower = FeedFollower()
    /// Whether the software keyboard is up, which brings up the button that puts it away.
    @State private var isKeyboardShown = false
    /// How wide the feed's rows are. Bubbles are laid out from it directly (`BubbleRow`); this copy sizes preview images.
    @State private var feedWidth: CGFloat = 0
    /// The search results list, while it's shown or on its way in or out, and its animated state (`setList(shown:)`).
    @State private var listShown = false
    @State private var listOpacity = 0.0
    @State private var listScale = 0.95
    @State private var listBlur = 30.0
    /// The chat shrinks a little behind the list, as in Telegram-iOS.
    @State private var chatScale = 1.0
    #endif
    #if os(macOS)
    /// The chat's height, which limits the search dropdown's.
    @State private var chatHeight: CGFloat = 0
    #endif
    #if os(macOS)
    @State private var scroller = FeedScroller()
    /// The open context menu. On iOS, bubbles use the system's context menu instead.
    @State private var messageMenu: MessageMenuState?
    #endif
    /// A message waiting for the user to confirm deleting it.
    @State private var pendingDelete: Message.ID?
    @State private var showsSettings = false

    var body: some View {
        feed
        #if os(iOS)
        .scaleEffect(chatScale)
        #endif
        // Messages fade out as they scroll behind the header or the composer.
        .overlay { FeedEdgeFade(edge: .top) }
        .overlay { FeedEdgeFade(edge: .bottom) }
        #if os(iOS)
        // Over the chat, under the header, the search panel and the composer.
        .overlay { searchList }
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            ChatHeader(
                leadingInset: headerLeadingInset,
                search: search,
                focus: $focus,
                onOpenSearch: openSearch,
                onCloseSearch: closeSearch,
                onOpenResult: openResult,
                onOpenSettings: { showsSettings = true }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(text: $draft, focus: $focus, onAttach: { setAttachMenu(shown: true) }, onSend: send)
                .padding(.top, 4)
                // Stacked on the composer's top edge, so they ride with it and the keyboard without insetting the feed.
                // An overlay on the feed placed them from its safe area, which iOS 18 works out differently.
                .overlay(alignment: .topTrailing) {
                    feedButtons.alignmentGuide(.top) { $0[.bottom] }
                }
        }
        // Drops out of the header's search field and floats over the feed, instead of insetting it.
        .overlay(alignment: .top) {
            if search.isActive {
                searchControls
                    .padding(.leading, headerLeadingInset + Metrics.chromeHeight + Metrics.chromeSpacing)
                    .padding(.trailing, Metrics.sideMargin + Metrics.chromeHeight + Metrics.chromeSpacing)
                    // Keeps its gap under the search field's glass, which grows while the field has focus.
                    .padding(.top, Metrics.headerTop + Metrics.chromeHeight + Metrics.chromeSpacing
                        + (focus == .search ? Metrics.focusGrowth : 0))
                    .animation(Metrics.focusAnimation, value: focus == .search)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
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
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
        }
        #if os(macOS)
        .overlay {
            if let menu = messageMenu {
                MessageMenuOverlay(menu: menu) { item in
                    closeMessageMenu()
                    perform(item, on: menu.messageID)
                } onClose: {
                    closeMessageMenu()
                }
                .transition(.opacity)
            }
        }
        .onExitCommand {
            if showsAttachMenu {
                setAttachMenu(shown: false)
            } else if search.isActive {
                closeSearch()
            }
        }
        #endif
        .onChange(of: search.query) { search.update(using: store.database) }
        .onChange(of: search.current) { _, id in
            if let id { jump(to: id) }
        }
        // Telegram's confirmation for deleting a message in Saved Messages.
        .alert("This action can't be undone", isPresented: isConfirmingDelete, presenting: pendingDelete) { id in
            Button("Delete", role: .destructive) { store.delete(id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Delete selected message?")
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        #if os(macOS)
        // ⌘, and the app menu's Settings… item open the same sheet (`SettingsCommands`).
        .focusedSceneValue(\.openSettings) { showsSettings = true }
        #endif
        .environment(\.searchTerms, search.isActive ? search.terms : [])
        #if os(iOS)
        .environment(\.chatTextSize, ChatTextSize(dynamicTypeSize))
        .environment(\.feedWidth, feedWidth)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardShown = false
        }
        #endif
        // Also under the keyboard, which shows the app behind its rounded top corners.
        .background { Theme.background.ignoresSafeArea() }
        #if os(macOS)
        .background {
            TrafficLightsAligner(centerY: Metrics.headerTop + Metrics.chromeHeight / 2, width: $trafficLightsWidth)
        }
        .background {
            WindowEventMonitor(events: [.rightMouseDown, .leftMouseDown, .keyDown, .scrollWheel], handler: handleWindowEvent) {
                closeMessageMenu()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chatHeight = $0 }
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
                // Reaching the top loads the next page of history, keeping what's on screen in place.
                if store.hasOlder {
                    Color.clear
                        .frame(height: 1)
                        .onScrollVisibilityChange { visible in
                            guard visible else { return }
                            #if os(macOS)
                            scroller.willPrepend()
                            #else
                            feedFollower.willPrepend()
                            #endif
                            store.loadOlder()
                        }
                }
                ForEach(FeedItem.build(from: store.messages)) { item in
                    Group {
                        switch item {
                        case .day(let date):
                            DaySeparator(date: date)
                        case .message(let message, let position):
                            MessageBubble(
                                message: message,
                                position: position,
                                isFlashed: flashedMessageID == message.id,
                                isLoadingPreview: store.loadingPreviews.contains(message.id),
                                onReloadPreview: { store.reloadPreview(for: message.id) }
                            )
                            #if !os(macOS)
                            .contextMenu {
                                ForEach(MessageMenuItem.groups.indices, id: \.self) { index in
                                    Section {
                                        ForEach(MessageMenuItem.groups[index]) { item in
                                            Button(role: item.isDestructive ? .destructive : nil) {
                                                perform(item, on: message.id)
                                            } label: {
                                                Label(item.title, systemImage: item.systemImage)
                                            }
                                        }
                                    }
                                }
                            }
                            #endif
                        }
                    }
                    #if os(macOS)
                    // Where each row sits, so FeedScroller can glide to it.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FeedScroller.contentSpace)) } action: {
                        scroller.rowFrames[item.id] = $0
                    }
                    #endif
                }
            }
            .padding(.vertical, 4)
            // Clicking the feed doesn't take focus from the search field, so an empty search is closed here instead.
            // A gesture on the ScrollView itself never sees the click.
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded(closeSearch), isEnabled: search.isActive && search.query.isEmpty)
            #if os(macOS)
            .coordinateSpace(.named(FeedScroller.contentSpace))
            .background(FeedScrollerAnchor(scroller: scroller))
            #else
            .background(FeedFollowerAnchor(follower: feedFollower))
            // As in Telegram-iOS, a tap anywhere in the feed puts the keyboard away.
            .background(FeedTapToDismiss(isEnabled: focus != nil) { focus = nil })
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { feedWidth = $0 }
            #endif
        }
        // No `.scrollPosition` binding: it holds on to its last value and snaps back to it, undoing jumps.
        // Not for `.sizeChanges`: that snaps the feed up the instant a message is added,
        // before `send()` can scroll to it smoothly.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        #if os(iOS)
        .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, geometry in
            feedFollower.update(contentHeight: geometry.contentSize.height)
        }
        #endif
    }

    private var feedButtons: some View {
        #if os(macOS)
        FeedButtons(showsScrollToBottom: scroller.isAwayFromBottom, onScrollToBottom: scroller.scrollToBottom)
        #else
        FeedButtons(
            // Telegram-iOS hides its result arrows and down button while the list shows.
            showsScrollToBottom: feedFollower.isAwayFromBottom && !search.isShowingList,
            showsHideKeyboard: isKeyboardShown,
            searchArrows: searchArrows,
            onScrollToBottom: feedFollower.scrollToBottom,
            onHideKeyboard: { focus = nil }
        )
        #endif
    }

    #if os(iOS)
    /// Telegram-iOS's result arrows, while stepping through results in the chat.
    private var searchArrows: FeedButtons.SearchArrows? {
        guard search.isActive, !search.isShowingList, !search.results.isEmpty else { return nil }
        return FeedButtons.SearchArrows(canShowOlder: search.canShowOlder, onOlder: search.showOlder) {
            if search.canShowNewer { search.showNewer() } else { feedFollower.scrollToBottom() }
        }
    }
    #endif

    /// Header content starts after the traffic lights, which are hidden in full screen.
    private var headerLeadingInset: CGFloat {
        trafficLightsWidth > 0 ? trafficLightsWidth + 12 : Metrics.sideMargin
    }

    /// Days the calendar can jump to: from the first message through today.
    private var dateRange: ClosedRange<Date> {
        min(oldestDate ?? .now, .now)...Date.now
    }

    /// Critically damped springs (no bounce) for UI that appears on a click: interruptible, unlike fixed curves.
    private static let panelSpring = Animation.smooth(duration: 0.25)
    private static let menuSpring = Animation.smooth(duration: 0.2)
    /// A context menu fades in and out over 0.2s, as in Telegram.
    private static let menuFade = Animation.easeOut(duration: 0.2)

    private func openSearch() {
        oldestDate = try? store.database.oldestItemDate()
        withAnimation(Self.panelSpring) { search.isActive = true }
    }

    private func closeSearch() {
        #if os(iOS)
        if listShown { setList(shown: false) }
        #endif
        withAnimation(Self.panelSpring) { search.close() }
        #if os(macOS)
        // The keyboard goes back to the composer. In Telegram the message field is the chat's default responder.
        focus = .composer
        #else
        focus = nil
        #endif
    }

    /// The search panel, and on the Mac the results dropdown under it.
    private var searchControls: some View {
        VStack(spacing: Self.dropdownGap) {
            SearchPanel(
                search: search,
                dateRange: dateRange,
                onJumpToDate: jump(toDay:),
                onToggleList: toggleList,
                onStep: steppedThroughResults,
                onClose: closeSearch
            )
            #if os(macOS)
            if showsDropdown {
                SearchDropdown(search: search, highlighted: search.cursor, maxHeight: dropdownMaxHeight, onSelect: openResult)
                    // Slides out from under the panel, as TelegramSwift's slides out from under its header.
                    .zIndex(-1)
                    .transition(Self.dropdownTransition(reduceMotion: reduceMotion))
            }
            #endif
        }
    }

    #if os(iOS)
    @ViewBuilder private var searchList: some View {
        if listShown {
            SearchResultsList(
                search: search,
                topInset: Metrics.chromeSpacing + SearchPanel.height + 8 + (focus == .search ? Metrics.focusGrowth : 0),
                isKeyboardFocused: focus != nil,
                onHideKeyboard: { focus = nil },
                onSelect: openResult
            )
            // Rows fade out behind the header and the composer, like messages do.
            .overlay { FeedEdgeFade(edge: .top) }
            .overlay { FeedEdgeFade(edge: .bottom) }
            .opacity(listOpacity)
            .scaleEffect(listScale)
            .blur(radius: listBlur)
        }
    }
    #endif

    /// A result picked in the list or dropdown: the chat jumps to it, and it becomes the current result.
    private func openResult(_ id: UUID) {
        if search.current == id {
            jump(to: id)
        } else {
            search.select(id)
        }
        #if os(macOS)
        // TelegramSwift leaves nothing focused, so the dropdown closes.
        focus = nil
        #else
        setList(shown: false)
        #endif
    }

    private func toggleList() {
        #if os(iOS)
        setList(shown: !search.isShowingList)
        #endif
    }

    /// TelegramSwift's arrows take focus from the search field, which puts the dropdown away before the chat jumps.
    private func steppedThroughResults() {
        #if os(macOS)
        if focus == .search { focus = nil }
        #endif
    }

    #if os(iOS)
    /// Telegram-iOS's list transition. In: fades in over 0.2s, grows from 0.95 and sharpens from a 30pt blur, while the
    /// chat behind shrinks to 0.95. Out: the reverse, a little slower. Its 0.4s "spring" is really this curve.
    private func setList(shown: Bool) {
        search.isShowingList = shown
        let slide = Animation.timingCurve(0.38, 0.7, 0.125, 1, duration: 0.4)
        if shown {
            listShown = true
            guard !reduceMotion else {
                (listScale, listBlur) = (1, 0)
                withAnimation(.easeInOut(duration: 0.2)) { listOpacity = 1 }
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) { listOpacity = 1 }
            withAnimation(slide) { (listScale, chatScale) = (1, 0.95) }
            withAnimation(.easeOut(duration: 0.2)) { listBlur = 0 }
        } else {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : slide) {
                (listOpacity, chatScale) = (0, 1)
            } completion: {
                if !search.isShowingList { listShown = false }
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3)) { listScale = 0.95 }
            withAnimation(.easeOut(duration: 0.3)) { listBlur = 30 }
        }
    }
    #endif

    #if os(macOS)
    /// TelegramSwift's dropdown shows while the search field has focus and there's a result.
    private var showsDropdown: Bool {
        focus == .search && !search.rows.isEmpty
    }

    /// At most half the chat, and never closer than 50pt to its bottom (`InputContextHelper`).
    private var dropdownMaxHeight: CGFloat {
        let top = Metrics.headerTop + Metrics.chromeHeight + Metrics.chromeSpacing + Metrics.focusGrowth + SearchPanel.height + Self.dropdownGap
        return max(0, min((chatHeight / 2).rounded(.down), chatHeight - 50 - top))
    }

    /// TelegramSwift's: fades over 0.2s while sliding 0.4s on an over-damped spring, which reads as an ease-out.
    private static func dropdownTransition(reduceMotion: Bool) -> AnyTransition {
        let fade = AnyTransition.opacity.animation(.easeOut(duration: 0.2))
        guard !reduceMotion else { return fade }
        return fade.combined(with: .offset(y: -(SearchPanel.height + dropdownGap)).animation(.smooth(duration: 0.4)))
    }
    #endif

    private static let dropdownGap: CGFloat = 6

    /// Centers a search result and flashes its bubble, like Telegram. Older results load their page of history first.
    private func jump(to id: UUID) {
        loadHistory(through: id)
        scroll(to: id.uuidString, anchor: .center)
        flashedMessageID = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard flashedMessageID == id else { return }
            withAnimation(.easeOut(duration: 0.4)) { flashedMessageID = nil }
        }
    }

    /// Scrolls to the first message on or after `date`, loading history back to it if needed.
    private func jump(toDay date: Date) {
        let calendar = Calendar.current
        guard let id = try? store.database.firstItem(onOrAfter: calendar.startOfDay(for: date)) else { return }
        loadHistory(through: id)
        guard let message = store.messages.first(where: { $0.id == id }) else { return }
        scroll(to: FeedItem.day(calendar.startOfDay(for: message.date)).id, anchor: .top)
    }

    private func loadHistory(through id: UUID) {
        guard !store.messages.contains(where: { $0.id == id }) else { return }
        #if os(macOS)
        scroller.willPrepend()
        #else
        feedFollower.willPrepend()
        #endif
        store.ensureLoaded(id)
    }

    private func scroll(to id: String, anchor: UnitPoint) {
        #if os(macOS)
        if scroller.scroll(toRow: id, anchor: anchor) { return }
        #endif
        scrollRequest = ScrollRequest(id: id, anchor: anchor, serial: (scrollRequest?.serial ?? 0) + 1)
    }

    private func setAttachMenu(shown: Bool) {
        withAnimation(Self.menuSpring) {
            showsAttachMenu = shown
        }
    }

    /// Runs a context menu item on a message. Only Copy Text and Delete are built so far.
    private func perform(_ item: MessageMenuItem, on id: Message.ID) {
        guard let message = store.messages.first(where: { $0.id == id }) else { return }
        switch item {
        case .copyText: Pasteboard.copy(message.text)
        case .delete: pendingDelete = id
        case .reply, .translate, .edit, .pin, .forward, .select: break
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } }
    }

    #if os(macOS)
    /// Opens a message's context menu on a right-click, two-finger tap or Control-click anywhere on its row, beside the
    /// bubble included, as TelegramSwift's `TableRowView` does. While the menu is open, events go to it instead.
    private func handleWindowEvent(_ event: NSEvent, in view: NSView) -> Bool {
        if let menu = messageMenu {
            switch menu.handle(event) {
            case .select(let item):
                closeMessageMenu()
                perform(item, on: menu.messageID)
            case .close:
                closeMessageMenu()
            case nil:
                break
            }
            // Left clicks go on to the menu's rows and the backdrop around it.
            return event.type != .leftMouseDown
        }
        let isContextClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isContextClick, !showsAttachMenu, let point = scroller.contentPoint(of: event),
              let message = store.messages.first(where: { scroller.rowFrames[$0.id.uuidString]?.contains(point) == true })
        else { return false }
        let location = view.convert(event.locationInWindow, from: nil)
        withAnimation(Self.menuFade) {
            messageMenu = MessageMenuState(messageID: message.id, point: location)
        }
        return true
    }

    private func closeMessageMenu() {
        guard messageMenu != nil else { return }
        withAnimation(Self.menuFade) { messageMenu = nil }
    }
    #endif

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        #if os(macOS)
        scroller.willInsert()
        #else
        feedFollower.willInsert()
        #endif
        store.send(draft)
        draft = ""
    }
}

/// The text fields in the chat that can hold the keyboard.
enum ChatFocus: Hashable {
    case composer
    case search
}

/// A jump for the ScrollViewReader to perform. `serial` makes repeated jumps to the same row fire again.
private struct ScrollRequest: Equatable {
    let id: String
    let anchor: UnitPoint
    let serial: Int
}

private struct DaySeparator: View {
    let date: Date
    @Environment(\.chatTextSize) private var textSize

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
            .font(.system(size: textSize.day, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .chromeBackground(Capsule())
            .padding(.vertical, 8)
    }
}

extension EnvironmentValues {
    /// Folded search terms to highlight in bubbles; empty when search is closed.
    @Entry var searchTerms: [String] = []
}
