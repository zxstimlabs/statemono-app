import Foundation
import GRDB

/// A link waiting for Apple Intelligence's tags, with the text the model reads.
public struct TagWork: Sendable, Equatable {
    public let id: UUID
    public let text: String
}

/// How many live links have been tried, out of those that can be.
public struct TagProgress: Equatable, Sendable {
    public let tagged: Int
    public let total: Int
}

/// One link's tags, as its Tags sheet shows them.
public struct ItemTags: Equatable, Sendable {
    public let tags: [String]
    /// When the model was last asked, or nil if it hasn't been yet.
    public let attemptedAt: Date?
}

// Apple Intelligence's tags (docs/search-plan.md, Phase 4), stored on `item` and indexed with it, so keyword search
// matches them. Like previews and vectors, they're made on each device: saving them doesn't touch `updatedAt` or
// `isDirty`, and sync doesn't carry them.
extension AppDatabase {
    /// Live links waiting for tags, newest first, at most `limit`: never tried, or, during Re-tag All, last tried before
    /// `retagSince`. A link waits for its preview, so its tags take it into account. The progress counts every link
    /// that can be tagged.
    public func tagWork(retagSince: Date?, limit: Int) async throws -> (work: [TagWork], progress: TagProgress) {
        try await writer.read { db in
            let eligible = "item.deletedAt IS NULL AND (item.link IS NULL OR item.previewFetchedAt IS NOT NULL)"
            let waiting = retagSince == nil ? "item.tagsAttemptedAt IS NULL" : "(item.tagsAttemptedAt IS NULL OR item.tagsAttemptedAt < :since)"
            let arguments: StatementArguments = ["since": retagSince, "limit": limit]
            let total = try Int.fetchOne(db, sql: "SELECT count(*) FROM item WHERE \(eligible)") ?? 0
            let pending = try Int.fetchOne(db, sql: "SELECT count(*) FROM item WHERE \(eligible) AND \(waiting)", arguments: arguments) ?? 0
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, text, previewTitle, previewSiteName, previewSummary FROM item
                WHERE \(eligible) AND \(waiting)
                ORDER BY createdAt DESC LIMIT :limit
                """, arguments: arguments)
            let work = rows.map { row in
                TagWork(id: row[0], text: Self.vectorText(title: row[2], siteName: row[3], summary: row[4], text: row[1]))
            }
            return (work, TagProgress(tagged: total - pending, total: total))
        }
    }

    /// The text the model reads for one link, for re-tagging it on request. Nil if it's gone or deleted.
    public func tagWork(for id: UUID) async throws -> TagWork? {
        try await writer.read { db in
            guard let item = try Item.filter(Item.Columns.id == id && Item.Columns.deletedAt == nil).fetchOne(db) else { return nil }
            let text = Self.vectorText(title: item.previewTitle, siteName: item.previewSiteName, summary: item.previewSummary, text: item.text)
            return TagWork(id: id, text: text)
        }
    }

    /// Records a try. Tags replace the old ones; nil (the model refused, or failed) keeps the old ones, so search never
    /// loses them, and only marks the link tried, so it isn't asked again in a loop.
    public func saveTags(_ tags: [String]?, for id: UUID, osVersion: String) async throws {
        try await writer.write { db in
            var assignments = [Item.Columns.tagsAttemptedAt.set(to: Date.now)]
            if let tags {
                assignments.append(Item.Columns.tags.set(to: tags.joined(separator: "\n")))
                assignments.append(Item.Columns.tagsOSVersion.set(to: osVersion))
            }
            try Item.filter(Item.Columns.id == id).updateAll(db, assignments)
        }
    }

    public func tags(for id: UUID) async throws -> ItemTags? {
        try await writer.read { db in
            guard let item = try Item.filter(Item.Columns.id == id).fetchOne(db) else { return nil }
            let tags = item.tags?.split(separator: "\n").map(String.init) ?? []
            return ItemTags(tags: tags, attemptedAt: item.tagsAttemptedAt)
        }
    }

    /// Deletes every tag and every try, for turning tags off. Turning them back on starts over.
    public func removeAllTags() async throws {
        try await writer.write { db in
            try Item.updateAll(db, [
                Item.Columns.tags.set(to: nil),
                Item.Columns.tagsAttemptedAt.set(to: nil),
                Item.Columns.tagsOSVersion.set(to: nil),
            ])
        }
    }

    /// Bytes the tags take.
    public func tagStorageSize() async throws -> Int64 {
        try await writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT CAST(total(length(tags) + length(tagsOSVersion)) AS INTEGER) FROM item") ?? 0
        }
    }
}
