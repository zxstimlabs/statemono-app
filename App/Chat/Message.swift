import Foundation

struct Message: Identifiable, Hashable {
    let id: UUID
    var text: String
    var date: Date
    var preview: LinkPreview?
}

struct LinkPreview: Hashable {
    var siteName: String?
    var title: String?
    var summary: String?
    var image: PreviewImage?
}

struct PreviewImage: Hashable {
    var url: URL
    /// Width over height, known up front so the bubble doesn't jump when the image loads.
    var aspectRatio: CGFloat
}

/// Where a bubble sits in a run of messages sent close together. Only the last one gets a tail.
struct BubblePosition: Hashable {
    var isFirstInGroup = true
    var isLastInGroup = true
}

enum FeedItem: Identifiable {
    case day(Date)
    case message(Message, BubblePosition)

    static let groupingInterval: TimeInterval = 5 * 60

    var id: String {
        switch self {
        case .day(let date): "day-\(date.timeIntervalSinceReferenceDate)"
        case .message(let message, _): message.id.uuidString
        }
    }

    /// Interleaves day separators and marks message groups. `messages` must be oldest first.
    static func build(from messages: [Message], calendar: Calendar = .current) -> [FeedItem] {
        func grouped(_ a: Message, _ b: Message) -> Bool {
            calendar.isDate(a.date, inSameDayAs: b.date) && b.date.timeIntervalSince(a.date) <= groupingInterval
        }

        var items: [FeedItem] = []
        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            if previous.map({ !calendar.isDate($0.date, inSameDayAs: message.date) }) ?? true {
                items.append(.day(calendar.startOfDay(for: message.date)))
            }
            let position = BubblePosition(
                isFirstInGroup: previous.map { !grouped($0, message) } ?? true,
                isLastInGroup: next.map { !grouped(message, $0) } ?? true
            )
            items.append(.message(message, position))
        }
        return items
    }
}
