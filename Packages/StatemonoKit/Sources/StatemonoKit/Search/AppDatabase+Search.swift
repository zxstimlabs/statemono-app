import Foundation
import GRDB

extension AppDatabase {
    /// Items where every word of `query` starts a word in the text or preview, newest first, ignoring case and
    /// accents: "grd" finds "GRDB". A word that matches nothing as typed also tries other spellings in the index
    /// (`SearchVocabulary.alternatives`), so "levenshtien" finds "Levenshtein".
    public func search(_ query: String) async throws -> SearchResults {
        let words = try await writer.read { db in try Self.searchWords(in: query, db) }
        guard !words.isEmpty else { return .empty }
        let vocabulary = try await searchVocabulary()
        let alternatives = words.enumerated().map { index, word in
            vocabulary.alternatives(for: word, isLast: index == words.count - 1)
        }

        let exact = words.map { Self.quoted($0) }.joined(separator: " AND ")
        let prefix = words.map { Self.quoted($0) + "*" }.joined(separator: " AND ")
        let tolerant = zip(words, alternatives).map { word, alternatives in
            guard !alternatives.isEmpty else { return Self.quoted(word) + "*" }
            let options = [Self.quoted(word) + "*"] + alternatives.map { Self.quoted($0.text) + ($0.isPrefix ? "*" : "") }
            return "(" + options.joined(separator: " OR ") + ")"
        }.joined(separator: " AND ")
        let hasAlternatives = alternatives.contains { !$0.isEmpty }

        let items = try await writer.read { db in
            let found = try Self.items(matching: hasAlternatives ? tolerant : prefix, db)
            guard !found.isEmpty else { return [SearchResult]() }
            let exactMatches = Set(try Self.items(matching: exact, db))
            let prefixMatches = hasAlternatives ? Set(try Self.items(matching: prefix, db)) : Set(found)
            return found.map { id in
                SearchResult(id: id, match: exactMatches.contains(id) ? .exact : prefixMatches.contains(id) ? .prefix : .typo)
            }
        }
        return SearchResults(items: items, highlights: words + alternatives.flatMap { $0.map(\.text) })
    }

    /// The items behind a page of search results, with their previews, in the order given. Items deleted since the
    /// search are left out.
    public func entries(for ids: [UUID]) async throws -> [FeedEntry] {
        guard !ids.isEmpty else { return [] }
        let found = try await writer.read { db in
            try Item
                .filter(ids.contains(Item.Columns.id) && Item.Columns.deletedAt == nil)
                .including(optional: Item.previewImage)
                .asRequest(of: FeedEntry.self)
                .fetchAll(db)
        }
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.item.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// The query's words as the index stores them: split and folded by the search tokenizer.
    static func searchWords(in query: String, _ db: Database) throws -> [String] {
        try db.makeTokenizer(StatemonoTokenizer.tokenizerDescriptor())
            .tokenize(query: query)
            .filter { !$0.flags.contains(.colocated) }
            .map(\.token)
    }

    private static func quoted(_ word: String) -> String {
        "\"" + word.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Live items matching an FTS5 query, newest first.
    private static func items(matching pattern: String, _ db: Database) throws -> [UUID] {
        try UUID.fetchAll(db, sql: """
            SELECT item.id FROM item
            JOIN itemSearch ON itemSearch.rowid = item.rowid
            WHERE itemSearch MATCH ? AND item.deletedAt IS NULL
            ORDER BY item.createdAt DESC
            """, arguments: [pattern])
    }

    // MARK: - Vocabulary

    /// The index's words, read again only when items have changed since the last read.
    func searchVocabulary() async throws -> SearchVocabulary {
        let version = try await writer.read { db in try VocabularyVersion(db) }
        if let cached = vocabularyCache.withLock({ $0 }), cached.version == version {
            return cached.vocabulary
        }
        // `fts5vocab` needs a table of its own. A temporary one is created on the writer's connection, since reader
        // connections are read-only, and it lasts as long as that connection.
        let (current, vocabulary) = try await writer.writeWithoutTransaction { db in
            try db.execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS temp.itemSearchVocabulary USING fts5vocab(main, itemSearch, row)")
            let entries = try Row.fetchAll(db, sql: "SELECT term, doc FROM temp.itemSearchVocabulary")
                .map { (text: $0[0] as String, documents: $0[1] as Int) }
            return (try VocabularyVersion(db), SearchVocabulary(entries))
        }
        vocabularyCache.withLock { $0 = CachedVocabulary(version: current, vocabulary: vocabulary) }
        return vocabulary
    }
}

struct CachedVocabulary: Sendable {
    let version: VocabularyVersion
    let vocabulary: SearchVocabulary
}

/// Changes whenever the index's words may have: an item added, edited or deleted (`updatedAt`), or a preview saved.
/// It's cheap to read, and it also sees writes from other processes, such as the share extension.
struct VocabularyVersion: Equatable, Sendable {
    let count: Int
    let lastUpdate: String?
    let lastPreview: String?

    init(_ db: Database) throws {
        let row = try Row.fetchOne(db, sql: "SELECT count(*), max(updatedAt), max(previewFetchedAt) FROM item")
        count = row?[0] ?? 0
        lastUpdate = row?[1]
        lastPreview = row?[2]
    }
}
