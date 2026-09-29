import StatemonoKit
import SwiftUI

struct MessageBubble: View {
    let message: Message
    let position: BubblePosition
    /// Briefly lit up when search lands on this message.
    var isFlashed = false
    var isLoadingPreview = false
    var onReloadPreview: () -> Void = {}
    @Environment(\.searchTerms) private var searchTerms
    @Environment(\.chatTextSize) private var textSize

    private var shape: BubbleShape {
        BubbleShape(
            topTrailingRadius: position.isFirstInGroup ? Metrics.bubbleRadius : Metrics.groupedRadius,
            bottomTrailingRadius: Metrics.groupedRadius,
            hasTail: position.isLastInGroup
        )
    }

    /// Between the bubble's edges and its content. The trailing side includes the tail.
    static let insets = EdgeInsets(top: 7, leading: 10, bottom: 6, trailing: 10 + Metrics.tailWidth)

    private var contentMaxWidth: CGFloat {
        #if os(macOS)
        message.preview == nil ? Metrics.textMaxWidth : Metrics.previewWidth
        #else
        .infinity
        #endif
    }

    var body: some View {
        BubbleRow {
            CappedWidth(max: contentMaxWidth) {
                content
            }
            .overlay(alignment: .topTrailing) {
                if message.link != nil {
                    ReloadButton(isLoading: isLoadingPreview, action: onReloadPreview)
                }
            }
            .padding(Self.insets)
            .background { BubbleFill(shape: shape) }
            .overlay {
                if isFlashed {
                    shape.fill(.white.opacity(0.18)).transition(.opacity)
                }
            }
        }
        .padding(.top, position.isFirstInGroup ? 4 : 2)
    }

    @ViewBuilder private var content: some View {
        if let preview = message.preview {
            VStack(alignment: .leading, spacing: 0) {
                messageText(highlighted(Linkifier.attributed(message.text), source: message.text))
                    .padding(.trailing, ReloadButton.reservedWidth)
                LinkPreviewView(preview: preview, url: message.link, revision: message.previewRevision)
                    .padding(.top, 5)
                TimeLabel(date: message.date)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 3)
            }
        } else {
            // Telegram tucks the time into the last line when it fits. Reserve that space with invisible text;
            // if the last line is too full, the reserve wraps and the time drops onto its own line.
            messageText(highlighted(Linkifier.attributed(message.text), source: message.text) + TimeLabel.reserve(for: message.date, size: textSize.time))
                .padding(.trailing, message.link == nil ? 0 : ReloadButton.reservedWidth)
                .overlay(alignment: .bottomTrailing) {
                    TimeLabel(date: message.date)
                }
        }
    }

    private func highlighted(_ text: AttributedString, source: String) -> AttributedString {
        Highlighter.apply(searchTerms, to: text, source: source)
    }

    private func messageText(_ text: AttributedString) -> some View {
        Text(text)
            .font(.system(size: textSize.message))
            .foregroundStyle(.white)
            .tint(.white)
    }
}

/// Fills the bubble with Telegram's window-pinned gradient, approximated per bubble: the lower a bubble sits in
/// the window, the darker it is. The shade is set in `visualEffect`, which runs at render time. A GeometryReader
/// here re-ran every bubble's body on every scroll frame and dropped a 200-message feed to ~20fps.
private struct BubbleFill: View {
    let shape: BubbleShape

    var body: some View {
        shape.fill(Theme.bubbleTop)
            .visualEffect { content, proxy in
                let height = max(proxy.bounds(of: .scrollView)?.height ?? 1, 1)
                let position = min(max(proxy.frame(in: .scrollView).midY / height, 0), 1)
                return content.brightness(Theme.bubbleBottomBrightness * position)
            }
    }
}

/// Fetches a link's preview again. It sits in the bubble's top-right corner, sized and colored like the time and
/// ticks at the bottom right, and spins while a fetch is running, including the first one after sending.
private struct ReloadButton: View {
    static let size = CGSize(width: 14, height: 16)
    /// Room the link text leaves on its right so the button never covers it.
    static let reservedWidth = size.width + 4

    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isLoading)
                .frame(width: Self.size.width, height: Self.size.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressFeedback)
        .disabled(isLoading)
        .help("Reload preview")
        .accessibilityLabel("Reload preview")
    }
}

struct TimeLabel: View {
    let date: Date
    @Environment(\.chatTextSize) private var textSize

    static let format = Date.FormatStyle.dateTime.hour().minute()

    /// Invisible text as wide as a `TimeLabel` plus a small gap. The leading plain space is where it may wrap.
    /// It ends in "00" rather than spaces because trailing spaces don't count toward a line's width;
    /// NBSP + "00" at 11pt is 17.1pt, just over the 4pt gap + 12.5pt checks. Both scale with `size`.
    static func reserve(for date: Date, size: CGFloat) -> AttributedString {
        var reserve = AttributedString(" \u{00A0}" + date.formatted(format) + "\u{00A0}00")
        reserve.swiftUI.font = .system(size: size)
        reserve.swiftUI.foregroundColor = .clear
        return reserve
    }

    var body: some View {
        // The checks were measured beside 11pt text; Telegram-iOS sizes them with the time.
        let scale = textSize.time / 11
        HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
            Text(date, format: Self.format)
            ReadChecks()
                .stroke(style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                .frame(width: 12.5 * scale, height: 7.5 * scale)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        }
        .font(.system(size: textSize.time))
        .foregroundStyle(.white)
    }
}

private struct LinkPreviewView: View {
    let preview: LinkPreview
    let url: URL?
    /// Changes when the preview is reloaded, so the image view starts over and loads the image again.
    let revision: Date?

    /// Telegram's small thumbnail.
    static let thumbnailSide: CGFloat = 54
    @Environment(\.openURL) private var openURL
    @Environment(\.searchTerms) private var searchTerms
    @Environment(\.chatTextSize) private var textSize
    @Environment(\.feedWidth) private var feedWidth

    /// A large image spans the preview's width, minus its insets (7 leading, 6 trailing).
    private var largeImageWidth: CGFloat {
        #if os(macOS)
        Metrics.previewWidth - 13
        #else
        // A preview fills its bubble, which on iOS is as wide as the row allows. Zero until the feed is measured.
        let bubble = feedWidth - Metrics.bubbleLeadingSpace(rowWidth: feedWidth) - Metrics.bubbleTrailing
        return max(0, bubble - MessageBubble.insets.leading - MessageBubble.insets.trailing - 13)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    if let siteName = preview.siteName {
                        Text(Highlighter.apply(searchTerms, to: siteName)).fontWeight(.medium)
                    }
                    if let title = preview.title {
                        Text(Highlighter.apply(searchTerms, to: title)).fontWeight(.semibold)
                    }
                    if let summary = preview.summary {
                        Text(Highlighter.apply(searchTerms, to: summary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Telegram's small thumbnail: 54pt in the top-right corner, for images that don't warrant full width.
                if let image = preview.image, !image.isLarge {
                    RemoteImage(image: image, size: CGSize(width: Self.thumbnailSide, height: Self.thumbnailSide))
                        .id(revision)
                        .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(.top, 2)
                }
            }
            if let image = preview.image, image.isLarge {
                let aspect = min(max(image.aspectRatio, 0.8), 3)
                Color.clear
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        RemoteImage(image: image, size: CGSize(width: largeImageWidth, height: largeImageWidth / aspect))
                            .id(revision)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(.top, 3)
            }
        }
        .font(.system(size: textSize.preview))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 3, leading: 7, bottom: 4.5, trailing: 6))
        .background {
            ZStack(alignment: .leading) {
                Color.white.opacity(0.1)
                Color.white.frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url { openURL(url) }
        }
    }
}

/// Puts a bubble at the row's trailing edge, `Metrics.bubbleTrailing` in, leaving at least `Metrics.bubbleLeadingSpace`
/// beside it. On iOS that room depends on the row's width, which a layout is given; reading it in each bubble would
/// take a GeometryReader, which the feed can't afford.
private struct BubbleRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        return CGSize(width: width, height: subviews.first?.sizeThatFits(bubbleProposal(rowWidth: width)).height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bubble = subviews.first else { return }
        let bubbleProposal = bubbleProposal(rowWidth: bounds.width)
        let width = bubble.sizeThatFits(bubbleProposal).width
        bubble.place(at: CGPoint(x: bounds.maxX - Metrics.bubbleTrailing - width, y: bounds.minY), proposal: bubbleProposal)
    }

    private func bubbleProposal(rowWidth: CGFloat) -> ProposedViewSize {
        let width = rowWidth - Metrics.bubbleLeadingSpace(rowWidth: rowWidth) - Metrics.bubbleTrailing
        return ProposedViewSize(width: max(0, width), height: nil)
    }
}

/// Offers its content at most `max` points of width but, unlike `.frame(maxWidth:)`, still hugs short content. The
/// content always gets the height it asks for: a VStack given a fixed height shares it among its flexible children, so
/// a preview's text could lose lines to its image once the text is large.
private struct CappedWidth: Layout {
    var max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = Swift.min(proposal.width ?? max, max)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

@MainActor
enum Linkifier {
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let range = Range(match.range, in: result) else { continue }
            result[range].link = url
            result[range].swiftUI.underlineStyle = .single
        }
        return result
    }

    /// The first web link in `text`. A bare "example.com" comes back from the detector as http://; it's asked for
    /// over https instead, which nearly every site serves and which App Transport Security requires.
    static func firstURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
            let typed = (text as NSString).substring(with: match.range).lowercased()
            if scheme == "http", !typed.hasPrefix("http"), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = "https"
                return components.url ?? url
            }
            return url
        }
        return nil
    }
}

/// Marks search matches in text. `source` must be the plain string `text` was built from.
enum Highlighter {
    static func apply(_ terms: [String], to text: String) -> AttributedString {
        apply(terms, to: AttributedString(text), source: text)
    }

    static func apply(_ terms: [String], to text: AttributedString, source: String) -> AttributedString {
        guard !terms.isEmpty else { return text }
        var text = text
        for range in SearchText.ranges(of: terms, in: source) {
            guard let range = Range(range, in: text) else { continue }
            text[range].swiftUI.backgroundColor = Theme.searchHighlight
        }
        return text
    }
}
