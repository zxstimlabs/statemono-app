import Foundation
import GRDB
import Synchronization

/// The app's SQLite database (GRDB), the source of truth for the feed. It follows Telegram's model:
/// - `item`: messages, with their link preview's text and the id of its image (Postbox's message table).
/// - `media`: one row per image, with its size, placeholder, and cached file's size and last use. It indexes the files
///   in `MediaStore` and drives cleanup (Telegram's StorageBox).
/// - `itemSearch`: an FTS5 index over item text and preview text, with the đ → d fix.
public final class AppDatabase: Sendable {
    let writer: any DatabaseWriter
    let media: MediaStore

    public init(_ writer: any DatabaseWriter, media: MediaStore) throws {
        self.writer = writer
        self.media = media
        try Self.migrator.migrate(writer)
    }

    /// Opens (or creates) the database and brings its schema up to date. Throws if the file can't be read, for example
    /// when it's damaged, so the app can say so and offer `moveAside(_:)`.
    public static func open(at location: DatabaseLocation = .default, media: MediaStore = .shared) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: location.file.path, configuration: configuration)
        return try AppDatabase(pool, media: media)
    }

    /// Renames the database's files (including its WAL and shared-memory files) to
    /// "statemono-unreadable-<date>.sqlite", so `open(at:)` starts a new, empty database. Nothing is deleted: the old
    /// file can still be recovered. Returns the renamed database file, or nil if there was none.
    @discardableResult
    public static func moveAside(_ location: DatabaseLocation = .default, date: Date = .now) throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: location.file.path) else { return nil }
        // Local time, as the user would read it in Finder.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let backup = location.directory.appending(path: "statemono-unreadable-\(formatter.string(from: date)).sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: location.file.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: URL(fileURLWithPath: backup.path + suffix))
        }
        return backup
    }

    /// An empty database in memory, for tests and previews.
    public static func inMemory(media: MediaStore) throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration), media: media)
    }

    /// Every connection registers the search tokenizer; see `StatemonoTokenizer`.
    static var configuration: Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            db.add(tokenizer: StatemonoTokenizer.self)
        }
        return configuration
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "media") { t in
                t.primaryKey("id", .text)
                t.column("url", .text).notNull()
                t.column("width", .integer).notNull()
                t.column("height", .integer).notNull()
                t.column("placeholder", .blob)
                t.column("byteCount", .integer)
                t.column("lastUsedAt", .datetime)
            }
            try db.create(table: "item") { t in
                // An explicit INTEGER PRIMARY KEY: VACUUM can renumber implicit rowids and break the FTS index.
                t.autoIncrementedPrimaryKey("rowid")
                t.column("id", .blob).notNull().unique()
                t.column("text", .text).notNull()
                t.column("link", .text).indexed()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("isDirty", .boolean).notNull()
                t.column("previewSiteName", .text)
                t.column("previewTitle", .text)
                t.column("previewSummary", .text)
                t.column("previewImageID", .text).references("media", onDelete: .setNull)
                t.column("previewImageIsLarge", .boolean).notNull()
                t.column("previewFetchedAt", .datetime)
            }
            try db.create(virtualTable: "itemSearch", using: FTS5()) { t in
                t.synchronize(withTable: "item")
                t.tokenizer = StatemonoTokenizer.tokenizerDescriptor()
                t.column("text")
                t.column("previewSiteName")
                t.column("previewTitle")
                t.column("previewSummary")
            }
        }
        return migrator
    }

    // MARK: - Feed

    // The feed shows a window of history anchored at its oldest message, like Telegram's history view: everything from
    // `start` on. New messages extend it at the bottom, and nothing drops off the top, so what's on screen never shifts
    // under the reader. Loading older messages moves `start` back. A nil start means all of history.

    /// Delivers the items from `start` on, oldest first, now and again whenever they change. The first page arrives
    /// before this returns. Keep the returned object to keep it going.
    @MainActor
    public func observeFeed(from start: Date?, onChange: @escaping @MainActor (FeedPage) -> Void) -> FeedObservation {
        let cancellable = ValueObservation
            .tracking { db in try Self.feed(db, from: start) }
            .start(in: writer, scheduling: .immediate, onError: { _ in }, onChange: onChange)
        return FeedObservation(cancellable)
    }

    static func feed(_ db: Database, from start: Date?) throws -> FeedPage {
        let live = Item.filter(Item.Columns.deletedAt == nil)
        let window = start.map { live.filter(Item.Columns.createdAt >= $0) } ?? live
        let entries = try window
            .order(Item.Columns.createdAt)
            .including(optional: Item.previewImage)
            .asRequest(of: FeedEntry.self)
            .fetchAll(db)
        let hasOlder = try start.map { try live.filter(Item.Columns.createdAt < $0).isEmpty(db) == false } ?? false
        return FeedPage(entries: entries, hasOlder: hasOlder)
    }

    /// Where a window showing the newest `count` items starts, or nil if there are no more than that.
    public func feedStart(newest count: Int) throws -> Date? {
        try writer.read { db in try Self.start(of: Item.filter(Item.Columns.deletedAt == nil), keeping: count, db) }
    }

    /// Moves a window's start back by `count` older items, or to nil once fewer than that remain.
    public func feedStart(before start: Date, adding count: Int) throws -> Date? {
        try writer.read { db in
            try Self.start(of: Item.filter(Item.Columns.deletedAt == nil && Item.Columns.createdAt < start), keeping: count, db)
        }
    }

    public func createdAt(of id: UUID) throws -> Date? {
        try writer.read { db in try Item.filter(Item.Columns.id == id).fetchOne(db)?.createdAt }
    }

    /// The creation date of the `count`-th newest item in `items`, or nil if there are no more than `count`.
    private static func start(of items: QueryInterfaceRequest<Item>, keeping count: Int, _ db: Database) throws -> Date? {
        guard try items.fetchCount(db) > count else { return nil }
        return try items.order(Item.Columns.createdAt.desc).limit(1, offset: count - 1).fetchOne(db)?.createdAt
    }

    /// The first item on or after `date`, for jumping to a day.
    public func firstItem(onOrAfter date: Date) throws -> UUID? {
        try writer.read { db in
            try Item
                .filter(Item.Columns.deletedAt == nil && Item.Columns.createdAt >= date)
                .order(Item.Columns.createdAt)
                .fetchOne(db)?.id
        }
    }

    public func oldestItemDate() throws -> Date? {
        try writer.read { db in
            try Item.filter(Item.Columns.deletedAt == nil).select(min(Item.Columns.createdAt), as: Date.self).fetchOne(db)
        }
    }

    // MARK: - Writes

    @discardableResult
    public func insertItem(text: String, link: URL?, date: Date = .now) throws -> Item {
        try writer.write { db in
            var item = Item(text: text, link: link, date: date)
            try item.insert(db)
            return item
        }
    }

    /// Stores a fetched preview on an item, and its image's record. A nil preview records that the page had nothing to
    /// show, so it isn't fetched again at every launch.
    public func savePreview(_ preview: LinkPreview?, for itemID: UUID) async throws {
        let storedBytes = preview?.image.flatMap { media.fileSize(for: $0.url) }
        try await writer.write { db in
            if let image = preview?.image {
                var record = try MediaRecord.fetchOne(db, key: image.id)
                    ?? MediaRecord(id: image.id, url: image.url, width: image.width, height: image.height)
                record.url = image.url
                record.width = image.width
                record.height = image.height
                record.placeholder = image.placeholder
                if let storedBytes {
                    record.byteCount = storedBytes
                    record.lastUsedAt = record.lastUsedAt ?? .now
                }
                try record.save(db)
            }
            try Item.filter(Item.Columns.id == itemID).updateAll(db, [
                Column("previewSiteName").set(to: preview?.siteName),
                Column("previewTitle").set(to: preview?.title),
                Column("previewSummary").set(to: preview?.summary),
                Column("previewImageID").set(to: preview?.image?.id),
                Column("previewImageIsLarge").set(to: preview?.image?.isLarge ?? false),
                Item.Columns.previewFetchedAt.set(to: Date.now),
            ])
        }
    }

    /// The preview already fetched for `link`, if any item has one, so the same link isn't fetched twice.
    public func existingPreview(for link: URL) throws -> LinkPreview?? {
        try writer.read { db in
            let entry = try Item
                .filter(Item.Columns.link == link && Item.Columns.previewFetchedAt != nil)
                .order(Item.Columns.previewFetchedAt.desc)
                .including(optional: Item.previewImage)
                .asRequest(of: FeedEntry.self)
                .fetchOne(db)
            return entry.map { $0.preview }
        }
    }

    // MARK: - Search

    /// Items where every word of `query` starts a word in the text or preview, oldest first. "duong" finds "đường",
    /// and "grd" finds "GRDB".
    public func search(_ query: String) async throws -> [UUID] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
        return try await writer.read { db in
            try UUID.fetchAll(db, sql: """
                SELECT item.id FROM item
                JOIN itemSearch ON itemSearch.rowid = item.rowid
                WHERE itemSearch MATCH ? AND item.deletedAt IS NULL
                ORDER BY item.createdAt
                """, arguments: [pattern])
        }
    }
}

/// Where the database lives. The default is Application Support/<bundle id>/statemono.sqlite, next to the media files.
/// It moves into the App Group container with the share extension (plan step 4), which also needs GRDB's "Sharing a
/// Database" setup.
public struct DatabaseLocation: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var `default`: DatabaseLocation {
        DatabaseLocation(directory: URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "Statemono"))
    }

    public var file: URL {
        directory.appending(path: "statemono.sqlite")
    }
}

/// Keeps a feed observation running until it's cancelled or released.
@MainActor
public final class FeedObservation {
    private let cancellable: AnyDatabaseCancellable

    init(_ cancellable: AnyDatabaseCancellable) {
        self.cancellable = cancellable
    }

    public func cancel() {
        cancellable.cancel()
    }
}

// MARK: - Cached media

/// Tells the database what happens to cached files, so `media` stays an accurate index of the disk.
public protocol MediaIndex: Sendable {
    func mediaStored(id: String, byteCount: Int)
    func mediaUsed(id: String)
}

extension AppDatabase: MediaIndex {
    public func mediaStored(id: String, byteCount: Int) {
        writer.asyncWriteWithoutTransaction { db in
            _ = try? MediaRecord.filter(key: id).updateAll(db, [
                MediaRecord.Columns.byteCount.set(to: byteCount),
                MediaRecord.Columns.lastUsedAt.set(to: Date.now),
            ])
        }
    }

    public func mediaUsed(id: String) {
        writer.asyncWriteWithoutTransaction { db in
            _ = try? MediaRecord.filter(key: id).updateAll(db, MediaRecord.Columns.lastUsedAt.set(to: Date.now))
        }
    }

    // Cleanup, for a storage screen. Removing a file keeps its record, so previews keep their size and placeholder,
    // and the image downloads again the next time it's shown.

    /// Bytes of cached images on disk.
    public func cachedMediaSize() throws -> Int64 {
        try writer.read { db in
            try MediaRecord.select(sum(MediaRecord.Columns.byteCount), as: Int64.self).fetchOne(db) ?? 0
        }
    }

    public func removeAllCachedMedia() throws {
        media.removeAll()
        try writer.write { db in
            try MediaRecord.updateAll(db, MediaRecord.Columns.byteCount.set(to: nil))
            try Self.deleteUnreferencedMedia(db)
        }
    }

    /// Removes the least recently used images until the rest fit in `bytes`.
    public func trimCachedMedia(to bytes: Int64) throws {
        try writer.write { db in
            var total = try MediaRecord.select(sum(MediaRecord.Columns.byteCount), as: Int64.self).fetchOne(db) ?? 0
            let cached = try MediaRecord
                .filter(MediaRecord.Columns.byteCount != nil)
                .order(MediaRecord.Columns.lastUsedAt)
                .fetchAll(db)
            for var record in cached where total > bytes {
                media.remove(id: record.id)
                total -= Int64(record.byteCount ?? 0)
                record.byteCount = nil
                try record.update(db)
            }
            try Self.deleteUnreferencedMedia(db)
        }
    }

    /// Removes images that haven't been shown since `date`.
    public func removeCachedMedia(unusedSince date: Date) throws {
        try writer.write { db in
            let stale = try MediaRecord
                .filter(MediaRecord.Columns.byteCount != nil && (MediaRecord.Columns.lastUsedAt == nil || MediaRecord.Columns.lastUsedAt < date))
                .fetchAll(db)
            for var record in stale {
                media.remove(id: record.id)
                record.byteCount = nil
                try record.update(db)
            }
            try Self.deleteUnreferencedMedia(db)
        }
    }

    /// Records no item points at any more, such as an image replaced by a reload.
    private static func deleteUnreferencedMedia(_ db: Database) throws {
        try db.execute(sql: """
            DELETE FROM media WHERE byteCount IS NULL
            AND id NOT IN (SELECT previewImageID FROM item WHERE previewImageID IS NOT NULL)
            """)
    }
}
