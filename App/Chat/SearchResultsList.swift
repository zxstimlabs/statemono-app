#if os(iOS)
import StatemonoKit
import SwiftUI
import UIKit

/// Telegram-iOS's search results "Show as List" (`ChatInlineSearchResultsListComponent`): the results, newest first, on
/// an opaque page over the chat. Smart Search's related links follow under a Related header. It sits under the header, the search panel and the composer, scrolls to the top when
/// the results change, and dragging it puts the keyboard away. So does a tap, as on the chat under it. A tap on a row is
/// handed to `onSelect`.
struct SearchResultsList: View {
    let search: ChatSearch
    /// Room at the top for the search panel, which floats over the list.
    var topInset: CGFloat
    /// Whether a field has the keyboard, which a tap on the list puts away (`onHideKeyboard`).
    var isKeyboardFocused: Bool
    var onHideKeyboard: () -> Void
    var onSelect: (Message.ID) -> Void
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(search.rows.enumerated()), id: \.element.id) { index, message in
                    row(message, isLast: index == search.rows.count - 1)
                        .onAppear { search.loadRows(near: index) }
                }
                if !search.relatedRows.isEmpty {
                    SearchSectionHeader(title: "Related")
                    ForEach(Array(search.relatedRows.enumerated()), id: \.element.id) { index, message in
                        row(message, isLast: index == search.relatedRows.count - 1)
                    }
                }
            }
            .padding(.top, topInset)
            .background(FeedTapToDismiss(isEnabled: isKeyboardFocused, action: onHideKeyboard))
        }
        .id(search.resultsVersion)
        .scrollDismissesKeyboard(.immediately)
        .background { Theme.background.ignoresSafeArea() }
    }

    private func row(_ message: Message, isLast: Bool) -> some View {
        Button { onSelect(message.id) } label: {
            SearchResultRow(message: message, terms: search.terms)
        }
        .buttonStyle(SearchResultRowStyle())
        .overlay(alignment: .bottom) {
            // Hairlines inset 16pt on both sides; the last of a section runs edge to edge.
            Rectangle()
                .fill(Theme.searchListSeparator)
                .frame(height: 1 / displayScale)
                .padding(.horizontal, isLast ? 0 : 16)
        }
    }
}

/// A section title in the results list, in the style of Telegram-iOS's list section headers: small capitals in gray on
/// a slightly lighter band.
private struct SearchSectionHeader: View {
    let title: LocalizedStringKey
    @Environment(\.chatTextSize) private var textSize

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: textSize.message * 13 / 17))
            .foregroundStyle(Theme.searchListSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 7)
            .padding(.bottom, 5)
            .background(Theme.searchListHeaderFill)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One result: the link's title and the date on the first line, then up to two lines of the text around the first match,
/// with a link's image as an 18pt thumbnail at its start. Sizes are Telegram-iOS's at 17pt, scaled with the text size.
private struct SearchResultRow: View {
    let message: Message
    let terms: [String]
    @Environment(\.chatTextSize) private var textSize

    var body: some View {
        let content = SearchRowContent(message: message, terms: terms)
        let base = textSize.message
        VStack(alignment: .leading, spacing: 1) {
            if let title = content.title {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.system(size: base * 16 / 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    date(base: base)
                }
                snippet(content, base: base)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    snippet(content, base: base)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    date(base: base)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func date(base: CGFloat) -> some View {
        Text(SearchResultDate.string(for: message.date))
            .font(.system(size: base * 14 / 17))
            .foregroundStyle(Theme.searchListSecondaryText)
            .lineLimit(1)
    }

    /// Gray text with the matched words in the text color, as Telegram marks them.
    private func snippet(_ content: SearchRowContent, base: CGFloat) -> some View {
        let size = base * 15 / 17
        var text = AttributedString(content.snippet)
        text.foregroundColor = Theme.searchListSecondaryText
        for match in content.matches {
            if let range = Range(match, in: text) { text[range].foregroundColor = Theme.text }
        }
        let image = message.preview?.image
        return Group {
            if image != nil {
                // Room at the start of the first line for the thumbnail, which the text wraps under.
                Text("\(Image(uiImage: Self.thumbnailSpace))\(text)")
            } else {
                Text(text)
            }
        }
        .font(.system(size: size))
        .lineLimit(2)
        .overlay(alignment: .topLeading) {
            if let image {
                RemoteImage(image: image, size: CGSize(width: Self.thumbnailSide, height: Self.thumbnailSide))
                    .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .offset(x: 1, y: (UIFont.systemFont(ofSize: size).lineHeight - Self.thumbnailSide) / 2 + 1)
            }
        }
    }

    /// Telegram's inline thumbnail: 18pt with 5pt after it.
    static let thumbnailSide: CGFloat = 18
    static let thumbnailSpace = UIGraphicsImageRenderer(size: CGSize(width: thumbnailSide + 5, height: 1)).image { _ in }
}

/// Telegram-iOS marks a pressed row with a flat background.
private struct SearchResultRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.searchListPressed : .clear)
    }
}
#endif
