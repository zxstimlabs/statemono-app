import SwiftUI

struct MessageBubble: View {
    let message: Message
    let position: BubblePosition

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 56)
            CappedWidth(max: message.preview == nil ? Metrics.textMaxWidth : Metrics.previewWidth) {
                content
            }
            .padding(EdgeInsets(top: 7, leading: 10, bottom: 6, trailing: 10 + Metrics.tailWidth))
            .background {
                BubbleFill(shape: BubbleShape(
                    topTrailingRadius: position.isFirstInGroup ? Metrics.bubbleRadius : Metrics.groupedRadius,
                    bottomTrailingRadius: Metrics.groupedRadius,
                    hasTail: position.isLastInGroup
                ))
            }
        }
        .padding(.trailing, Metrics.bubbleTrailing)
        .padding(.top, position.isFirstInGroup ? 4 : 2)
    }

    @ViewBuilder private var content: some View {
        if let preview = message.preview {
            VStack(alignment: .leading, spacing: 0) {
                messageText(Linkifier.attributed(message.text))
                LinkPreviewView(preview: preview, url: Linkifier.firstURL(in: message.text))
                    .padding(.top, 5)
                TimeLabel(date: message.date)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 3)
            }
        } else {
            // Telegram tucks the time into the last line when it fits. Reserve that space with invisible text;
            // if the last line is too full, the reserve wraps and the time drops onto its own line.
            messageText(Linkifier.attributed(message.text) + TimeLabel.reserve(for: message.date))
                .overlay(alignment: .bottomTrailing) {
                    TimeLabel(date: message.date)
                }
        }
    }

    private func messageText(_ text: AttributedString) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .tint(.white)
    }
}

/// Fills the bubble with the window-pinned gradient.
private struct BubbleFill: View {
    let shape: BubbleShape
    @Environment(\.chatViewportHeight) private var viewportHeight

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(ChatView.coordinateSpace))
            let height = max(frame.height, 1)
            shape.fill(LinearGradient(
                colors: [Theme.bubbleTop, Theme.bubbleBottom],
                startPoint: UnitPoint(x: 0.5, y: -frame.minY / height),
                endPoint: UnitPoint(x: 0.5, y: (viewportHeight - frame.minY) / height)
            ))
        }
    }
}

struct TimeLabel: View {
    let date: Date

    static let format = Date.FormatStyle.dateTime.hour().minute()

    /// Invisible text as wide as a `TimeLabel` plus a small gap. The leading plain space is where it may wrap.
    static func reserve(for date: Date) -> AttributedString {
        var reserve = AttributedString(" \u{00A0}" + date.formatted(format) + String(repeating: "\u{00A0}", count: 6))
        reserve.swiftUI.font = .system(size: 11)
        reserve.swiftUI.foregroundColor = .clear
        return reserve
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(date, format: Self.format)
            ReadChecks()
                .stroke(style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                .frame(width: 12.5, height: 7.5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white)
    }
}

private struct LinkPreviewView: View {
    let preview: LinkPreview
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let siteName = preview.siteName {
                Text(siteName).fontWeight(.medium)
            }
            if let title = preview.title {
                Text(title).fontWeight(.semibold)
            }
            if let summary = preview.summary {
                Text(summary)
            }
            if let image = preview.image {
                Color.clear
                    .aspectRatio(min(max(image.aspectRatio, 0.8), 3), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay { LocalImage(url: image.url) }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(.top, 3)
            }
        }
        .font(.system(size: 12))
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

/// Offers its content at most `max` points of width but, unlike `.frame(maxWidth:)`, still hugs short content.
private struct CappedWidth: Layout {
    var max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = Swift.min(proposal.width ?? max, max)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
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

    static func firstURL(in text: String) -> URL? {
        detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url
    }
}
