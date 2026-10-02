import Foundation

/// How a search result matched the query. Matches by meaning come separately, as related links.
public enum SearchMatch: Hashable, Sendable {
    /// Every query word is a whole word in the item.
    case exact
    /// Every query word starts a word in the item, at least one only as its beginning.
    case prefix
    /// At least one query word matched only through another spelling.
    case typo
    /// It needed Apple Intelligence's tags: some query word is in them but not in the item itself.
    case tag
}

public struct SearchResult: Hashable, Sendable {
    public let id: UUID
    public let match: SearchMatch
}

public struct SearchResults: Hashable, Sendable {
    /// Newest first, the order Telegram shows search results in.
    public let items: [SearchResult]
    /// Folded words to highlight in the results: the query's words, and the other spellings searched for them.
    public let highlights: [String]

    public static let empty = SearchResults(items: [], highlights: [])
}
