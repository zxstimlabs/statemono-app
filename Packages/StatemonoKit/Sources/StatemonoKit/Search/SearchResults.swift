import Foundation

/// How a search result matched the query. Later tiers of the search plan add matches by tag and by meaning.
public enum SearchMatch: Hashable, Sendable {
    /// Every query word is a whole word in the item.
    case exact
    /// Every query word starts a word in the item, at least one only as its beginning.
    case prefix
    /// At least one query word matched only through another spelling.
    case typo
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
