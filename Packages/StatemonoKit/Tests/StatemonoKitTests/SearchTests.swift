import Foundation
import Testing
@testable import StatemonoKit

@MainActor
struct SearchTests {
    let media = MediaStore(directory: FileManager.default.temporaryDirectory.appending(path: "search-media-\(UUID().uuidString)"))

    func makeDatabase() throws -> AppDatabase {
        try AppDatabase.inMemory(media: media)
    }

    /// A saved link with its preview's title.
    @discardableResult
    func save(_ link: String, title: String, in db: AppDatabase, date: Date = .now) async throws -> Item {
        let item = try db.insertItem(text: link, link: URL(string: link), date: date)
        try await db.savePreview(LinkPreview(siteName: "Wikipedia", title: title), for: item.id)
        return item
    }

    @Test func `a typo in a finished word finds the right spelling`() async throws {
        let db = try makeDatabase()
        let item = try await save("https://en.wikipedia.org/wiki/Levenshtein_distance", title: "Levenshtein distance", in: db)
        try await save("https://en.wikipedia.org/wiki/SQLite", title: "SQLite", in: db)

        let results = try await db.search("levenshtien distance")
        #expect(results.items == [SearchResult(id: item.id, match: .typo)])
        #expect(results.highlights.contains("levenshtein"))
        // Two edits for words of 8 letters or more.
        #expect(try await db.search("levenstien").items.map(\.id) == [item.id])
    }

    @Test func `a typo in the word still being typed finds words that start right`() async throws {
        let db = try makeDatabase()
        let item = try await save("https://en.wikipedia.org/wiki/Levenshtein_distance", title: "Levenshtein distance", in: db)

        // "levenhs" is "levensh" with two letters swapped, the start of "levenshtein".
        let results = try await db.search("distance levenhs")
        #expect(results.items == [SearchResult(id: item.id, match: .typo)])
        #expect(results.highlights.contains("levensh"))
        // Only the last word can be unfinished; before it, a word has to be a whole word within reach.
        #expect(try await db.search("levenhs distance").items.isEmpty)
    }

    @Test func `a word spelled right gets no other spellings`() async throws {
        let db = try makeDatabase()
        let form = try db.insertItem(text: "form builder", link: nil)
        try db.insertItem(text: "from scratch", link: nil)
        #expect(try await db.search("form").items.map(\.id) == [form.id])
        #expect(try await db.search("form").highlights == ["form"])
    }

    @Test func `short words match only as typed`() async throws {
        let db = try makeDatabase()
        try db.insertItem(text: "test", link: nil)
        #expect(try await db.search("tst").items.isEmpty)
        #expect(try await db.search("tes").items.count == 1)
    }

    @Test func `results are newest first and say how they matched`() async throws {
        let db = try makeDatabase()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let whole = try db.insertItem(text: "swift notes", link: nil, date: base)
        let start = try db.insertItem(text: "swiftui notes", link: nil, date: base.addingTimeInterval(60))
        #expect(try await db.search("swift").items == [
            SearchResult(id: start.id, match: .prefix),
            SearchResult(id: whole.id, match: .exact),
        ])
    }

    @Test func `new words are found right after they're saved`() async throws {
        let db = try makeDatabase()
        try await save("https://en.wikipedia.org/wiki/SQLite", title: "SQLite", in: db)
        #expect(try await db.search("photosinthesis").items.isEmpty)
        // The vocabulary was read for the search above. A new item and its preview must refresh it.
        let item = try await save("https://en.wikipedia.org/wiki/Photosynthesis", title: "Photosynthesis", in: db)
        #expect(try await db.search("photosinthesis").items.map(\.id) == [item.id])
    }

    @Test func `a page of results comes back in order, without deleted items`() async throws {
        let db = try makeDatabase()
        let first = try await save("https://en.wikipedia.org/wiki/SQLite", title: "SQLite", in: db)
        let second = try db.insertItem(text: "plain note", link: nil)
        let deleted = try db.insertItem(text: "gone", link: nil)
        try db.deleteItem(deleted.id)
        let entries = try await db.entries(for: [second.id, deleted.id, first.id])
        #expect(entries.map(\.item.id) == [second.id, first.id])
        #expect(entries.last?.preview?.title == "SQLite")
    }

    @Test func `alternatives are the most common, at most ten`() {
        let vocabulary = SearchVocabulary((0..<15).map { index in
            (text: "cat\(Character(UnicodeScalar(UInt8(97 + index))))s", documents: index)
        } + [(text: "catxy", documents: 1)])
        let alternatives = vocabulary.alternatives(for: "cat_s", isLast: false)
        #expect(alternatives.count == 10)
        #expect(alternatives.first == SearchAlternative(text: "catos", isPrefix: false))
        #expect(!alternatives.contains { $0.text == "catxy" })
    }

    @Test func `edit distance counts a swap of neighbors as one edit`() {
        func distance(_ a: String, _ b: String) -> Int {
            editDistance(Array(a.unicodeScalars), Array(b.unicodeScalars)[...], limit: 3)
        }
        #expect(distance("levenshtein", "levenshtein") == 0)
        #expect(distance("levenshtien", "levenshtein") == 1)
        #expect(distance("sqlte", "sqlite") == 1)
        #expect(distance("form", "from") == 1)
        #expect(distance("kitten", "sitting") == 3)
        #expect(distance("abcdefgh", "zyxwvuts") == 4) // past the limit: stops at limit + 1
    }
}
