import Foundation
import StatemonoKit

/// What a row of the search results shows for a message, following Telegram-iOS's search rows (`ChatListItem`) with the
/// author swapped for the link's title, since every message in Saved Messages is your own.
struct SearchRowContent {
    /// The preview's title, or its site. Nil for a message without a preview.
    let title: String?
    /// The text with the first match in it, cut to show that match (`SearchSnippet.cut`).
    let snippet: String
    /// Where the search terms match in `snippet`.
    let matches: [Range<String.Index>]

    init(message: Message, terms: [String]) {
        let preview = message.preview
        title = preview?.title ?? preview?.siteName
        // The message itself unless it's only the link, then the preview's description and title. The first of those
        // with a match wins; with none, the description, or the message.
        let isOnlyLink = message.link.map { message.text.trimmingCharacters(in: .whitespacesAndNewlines) == $0.absoluteString } ?? false
        let candidates = [isOnlyLink ? nil : message.text, preview?.summary, preview?.title, message.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let source = candidates.first { !SearchSnippet.matches(in: $0, terms: terms).isEmpty }
            ?? preview?.summary ?? message.text
        snippet = SearchSnippet.cut(source, terms: terms)
        matches = SearchSnippet.matches(in: snippet, terms: terms)
    }
}

/// Telegram-iOS's matching and cutting of search snippets (`SubstringSearch`, `ChatListItem`).
enum SearchSnippet {
    /// The words of `text` that match a term, whole words included. A word matches when it shares a beginning with a
    /// term and the rest of the longer one is under 37% of its length: "grd" marks "GRDB", "s" doesn't mark "swift".
    /// Words are runs of letters, digits, # and @, compared folded, like the search itself.
    static func matches(in text: String, terms: [String]) -> [Range<String.Index>] {
        guard !terms.isEmpty else { return [] }
        return words(in: text).filter { range in
            let word = fold(String(text[range]))
            return terms.contains { term in
                let common = zip(word, term).prefix { $0 == $1 }.count
                let longest = max(word.count, term.count)
                return common > 0 && Double(longest - common) / Double(longest) < 0.37
            }
        }
    }

    /// Line breaks become spaces. If the first match starts more than 24 characters in, the text starts at the nearest
    /// word beginning more than 12 characters before it, after "…".
    static func cut(_ text: String, terms: [String]) -> String {
        let flat = text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        guard let first = matches(in: flat, terms: terms).first?.lowerBound else { return flat }
        let origin = flat.distance(from: flat.startIndex, to: first)
        guard origin > 24 else { return flat }
        let start = words(in: flat)
            .map(\.lowerBound)
            .filter { $0 < first }
            .last { flat.distance(from: $0, to: first) > 12 }
        guard let start else { return flat }
        return "…" + flat[start...]
    }

    private static func words(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let isWordCharacter = character.isLetter || character.isNumber || character == "#" || character == "@"
            if isWordCharacter, start == nil {
                start = index
            } else if !isWordCharacter, let wordStart = start {
                ranges.append(wordStart..<index)
                start = nil
            }
            index = text.index(after: index)
        }
        if let start { ranges.append(start..<text.endIndex) }
        return ranges
    }

    private static func fold(_ word: String) -> String {
        SearchText.fold(word).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Dates in search results, by Telegram's rules: the time today, the weekday within the week, then a short date.
/// Telegram-iOS drops the year within the current year; TelegramSwift always shows it past a week.
enum SearchResultDate {
    static func string(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(.dateTime.hour().minute())
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? .max
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        if days < 7, sameYear {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        #if os(iOS)
        let template = sameYear ? "MMdd" : "MMddyy"
        #else
        let template = "dMMyy"
        #endif
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
