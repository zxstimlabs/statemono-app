import Foundation
import Testing
@testable import StatemonoKit

@MainActor
struct DatabaseTests {
    let media = MediaStore(directory: FileManager.default.temporaryDirectory.appending(path: "db-media-\(UUID().uuidString)"))

    func makeDatabase() throws -> AppDatabase {
        try AppDatabase.inMemory(media: media)
    }

    @Test func `feed is a window anchored at its oldest item`() async throws {
        let db = try makeDatabase()
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<5 {
            try db.insertItem(text: "note \(i)", link: nil, date: base.addingTimeInterval(Double(i)))
        }
        let start = try db.feedStart(newest: 3)
        var page: FeedPage?
        let observation = db.observeFeed(from: start) { page = $0 }
        defer { observation.cancel() }
        // `.immediate`: the first page arrives before observeFeed returns.
        #expect(page?.entries.map(\.item.text) == ["note 2", "note 3", "note 4"])
        #expect(page?.hasOlder == true)

        // A new item extends the window instead of pushing the oldest out.
        try db.insertItem(text: "note 5", link: nil, date: base.addingTimeInterval(5))
        try await Task.sleep(for: .milliseconds(50))
        #expect(page?.entries.map(\.item.text) == ["note 2", "note 3", "note 4", "note 5"])

        let earlier = try #require(start)
        #expect(try db.feedStart(before: earlier, adding: 1) == base.addingTimeInterval(1))
        #expect(try db.feedStart(before: earlier, adding: 2) == nil) // only two older: load everything
        #expect(try db.feedStart(newest: 10) == nil)
    }

    @Test func `search folds tone marks and đ, matches word prefixes`() async throws {
        let db = try makeDatabase()
        let vietnamese = try db.insertItem(text: "Đường Nguyễn Huệ ở Sài Gòn", link: nil)
        let github = try db.insertItem(text: "https://github.com/groue/GRDB.swift", link: URL(string: "https://github.com/groue/GRDB.swift"))
        #expect(try await db.search("duong") == [vietnamese.id])
        #expect(try await db.search("nguyen hue") == [vietnamese.id])
        #expect(try await db.search("đường") == [vietnamese.id])
        #expect(try await db.search("grd") == [github.id])
        #expect(try await db.search("groue swift") == [github.id])
        #expect(try await db.search("missing") == [])
        #expect(try await db.search("   ") == [])
    }

    @Test func `search covers preview text and skips deleted items`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "https://scriptc.dev/", link: URL(string: "https://scriptc.dev/"))
        try await db.savePreview(LinkPreview(siteName: "scriptc", title: "TypeScript-to-Native Compiler", summary: "Small, fast executables"), for: item.id)
        #expect(try await db.search("typescript native") == [item.id])
        try db.deleteItem(item.id)
        #expect(try await db.search("typescript") == [])
    }

    @Test func `deleting leaves a tombstone that drops out of the feed`() async throws {
        let db = try makeDatabase()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let kept = try db.insertItem(text: "kept", link: nil, date: base)
        let deleted = try db.insertItem(text: "deleted", link: nil, date: base.addingTimeInterval(1))
        try await db.writer.write { db in try db.execute(sql: "UPDATE item SET isDirty = 0") } // as if synced

        let deletedAt = base.addingTimeInterval(60)
        try db.deleteItem(deleted.id, date: deletedAt)
        try db.deleteItem(deleted.id, date: deletedAt.addingTimeInterval(60)) // already deleted: unchanged

        var page: FeedPage?
        let observation = db.observeFeed(from: nil) { page = $0 }
        defer { observation.cancel() }
        #expect(page?.entries.map(\.item.id) == [kept.id])
        let tombstone = try #require(try await db.writer.read { db in try Item.fetchOne(db, key: ["id": deleted.id]) })
        #expect(tombstone.deletedAt == deletedAt)
        #expect(tombstone.updatedAt == deletedAt)
        #expect(tombstone.isDirty)
        #expect(tombstone.text == "deleted")
    }

    @Test func `stores previews with their image record and reuses them for the same link`() async throws {
        let db = try makeDatabase()
        let link = URL(string: "https://x.com/a/status/1")!
        let image = PreviewImage(url: URL(string: "https://pbs.twimg.com/media/a.jpg")!, width: 1200, height: 716, isLarge: true, placeholder: Data([1, 2, 3]))
        let preview = LinkPreview(siteName: "X (formerly Twitter)", title: "A (@a) on X", summary: "Hello", image: image)
        let first = try db.insertItem(text: link.absoluteString, link: link)
        try await db.savePreview(preview, for: first.id)

        var page: FeedPage?
        let observation = db.observeFeed(from: nil) { page = $0 }
        defer { observation.cancel() }
        let entry = try #require(page?.entries.first)
        #expect(entry.preview == preview)
        #expect(entry.item.previewImageID == image.id)
        #expect(entry.item.previewFetchedAt != nil)
        #expect(entry.item.updatedAt == entry.item.createdAt) // a preview isn't a user edit

        #expect(try db.existingPreview(for: link) == .some(preview))
        #expect(try db.existingPreview(for: URL(string: "https://other.example")!) == nil)

        // A page with nothing to show is remembered as fetched, with no preview.
        let empty = try db.insertItem(text: "https://example.com", link: URL(string: "https://example.com"))
        try await db.savePreview(nil, for: empty.id)
        #expect(try db.existingPreview(for: URL(string: "https://example.com")!) == .some(nil))
    }

    @Test func `indexes cached files and cleans up least recently used first`() async throws {
        let db = try makeDatabase()
        defer { media.removeAll() }
        func cache(_ name: String, bytes: Int) async throws -> PreviewImage {
            let url = URL(string: "https://example.com/\(name).jpg")!
            try media.store(Data(repeating: 7, count: bytes), for: url)
            let image = PreviewImage(url: url, width: 100, height: 100)
            let item = try db.insertItem(text: url.absoluteString, link: url)
            try await db.savePreview(LinkPreview(title: name, image: image), for: item.id)
            return image
        }
        let old = try await cache("old", bytes: 64 * 1024)
        let recent = try await cache("recent", bytes: 64 * 1024)
        try await db.writer.write { db in
            try db.execute(sql: "UPDATE media SET lastUsedAt = ? WHERE id = ?", arguments: [Date(timeIntervalSinceNow: -86_400), old.id])
        }
        let total = try db.cachedMediaSize()
        #expect(total >= 128 * 1024)

        try db.trimCachedMedia(to: total - 1)
        #expect(media.fileSize(for: old.url) == nil)
        #expect(media.fileSize(for: recent.url) != nil)
        #expect(try db.cachedMediaSize() < total)

        // Removing files keeps the records, so previews keep their size and placeholder.
        try db.removeAllCachedMedia()
        #expect(try db.cachedMediaSize() == 0)
        #expect(media.fileSize(for: recent.url) == nil)
        let count = try await db.writer.read { try MediaRecord.fetchCount($0) }
        #expect(count == 2)
    }

    @Test func `records downloads and use reported by the loader`() async throws {
        let db = try makeDatabase()
        let url = URL(string: "https://example.com/photo.jpg")!
        let item = try db.insertItem(text: url.absoluteString, link: url)
        try await db.savePreview(LinkPreview(image: PreviewImage(url: url, width: 10, height: 10)), for: item.id)
        db.mediaStored(id: MediaStore.id(for: url), byteCount: 4096)
        // Reports are written asynchronously; a write after them sees them.
        let record = try await db.writer.write { try MediaRecord.fetchOne($0, key: MediaStore.id(for: url)) }
        #expect(record?.byteCount == 4096)
        #expect(record?.lastUsedAt != nil)
    }
}

struct DatabaseRecoveryTests {
    let location = DatabaseLocation(directory: FileManager.default.temporaryDirectory.appending(path: "db-recovery-\(UUID().uuidString)"))
    let media = MediaStore(directory: FileManager.default.temporaryDirectory.appending(path: "db-recovery-media-\(UUID().uuidString)"))

    @Test func `a damaged file fails to open, and moving it aside starts a new database`() throws {
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let garbage = Data("this is not a database".utf8)
        try garbage.write(to: location.file)

        #expect(throws: (any Error).self) { try AppDatabase.open(at: location, media: media) }

        let backup = try #require(try AppDatabase.moveAside(location, date: Date(timeIntervalSince1970: 1_790_000_000)))
        #expect(backup.lastPathComponent.hasPrefix("statemono-unreadable-"))
        #expect(try Data(contentsOf: backup) == garbage) // kept, not deleted
        #expect(!FileManager.default.fileExists(atPath: location.file.path))

        let fresh = try AppDatabase.open(at: location, media: media)
        #expect(try fresh.feedStart(newest: 50) == nil)
        try fresh.insertItem(text: "works again", link: nil)
    }

    @Test func `moving aside with no database does nothing`() throws {
        #expect(try AppDatabase.moveAside(location) == nil)
    }
}
