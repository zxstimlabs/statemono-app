#if os(macOS)
import StatemonoKit
import SwiftUI

/// TelegramSwift's search results dropdown (`InputContextHelper`, `ContextSearchMessageItem`): the results, newest
/// first, below the search panel while the search field has focus. At most half the chat tall. The current result is
/// marked in the accent color, and the keyboard cursor (`highlighted`) in gray; arrow keys move the cursor and Return
/// opens its row (see `SearchField`). A click is handed to `onSelect`.
struct SearchDropdown: View {
    let search: ChatSearch
    var highlighted: Message.ID?
    var maxHeight: CGFloat
    var onSelect: (Message.ID) -> Void

    static let rowHeight: CGFloat = 44
    private static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(search.rows.enumerated()), id: \.element.id) { index, message in
                        SearchDropdownRow(
                            message: message,
                            terms: search.terms,
                            isCurrent: message.id == search.current,
                            isHighlighted: message.id == highlighted,
                            showsSeparator: index < search.rows.count - 1
                        )
                        .frame(height: Self.rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(message.id) }
                        .id(message.id)
                        .onAppear { search.loadRows(near: index) }
                    }
                }
            }
            .frame(height: min(CGFloat(search.rows.count) * Self.rowHeight, maxHeight))
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
                    .foregroundStyle(.white)
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

    /// The text is already white, so matches are marked as in the bubbles, with a background.
    private func snippet(_ content: SearchRowContent) -> AttributedString {
        var text = AttributedString(content.snippet)
        for match in content.matches {
            if let range = Range(match, in: text) { text[range].backgroundColor = Theme.searchHighlight }
        }
        return text
    }
}
#endif
