import Foundation
import Testing
@testable import StatemonoKit

/// Apple Intelligence tags (docs/search-plan.md, Phase 4): stored on the item, searched with it, made on each device.
@MainActor
struct TagsTests {
    let media = MediaStore(directory: FileManager.default.temporaryDirectory.appending(path: "tags-media-\(UUID().uuidString)"))
    let base = Date(timeIntervalSince1970: 1_000_000)

    func makeDatabase() throws -> AppDatabase {
        try AppDatabase.inMemory(media: media)
    }

    @Test func `links wait for their preview, newest first`() async throws {
        let db = try makeDatabase()
        let note = try db.insertItem(text: "groceries for the week", link: nil, date: base)
        let link = try db.insertItem(text: "https://linear.app", link: URL(string: "https://linear.app"), date: base.addingTimeInterval(1))
        var (work, progress) = try await db.tagWork(retagSince: nil, limit: 10)
        #expect(work.map(\.id) == [note.id])
        #expect(progress == TagProgress(tagged: 0, total: 1))

        try await db.savePreview(LinkPreview(siteName: "Linear", title: "Plan and build products"), for: link.id)
        (work, progress) = try await db.tagWork(retagSince: nil, limit: 10)
        #expect(work.map(\.id) == [link.id, note.id])
        #expect(work.first?.text == "Plan and build products\nLinear\nhttps://linear.app")
    }

    @Test func `tags are searched, and a match only through them says so`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "https://linear.app", link: URL(string: "https://linear.app"), date: base)
        try await db.savePreview(LinkPreview(siteName: "Linear", title: "Plan and build products"), for: item.id)
        #expect(try await db.search("issue tracker").items.isEmpty)

        try await db.saveTags(["project management", "issue tracker", "software"], for: item.id, osVersion: "27.0")
        let results = try await db.search("issue tracker")
        #expect(results.items == [SearchResult(id: item.id, match: .tag)])
        // A word in the item itself is a plain match.
        #expect(try await db.search("linear").items.first?.match == .exact)
        #expect(try await db.tags(for: item.id)?.tags == ["project management", "issue tracker", "software"])
        // Tags don't make the item dirty: they never sync.
        try await db.markSynced(item.id, updatedAt: item.updatedAt, systemFields: Data([1]))
        try await db.saveTags(["planning"], for: item.id, osVersion: "27.0")
        #expect(try await db.dirtyItemIDs().isEmpty)
    }

    @Test func `a refused try keeps the old tags and isn't retried`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "a note about espresso", link: nil, date: base)
        try await db.saveTags(["coffee"], for: item.id, osVersion: "27.0")
        try await db.saveTags(nil, for: item.id, osVersion: "27.0")
        #expect(try await db.tags(for: item.id)?.tags == ["coffee"])
        #expect(try await db.tagWork(retagSince: nil, limit: 10).work.isEmpty)
        #expect(try await db.tagWork(retagSince: nil, limit: 10).progress == TagProgress(tagged: 1, total: 1))
    }

    @Test func `re-tag all queues links tried before it started`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "a note about espresso", link: nil, date: base)
        try await db.saveTags(["coffee"], for: item.id, osVersion: "26.0")
        let started = Date.now.addingTimeInterval(1)
        #expect(try await db.tagWork(retagSince: started, limit: 10).work.map(\.id) == [item.id])
        try await Task.sleep(for: .milliseconds(1100))
        try await db.saveTags(["coffee", "drink"], for: item.id, osVersion: "27.0")
        #expect(try await db.tagWork(retagSince: started, limit: 10).work.isEmpty)
    }

    @Test func `turning tags off removes them`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "a note about espresso", link: nil, date: base)
        try await db.saveTags(["coffee"], for: item.id, osVersion: "27.0")
        #expect(try await db.tagStorageSize() > 0)
        try await db.removeAllTags()
        #expect(try await db.tags(for: item.id) == ItemTags(tags: [], attemptedAt: nil))
        #expect(try await db.search("coffee").items.isEmpty)
        #expect(try await db.tagWork(retagSince: nil, limit: 10).work.map(\.id) == [item.id])
    }

    @Test func `centered vectors rank by how a link differs from the rest`() async throws {
        let db = try makeDatabase()
        let a = try db.insertItem(text: "a", link: nil, date: base)
        let b = try db.insertItem(text: "b", link: nil, date: base.addingTimeInterval(1))
        let c = try db.insertItem(text: "c", link: nil, date: base.addingTimeInterval(2))
        // All three share a large common direction (the first axis), as Apple's vectors do; they differ in the others.
        func unit(_ v: [Float]) -> [Float] { let l = sqrt(v.reduce(0) { $0 + $1 * $1 }); return v.map { $0 / l } }
        let work = try await db.vectorWork(model: "m").work
        let vectors: [UUID: [Float]] = [a.id: unit([10, 1, 0]), b.id: unit([10, 0, 1]), c.id: unit([10, -1, -1])]
        try await db.saveVectors(work.map { w in (w, vectors[[a, b, c].first { $0.text == w.text }!.id]!) }, model: "m")
        let query = unit([10, 0.9, 0.1])
        let related = try await db.relatedItems(to: query, model: "m", centered: true, excluding: [], count: 1)
        #expect(related == [a.id])
    }
}
