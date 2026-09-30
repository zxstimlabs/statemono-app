import Foundation
import Testing
@testable import StatemonoKit

/// The model itself is checked against swift-embeddings in Tools/SearchEval (`check`), since it needs the 133MB download.
/// These cover the tokenizer and the vectors' storage.
struct WordPieceTokenizerTests {
    /// Ids are line numbers: [PAD] 0, [UNK] 1, [CLS] 2, [SEP] 3, then the words.
    let tokenizer = try! WordPieceTokenizer(vocabulary: """
        [PAD]
        [UNK]
        [CLS]
        [SEP]
        hello
        world
        ##s
        ,
        !
        cafe
        un
        ##aff
        ##able
        東
        京
        $

        """)

    @Test func `words are lowercased, lose their accents, and split on punctuation`() {
        #expect(tokenizer.tokenize("Hello, Worlds! CAFÉ") == [2, 4, 7, 5, 6, 8, 9, 3])
    }

    @Test func `a word splits into the longest pieces the vocabulary has`() {
        #expect(tokenizer.tokenize("unaffable") == [2, 10, 11, 12, 3])
    }

    @Test func `a word with a piece missing from the vocabulary is unknown as a whole`() {
        #expect(tokenizer.tokenize("unafx hello") == [2, 1, 4, 3])
    }

    @Test func `CJK characters are words of their own, and ASCII symbols are punctuation`() {
        #expect(tokenizer.tokenize("東京$hello") == [2, 13, 14, 15, 4, 3])
    }

    @Test func `long text is cut but keeps its end token`() {
        let ids = tokenizer.tokenize(String(repeating: "hello ", count: 20), maxTokens: 8)
        #expect(ids == [2, 4, 4, 4, 4, 4, 4, 3])
    }
}

@MainActor
struct VectorTests {
    let media = MediaStore(directory: FileManager.default.temporaryDirectory.appending(path: "vector-media-\(UUID().uuidString)"))
    let model = "test@1"

    func makeDatabase() throws -> AppDatabase {
        try AppDatabase.inMemory(media: media)
    }

    /// Makes every waiting item's vector: a unit vector along the axis `axis(text)` picks.
    func prepare(_ db: AppDatabase, model: String? = nil, axis: (String) -> Int) async throws {
        let work = try await db.vectorWork(model: model ?? self.model).work
        try await db.saveVectors(work.map { ($0, Self.unit(axis($0.text))) }, model: model ?? self.model)
    }

    static func unit(_ axis: Int, dimension: Int = 4) -> [Float] {
        (0..<dimension).map { $0 == axis ? 1 : 0 }
    }

    @Test func `links wait for their preview, and the vector reads the preview and the text`() async throws {
        let db = try makeDatabase()
        let note = try db.insertItem(text: "a note", link: nil)
        let link = try db.insertItem(text: "https://example.com", link: URL(string: "https://example.com"))

        var (work, progress) = try await db.vectorWork(model: model)
        #expect(work.map(\.text) == ["a note"])
        #expect(progress == VectorProgress(ready: 0, total: 1))

        try await db.savePreview(LinkPreview(siteName: "Example", title: "Title", summary: "Summary"), for: link.id)
        (work, progress) = try await db.vectorWork(model: model)
        #expect(work.map(\.text) == ["Title\nExample\nSummary\nhttps://example.com", "a note"])
        #expect(progress.total == 2)
        _ = note
    }

    @Test func `saved vectors are done until the text or the model changes`() async throws {
        let db = try makeDatabase()
        let link = try db.insertItem(text: "https://example.com", link: URL(string: "https://example.com"))
        try await db.savePreview(LinkPreview(title: "Old title"), for: link.id)
        try await prepare(db) { _ in 0 }
        #expect(try await db.vectorWork(model: model).progress == VectorProgress(ready: 1, total: 1))

        // A reloaded preview changes the text, so the vector is made again.
        try await db.savePreview(LinkPreview(title: "New title"), for: link.id)
        #expect(try await db.vectorWork(model: model).work.map(\.text) == ["New title\nhttps://example.com"])
        try await prepare(db) { _ in 0 }
        // Another model makes every vector again.
        #expect(try await db.vectorWork(model: "other@2").work.count == 1)
    }

    @Test func `related items are the closest, best first, without the excluded or the deleted`() async throws {
        let db = try makeDatabase()
        let apple = try db.insertItem(text: "apple", link: nil)
        let banana = try db.insertItem(text: "banana", link: nil)
        let cherry = try db.insertItem(text: "cherry", link: nil)
        let date = try db.insertItem(text: "date", link: nil)
        let vectors: [String: [Float]] = [
            "apple": [1, 0, 0, 0],
            "banana": BertEmbedder.normalized([0.9, 0.1, 0, 0]),
            "cherry": BertEmbedder.normalized([0.5, 0.5, 0, 0]),
            "date": [0, 0, 1, 0],
        ]
        let work = try await db.vectorWork(model: model).work
        try await db.saveVectors(work.map { ($0, vectors[$0.text]!) }, model: model)

        let query: [Float] = [1, 0, 0, 0]
        #expect(try await db.relatedItems(to: query, model: model, excluding: [], count: 3) == [apple.id, banana.id, cherry.id])
        #expect(try await db.relatedItems(to: query, model: model, excluding: [apple.id], count: 2) == [banana.id, cherry.id])

        try db.deleteItem(banana.id)
        #expect(try await db.relatedItems(to: query, model: model, excluding: [], count: 3) == [apple.id, cherry.id, date.id])
        // Vectors from another model aren't compared.
        #expect(try await db.relatedItems(to: query, model: "other@2", excluding: [], count: 3).isEmpty)
    }

    @Test func `turning Smart Search off removes every vector`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "apple", link: nil)
        try await prepare(db) { _ in 0 }
        #expect(try await db.vectorStorageSize() > 0)
        #expect(try await db.relatedItems(to: Self.unit(0), model: model, excluding: [], count: 3) == [item.id])

        try await db.removeAllVectors()
        #expect(try await db.vectorStorageSize() == 0)
        #expect(try await db.relatedItems(to: Self.unit(0), model: model, excluding: [], count: 3).isEmpty)
        #expect(try await db.vectorWork(model: model).progress == VectorProgress(ready: 0, total: 1))
    }
}
