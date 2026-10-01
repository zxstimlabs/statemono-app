#if os(macOS)
import StatemonoKit
import SwiftUI

/// TelegramSwift's search results dropdown (`InputContextHelper`, `ContextSearchMessageItem`): the results, newest
/// first, below the search panel while the search field has focus. Smart Search's related links follow under a Related
/// header, which TelegramSwift has no counterpart for. At most half the chat tall. The current result is
/// marked in the accent color, and the keyboard cursor (`highlighted`) in gray; arrow keys move the cursor and Return
/// opens its row (see `SearchField`). A click is handed to `onSelect`.
struct SearchDropdown: View {
    let search: ChatSearch
    var highlighted: Message.ID?
    var maxHeight: CGFloat
    var onSelect: (Message.ID) -> Void

    static let rowHeight: CGFloat = 44
    static let headerHeight: CGFloat = 26
    private static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(search.rows.enumerated()), id: \.element.id) { index, message in
                        row(message, showsSeparator: index < search.rows.count - 1)
                            .onAppear { search.loadRows(near: index) }
                    }
                    if !search.relatedRows.isEmpty {
                        Text("Related")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.searchDropdownDate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .frame(height: Self.headerHeight)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(search.relatedRows.enumerated()), id: \.element.id) { index, message in
                            row(message, showsSeparator: index < search.relatedRows.count - 1)
                        }
                    }
                }
            }
            .frame(height: min(contentHeight, maxHeight))
            // Brings the cursor's row into view, scrolling as little as possible.
            .onChange(of: highlighted) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            // Coming back, the dropdown opens on the current result, as TelegramSwift's does.
            .onAppear {
                if let current = search.current { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .clipShape(Self.shape)
        .chromeBackground(Self.shape)
    }

    private var contentHeight: CGFloat {
        CGFloat(search.listRows.count) * Self.rowHeight + (search.relatedRows.isEmpty ? 0 : Self.headerHeight)
    }

    private func row(_ message: Message, showsSeparator: Bool) -> some View {
        SearchDropdownRow(
            message: message,
            terms: search.terms,
            isCurrent: message.id == search.current,
            isHighlighted: message.id == highlighted,
            showsSeparator: showsSeparator
        )
        .frame(height: Self.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(message.id) }
        .id(message.id)
    }
}

/// One result, 44pt: the link's title in the accent color over one line of the text around the first match, and the
/// date on the right. TelegramSwift puts the sender's avatar and name there; in Saved Messages that's always you.
private struct SearchDropdownRow: View {
    let message: Message
    let terms: [String]
    let isCurrent: Bool
    let isHighlighted: Bool
    let showsSeparator: Bool

    var body: some View {
        let content = SearchRowContent(message: message, terms: terms)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let title = content.title {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isCurrent ? .white : Theme.accent)
                }
                Text(snippet(content))
                    .font(.system(size: 13))
                    .foregroundStyle(isCurrent ? .white : Theme.text)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(SearchResultDate.string(for: message.date))
                .font(.system(size: 12))
                .foregroundStyle(isCurrent ? .white : Theme.searchDropdownDate)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
        .background(isCurrent ? Theme.searchDropdownSelected : isHighlighted ? Theme.menuHighlight : .clear)
        .overlay(alignment: .bottom) {
            if showsSeparator, !isCurrent {
                Theme.searchDropdownSeparator
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
        }
    }

    /// The text is already in the text color, so matches are marked with a background, as in the bubbles.
    private func snippet(_ content: SearchRowContent) -> AttributedString {
        var text = AttributedString(content.snippet)
        for match in content.matches {
            if let range = Range(match, in: text) { text[range].backgroundColor = Theme.searchDropdownHighlight }
        }
        return text
    }
}
#endif
