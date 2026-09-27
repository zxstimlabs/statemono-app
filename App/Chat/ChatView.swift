import SwiftUI

struct ChatView: View {
    static let coordinateSpace = "chat"

    @Environment(ChatStore.self) private var store
    @State private var draft = ""
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var viewportHeight: CGFloat = 0
    @State private var trafficLightsWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(FeedItem.build(from: store.messages)) { item in
                    switch item {
                    case .day(let date):
                        DaySeparator(date: date)
                    case .message(let message, let position):
                        MessageBubble(message: message, position: position)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .safeAreaInset(edge: .top, spacing: 0) {
            ChatHeader(leadingInset: trafficLightsWidth > 0 ? trafficLightsWidth + 12 : Metrics.sideMargin)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(text: $draft, onSend: send)
                .padding(.top, 4)
        }
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

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.send(draft)
        draft = ""
        withAnimation(.easeOut(duration: 0.2)) {
            scrollPosition.scrollTo(edge: .bottom)
        }
    }
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
}
