import SwiftUI

/// The search field in the header. Clicking it starts a search and opens `SearchPanel` below it, and ⌘F toggles the
/// search. Leaving the field while it's empty closes the search again.
///
/// On the Mac, while the results dropdown shows, the arrow keys move its cursor, Return opens the cursor's row, and
/// Escape clears the cursor before it closes the search.
struct SearchField: View {
    @Bindable var search: ChatSearch
    var focus: FocusState<ChatFocus?>.Binding
    var onOpen: () -> Void
    var onClose: () -> Void
    var onOpenResult: (Message.ID) -> Void = { _ in }
    @Environment(\.chatTextSize) private var textSize

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
            TextField("", text: $search.query, prompt: Text("Search").foregroundStyle(Theme.secondaryText))
                .textFieldStyle(.plain)
                .font(.system(size: textSize.message))
                .foregroundStyle(Theme.text)
                .focused(focus, equals: .search)
                .onSubmit {
                    #if os(macOS)
                    if let cursor = search.cursor, !search.listRows.isEmpty {
                        onOpenResult(cursor)
                        return
                    }
                    #endif
                    search.showOlder()
                }
                #if os(macOS)
                .onKeyPress(.downArrow) { moveCursor(by: 1) }
                .onKeyPress(.upArrow) { moveCursor(by: -1) }
                .onKeyPress(.escape) {
                    guard search.cursor != nil, !search.listRows.isEmpty else { return .ignored }
                    search.cursor = nil
                    return .handled
                }
                #endif
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                    focus.wrappedValue = .search
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.pressFeedback)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 11)
        .frame(height: Metrics.chromeHeight)
        // Grows a little while it has focus, like the composer. Only the glass, so the header keeps its height.
        .chromeBackground(Capsule(), outset: focus.wrappedValue == .search ? Metrics.focusGrowth : 0)
        .animation(Metrics.focusAnimation, value: focus.wrappedValue == .search)
        .contentShape(Capsule())
        .onTapGesture { focus.wrappedValue = .search }
        .onChange(of: focus.wrappedValue) { old, new in
            if new == .search {
                if !search.isActive { onOpen() }
            } else if old == .search, search.isActive, search.query.isEmpty {
                onClose()
            }
        }
        .background {
            // ⌘F with no visible button: opens the search, or closes it while it's open.
            Button {
                if search.isActive { onClose() } else { focus.wrappedValue = .search }
            } label: {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
    }

    #if os(macOS)
    private func moveCursor(by step: Int) -> KeyPress.Result {
        guard !search.listRows.isEmpty else { return .ignored }
        search.moveCursor(by: step)
        return .handled
    }
    #endif
}

/// Telegram's in-chat search controls, in a panel under the search field: the result counter, older and newer
/// result, jump to a date, and close. On iPhone it also switches the results between the chat and a list, as
/// Telegram-iOS's search panel does (`ChatTagSearchInputPanelNode`), and in list mode the counter reads "M messages".
/// There, as in Telegram-iOS, the older and newer arrows float over the chat instead (`FeedButtons`).
///
/// While Smart Search is off and nothing is found, a Smart Search chip offers it (`onSmartSearch`).
struct SearchPanel: View {
    @Bindable var search: ChatSearch
    var dateRange: ClosedRange<Date>
    var onJumpToDate: (Date) -> Void
    /// Switches between the chat and the results list.
    var onToggleList: () -> Void = {}
    /// Called after the arrows move to another result.
    var onStep: () -> Void = {}
    /// Opens Settings at Smart Search. Nil hides the chip.
    var onSmartSearch: (() -> Void)?
    var onClose: () -> Void

    /// 27.5pt buttons with 4.5pt above and below.
    static let height: CGFloat = 36.5

    @State private var showsCalendar = false
    @State private var calendarDate = Date.now
    @Environment(\.chatTextSize) private var textSize

    var body: some View {
        HStack(spacing: 6) {
            // In list mode, tapping the counter goes back to the chat, as in Telegram-iOS.
            Button(action: onToggleList) {
                Text(counter)
                    .font(.system(size: textSize.preview))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .buttonStyle(.pressFeedback)
            .disabled(!search.isShowingList || search.steps.isEmpty)
            .padding(.leading, 10)
            Spacer(minLength: 0)
            if let onSmartSearch {
                SmartSearchChip(action: onSmartSearch)
            }
            #if os(iOS)
            if !search.steps.isEmpty {
                Button(search.isShowingList ? "Show as Chat" : "Show as List", action: onToggleList)
                    .font(.system(size: textSize.preview))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .fixedSize()
                    .buttonStyle(.pressFeedback)
                    .padding(.horizontal, 4)
            }
            #endif
            HStack(spacing: 0) {
                // On iPhone the arrows float over the chat instead, as in Telegram-iOS (`FeedButtons`).
                #if os(macOS)
                if !search.isShowingList {
                    iconButton("chevron.up", size: 16, enabled: search.canShowOlder) {
                        search.showOlder()
                        onStep()
                    }
                    iconButton("chevron.down", size: 16, enabled: search.canShowNewer) {
                        search.showNewer()
                        onStep()
                    }
                }
                #endif
                iconButton("calendar", size: 16) {
                    calendarDate = min(max(.now, dateRange.lowerBound), dateRange.upperBound)
                    showsCalendar = true
                }
                .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                    DatePicker("", selection: $calendarDate, in: dateRange, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                        .onChange(of: calendarDate) { _, date in
                            showsCalendar = false
                            onJumpToDate(date)
                        }
                }
                iconButton("xmark", size: 14, action: onClose)
            }
        }
        .padding(EdgeInsets(top: 4.5, leading: 3.5, bottom: 4.5, trailing: 4))
        .chromeBackground(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// "1 of 12" counts back from the newest match, as Telegram does, and a list shows "12 messages". Related links,
    /// stepped through when nothing matched, say so: "1 of 3 related". Nothing until there's a query.
    private var counter: String {
        guard !search.terms.isEmpty else { return "" }
        guard let index = search.currentIndex else { return String(localized: "No results") }
        let count = search.steps.count
        if search.isSteppingRelated {
            return search.isShowingList ? String(localized: "\(count) related") : String(localized: "\(index + 1) of \(count) related")
        }
        if search.isShowingList {
            return count == 1 ? String(localized: "1 message") : String(localized: "\(count) messages")
        }
        return String(localized: "\(index + 1) of \(count)")
    }

    private func iconButton(_ systemImage: String, size: CGFloat, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        ChromeIconButton(systemImage: systemImage, size: size, action: action)
            .frame(width: 32, height: 27.5)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
    }
}

/// Offers Smart Search in the search panel while it's off: a small accent capsule that opens Settings.
private struct SmartSearchChip: View {
    let action: () -> Void
    @Environment(\.chatTextSize) private var textSize

    var body: some View {
        Button(action: action) {
            Label("Smart Search", systemImage: "sparkles")
                .font(.system(size: textSize.preview - 1, weight: .medium))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.accent.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.pressFeedback)
        .accessibilityHint("Opens Settings to turn on Smart Search, which finds links by meaning.")
    }
}
