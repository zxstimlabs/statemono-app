import Foundation
import Observation

/// In-chat search: which messages match the query and which one is showing.
/// Matching runs in memory for now; it moves to FTS5 in StatemonoKit with the same folding rules.
@MainActor @Observable
final class ChatSearch {
    var isActive = false
    var query = ""
    private(set) var terms: [String] = []
    /// Matching message IDs, oldest first.
    private(set) var results: [UUID] = []
    private(set) var currentIndex: Int?

    var current: UUID? { currentIndex.map { results[$0] } }
    var canShowOlder: Bool { (currentIndex ?? 0) > 0 }
    var canShowNewer: Bool { currentIndex.map { $0 < results.count - 1 } ?? false }

    /// Recomputes the results and selects the newest match.
    func update(in messages: [Message]) {
        terms = SearchText.terms(in: query)
        results = terms.isEmpty ? [] : messages.filter { SearchText.matches($0, terms: terms) }.map(\.id)
        currentIndex = results.isEmpty ? nil : results.count - 1
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

    /// Every term has to appear somewhere in the message or its preview.
    static func matches(_ message: Message, terms: [String]) -> Bool {
        let fields = [message.text, message.preview?.siteName, message.preview?.title, message.preview?.summary]
            .compactMap { $0 }
            .map(fold)
        return terms.allSatisfy { term in fields.contains { $0.range(of: term, options: options) != nil } }
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
