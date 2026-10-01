import Foundation
import GRDB

/// An item as it syncs: what the user made. Link previews, their images and Smart Search's vectors are left out, since
/// each device makes its own (docs/sync-plan.md).
public struct SyncedItem: Sendable, Hashable {
    public var id: UUID
    public var text: String
    public var link: URL?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, text: String, link: URL?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id
        self.text = text
        self.link = link
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// An item from another device, with the backend's metadata for its record.
public struct RemoteItem: Sendable {
    public var item: SyncedItem
    public var systemFields: Data

    public init(item: SyncedItem, systemFields: Data) {
        self.item = item
        self.systemFields = systemFields
    }
}

/// What applying an item from another device did here.
public enum RemoteChangeResult: Sendable, Equatable {
    /// It was new here, or newer than what was here, and replaced it.
    case applied
    /// What's here is newer, so it stays, marked to go up again.
    case keptLocal
    /// Both sides have the same version.
    case unchanged
}

/// Sync's side of the database: what to upload, and the rules for what comes down. Last write wins by `updatedAt`, as
/// the design principles say. Applying a change from elsewhere doesn't make an item dirty, and `updatedAt` only ever
/// carries a user's edit, made here or on another device.
extension AppDatabase {
    /// Every item with changes the sync backend hasn't received yet.
    public func dirtyItemIDs() async throws -> [UUID] {
        try await writer.read { db in
            try UUID.fetchAll(db, Item.select(Item.Columns.id).filter(Item.Columns.isDirty))
        }
    }

    /// Keeps reporting the dirty items: new messages, deletes, and the share extension's rows once the app sees them.
    @MainActor
    public func observeDirtyItems(onChange: @escaping @MainActor ([UUID]) -> Void) -> FeedObservation {
        let cancellable = ValueObservation
            .tracking { db in try UUID.fetchAll(db, Item.select(Item.Columns.id).filter(Item.Columns.isDirty)) }
            .removeDuplicates()
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { ids in
                MainActor.assumeIsolated { onChange(ids) }
            })
        return FeedObservation(cancellable)
    }

    /// The items to upload, each with the backend's metadata from its last save, if there was one.
    public func itemsToSync(_ ids: [UUID]) async throws -> [UUID: (item: SyncedItem, systemFields: Data?)] {
        try await writer.read { db in
            var result: [UUID: (item: SyncedItem, systemFields: Data?)] = [:]
            for item in try Item.filter(ids.contains(Item.Columns.id)).fetchAll(db) {
                let fields = try Data.fetchOne(db, sql: "SELECT systemFields FROM itemSync WHERE itemRowID = ?", arguments: [item.rowid])
                result[item.id] = (item.synced, fields)
            }
            return result
        }
    }

    /// Records that the backend saved the item as it was at `updatedAt`, with its metadata. The item stays dirty if it
    /// changed again while the save was out; returns whether it's still dirty, so it can be sent again.
    @discardableResult
    public func markSynced(_ id: UUID, updatedAt: Date, systemFields: Data) async throws -> Bool {
        try await writer.write { db in
            guard let item = try Item.filter(Item.Columns.id == id).fetchOne(db), let rowid = item.rowid else { return false }
            try Self.saveSystemFields(systemFields, rowid: rowid, db)
            guard Self.isSameInstant(item.updatedAt, updatedAt) else { return item.isDirty }
            try Item.filter(Item.Columns.id == id).updateAll(db, Item.Columns.isDirty.set(to: false))
            return false
        }
    }

    /// Applies items from another device, by last write wins on `updatedAt`, in one transaction. A new item gets a new
    /// local rowid and no preview yet, so the feed fetches one here. An item whose link changed loses its preview too.
    public func applyRemote(_ changes: [RemoteItem]) async throws -> [UUID: RemoteChangeResult] {
        try await writer.write { db in
            var results: [UUID: RemoteChangeResult] = [:]
            for change in changes {
                let remote = change.item
                guard var local = try Item.filter(Item.Columns.id == remote.id).fetchOne(db) else {
                    var item = Item(synced: remote)
                    try item.insert(db)
                    if let rowid = item.rowid { try Self.saveSystemFields(change.systemFields, rowid: rowid, db) }
                    results[remote.id] = .applied
                    continue
                }
                guard let rowid = local.rowid else { continue }
                // The record's metadata is the server's latest either way, so the next upload builds on it.
                try Self.saveSystemFields(change.systemFields, rowid: rowid, db)
                if Self.isSameInstant(local.updatedAt, remote.updatedAt) {
                    // The server has this very version, so nothing is left to send, as after re-uploading everything.
                    if local.isDirty {
                        try Item.filter(Item.Columns.id == remote.id).updateAll(db, Item.Columns.isDirty.set(to: false))
                    }
                    results[remote.id] = .unchanged
                } else if remote.updatedAt > local.updatedAt {
                    if local.link != remote.link {
                        local.previewSiteName = nil
                        local.previewTitle = nil
                        local.previewSummary = nil
                        local.previewImageID = nil
                        local.previewImageIsLarge = false
                        local.previewFetchedAt = nil
                    }
                    local.text = remote.text
                    local.link = remote.link
                    local.createdAt = remote.createdAt
                    local.updatedAt = remote.updatedAt
                    local.deletedAt = remote.deletedAt
                    local.isDirty = false
                    try local.update(db)
                    results[remote.id] = .applied
                } else {
                    if !local.isDirty {
                        try Item.filter(Item.Columns.id == remote.id).updateAll(db, Item.Columns.isDirty.set(to: true))
                    }
                    results[remote.id] = .keptLocal
                }
            }
            return results
        }
    }

    /// Forgets the backend's metadata for these items, whose records it no longer has, and marks them to go up again.
    public func forgetSyncedRecords(_ ids: [UUID]) async throws {
        try await writer.write { db in
            let items = Item.filter(ids.contains(Item.Columns.id))
            let rowids = try Int64.fetchAll(db, items.select(Column("rowid")))
            try Table("itemSync").filter(rowids.contains(Column("itemRowID"))).deleteAll(db)
            try items.updateAll(db, Item.Columns.isDirty.set(to: true))
        }
    }

    /// Forgets everything the backend had and marks every item to go up again: after a sign-in, a switch to another
    /// account, a sign-out, or a reset of the data in iCloud. Nothing on the device is deleted.
    public func resetSync() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM itemSync")
            try Item.updateAll(db, Item.Columns.isDirty.set(to: true))
        }
    }

    /// Whether this device has synced anything through the backend: whether it holds metadata for any item.
    public func hasSyncedItems() async throws -> Bool {
        try await writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM itemSync)") ?? false
        }
    }

    /// The backend's saved state, or nil before its first run.
    public func syncState(_ backend: String) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM syncState WHERE backend = ?", arguments: [backend])
        }
    }

    /// Saves the backend's state; nil forgets it, so the next run starts afresh.
    public func saveSyncState(_ data: Data?, backend: String) async throws {
        try await writer.write { db in
            if let data {
                try db.execute(sql: "INSERT OR REPLACE INTO syncState (backend, data) VALUES (?, ?)", arguments: [backend, data])
            } else {
                try db.execute(sql: "DELETE FROM syncState WHERE backend = ?", arguments: [backend])
            }
        }
    }

    private static func saveSystemFields(_ data: Data, rowid: Int64, _ db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO itemSync (itemRowID, systemFields) VALUES (?, ?)", arguments: [rowid, data])
    }

    /// The database keeps dates to the millisecond, so a date that went to the server and back can differ below that.
    static func isSameInstant(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 0.001
    }
}

extension Item {
    /// A new item from another device: clean, with no preview yet.
    init(synced: SyncedItem) {
        self.init(text: synced.text, link: synced.link, date: synced.createdAt)
        id = synced.id
        updatedAt = synced.updatedAt
        deletedAt = synced.deletedAt
        isDirty = false
    }

    var synced: SyncedItem {
        SyncedItem(id: id, text: text, link: link, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
