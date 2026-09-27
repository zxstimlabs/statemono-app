import SwiftUI

/// The search field in the header. Clicking it starts a search and opens `SearchPanel` below it, and ⌘F toggles the
/// search. Leaving the field while it's empty closes the search again.
struct SearchField: View {
    @Bindable var search: ChatSearch
    var focus: FocusState<ChatFocus?>.Binding
    var onOpen: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
            TextField("", text: $search.query, prompt: Text("Search").foregroundStyle(Theme.secondaryText))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused(focus, equals: .search)
                .onSubmit { search.showOlder() }
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
        .chromeBackground(Capsule())
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
}

/// Telegram's in-chat search controls, in a panel under the search field: the result counter, older and newer
/// result, jump to a date, and close.
struct SearchPanel: View {
    @Bindable var search: ChatSearch
    var dateRange: ClosedRange<Date>
    var onJumpToDate: (Date) -> Void
    var onClose: () -> Void

    @State private var showsCalendar = false
    @State private var calendarDate = Date.now

    var body: some View {
        HStack(spacing: 6) {
            Text(counter)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .padding(.leading, 10)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                iconButton("chevron.up", size: 16, enabled: search.canShowOlder) { search.showOlder() }
                iconButton("chevron.down", size: 16, enabled: search.canShowNewer) { search.showNewer() }
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

    /// "1 of 12" counts back from the newest match, as Telegram does. Nothing until there's a query.
    private var counter: String {
        guard !search.terms.isEmpty else { return "" }
        guard let index = search.currentIndex else { return String(localized: "No results") }
        return String(localized: "\(search.results.count - index) of \(search.results.count)")
    }

    private func iconButton(_ systemImage: String, size: CGFloat, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        ChromeIconButton(systemImage: systemImage, size: size, action: action)
            .frame(width: 32, height: 27.5)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
    }
}
