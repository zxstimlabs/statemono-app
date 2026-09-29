import Foundation
import Observation
import StatemonoKit

/// In-chat search over the whole history, through the database's full-text index (`AppDatabase.search`): every word
/// must start a word in the message or its preview, ignoring case and accents, and a word that matches nothing as typed
/// also tries other spellings. Bubbles highlight the words searched for, with the same folding (`SearchText`).
@MainActor @Observable
final class ChatSearch {
    /// Telegram-iOS waits this long after a keystroke before searching, and typing again replaces the wait
    /// (`ChatControllerUpdateSearch`).
    static let delay: Duration = .milliseconds(200)

    /// Rows of the results list load this many at a time, like Telegram's search pages.
    static let rowPage = 100

    var isActive = false
    var query = ""
    /// Telegram-iOS's "Show as List": the results as a list over the chat instead of stepping through it.
    var isShowingList = false
    /// Folded words to highlight: the query's words and the other spellings searched for them.
    private(set) var terms: [String] = []
    /// Matching message IDs, newest first.
    private(set) var results: [UUID] = []
    private(set) var currentIndex: Int?
    /// The results list's rows, newest first, loaded a page at a time as it scrolls.
    private(set) var rows: [Message] = []
    /// Changes with every new set of results, so the list starts again from the top.
    private(set) var resultsVersion = 0
    /// The Mac dropdown's keyboard cursor: arrow keys move it and Return opens its row. Like TelegramSwift's, it starts
    /// on the first row when results arrive.
    var cursor: UUID?
    /// Discards a search that was replaced while it waited or ran.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var database: AppDatabase?
    /// How many results have had their rows loaded. Deleted messages are skipped, so it can be more than `rows`.
    @ObservationIgnored private var loadedResults = 0
    @ObservationIgnored private var isLoadingRows = false

    var current: UUID? { currentIndex.map { results[$0] } }
    var canShowOlder: Bool { currentIndex.map { $0 < results.count - 1 } ?? false }
    var canShowNewer: Bool { (currentIndex ?? 0) > 0 }

    /// Searches for the current query after `delay`, then selects the newest match. An empty query clears at once.
    func update(using database: AppDatabase) {
        self.database = database
        generation += 1
        let generation = generation
        let query = query
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show(.empty)
            return
        }
        Task {
            try? await Task.sleep(for: Self.delay)
            guard generation == self.generation else { return }
            let found = (try? await database.search(query)) ?? .empty
            guard generation == self.generation else { return }
            show(found)
        }
    }

    func showOlder() {
        if canShowOlder, let index = currentIndex { currentIndex = index + 1 }
    }

    func showNewer() {
        if canShowNewer, let index = currentIndex { currentIndex = index - 1 }
    }

    /// Makes `id` the current result, as when it's picked in the results list.
    func select(_ id: UUID) {
        if let index = results.firstIndex(of: id) { currentIndex = index }
    }

    /// Loads the next page of rows once the list has scrolled within 5 rows of the end, as Telegram does.
    func loadRows(near row: Int) {
        guard row >= rows.count - 5, loadedResults < results.count, !isLoadingRows, let database else { return }
        isLoadingRows = true
        let generation = generation
        let page = Array(results[loadedResults..<min(loadedResults + Self.rowPage, results.count)])
        Task {
            defer { isLoadingRows = false }
            let entries = (try? await database.entries(for: page)) ?? []
            guard generation == self.generation else { return }
            let isFirstPage = rows.isEmpty
            loadedResults += page.count
            rows += entries.map(Message.init)
            if isFirstPage { cursor = rows.first?.id }
        }
    }

    /// Moves the cursor down (`step` 1) or up (-1) a row, wrapping around at the ends as TelegramSwift's does.
    func moveCursor(by step: Int) {
        guard !rows.isEmpty else { return }
        let index = cursor.flatMap { id in rows.firstIndex { $0.id == id } }
        let next = index.map { ($0 + step + rows.count) % rows.count } ?? (step > 0 ? 0 : rows.count - 1)
        cursor = rows[next].id
        loadRows(near: next)
    }

    func close() {
        generation += 1
        isActive = false
        isShowingList = false
        query = ""
        show(.empty)
    }

    private func show(_ found: SearchResults) {
        terms = found.highlights
        results = found.items.map(\.id)
        currentIndex = results.isEmpty ? nil : 0
        resultsVersion += 1
        cursor = nil
        rows = []
        loadedResults = 0
        isLoadingRows = false
        loadRows(near: 0)
    }
}

enum SearchText {
    private static let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Foundation's diacritic folding treats đ/Đ as their own letter, so they're folded to d by hand.
    /// Both are one UTF-16 unit, so ranges found in folded text line up with the original.
    static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
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
