import Foundation
import Observation
import StatemonoKit

/// In-chat search over the whole history, through the database's full-text index (`AppDatabase.search`): every word
/// must start a word in the message or its preview, ignoring case and tone marks, with đ matching d. Bubbles highlight
/// matches with the same folding (`SearchText`).
@MainActor @Observable
final class ChatSearch {
    var isActive = false
    var query = ""
    private(set) var terms: [String] = []
    /// Matching message IDs, oldest first.
    private(set) var results: [UUID] = []
    private(set) var currentIndex: Int?
    /// Discards results from a query that was replaced while it ran.
    @ObservationIgnored private var generation = 0

    var current: UUID? { currentIndex.map { results[$0] } }
    var canShowOlder: Bool { (currentIndex ?? 0) > 0 }
    var canShowNewer: Bool { currentIndex.map { $0 < results.count - 1 } ?? false }

    /// Searches again for the current query and selects the newest match.
    func update(using database: AppDatabase) {
        terms = SearchText.terms(in: query)
        generation += 1
        let generation = generation
        let query = query
        Task {
            let ids = (try? await database.search(query)) ?? []
            guard generation == self.generation else { return }
            results = ids
            currentIndex = ids.isEmpty ? nil : ids.count - 1
        }
    }

    func showOlder() {
        if canShowOlder, let index = currentIndex { currentIndex = index - 1 }
    }

    func showNewer() {
        if canShowNewer, let index = currentIndex { currentIndex = index + 1 }
    }

    func close() {
        isActive = false
        query = ""
        terms = []
        results = []
        currentIndex = nil
    }
}

enum SearchText {
    private static let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Foundation's diacritic folding treats đ/Đ as their own letter, so they're folded to d by hand.
    /// Both are one UTF-16 unit, so ranges found in folded text line up with the original.
    static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
    }

    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
    }

    /// Every occurrence of every term in `text`, as UTF-16 ranges of the original string.
    static func ranges(of terms: [String], in text: String) -> [NSRange] {
        let folded = fold(text) as NSString
        var ranges: [NSRange] = []
        for term in terms {
            var location = 0
            while location < folded.length {
                let found = folded.range(of: term, options: options, range: NSRange(location: location, length: folded.length - location))
                guard found.location != NSNotFound else { break }
                ranges.append(found)
                location = found.location + max(found.length, 1)
            }
        }
        return ranges
    }
}
