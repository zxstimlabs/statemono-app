import Foundation
import StatemonoKit

/// A feed item as the UI shows it, read from the database.
struct Message: Identifiable, Hashable {
    let id: UUID
    let text: String
    let date: Date
    /// The first web link in `text`, found when the item was saved.
    let link: URL?
    let preview: LinkPreview?
    /// When the preview was last fetched. It changes on a reload, so views showing its image load the new one.
    let previewRevision: Date?

    /// Whether a preview fetch has finished for the link, even one that found nothing.
    var hasFetchedPreview: Bool { previewRevision != nil }

    init(entry: FeedEntry) {
        id = entry.item.id
        text = entry.item.text
        date = entry.item.createdAt
        link = entry.item.link
        preview = entry.preview
        previewRevision = entry.item.previewFetchedAt
    }
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
