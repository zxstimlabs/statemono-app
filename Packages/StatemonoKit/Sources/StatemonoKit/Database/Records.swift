import Foundation
import GRDB

/// A saved message: its text, usually a link, and that link's preview. It follows Telegram's model: the message
/// carries its webpage preview's text, and refers to the preview's image by id (a `MediaRecord`).
public struct Item: Codable, Hashable, Sendable, Identifiable {
    /// Local integer key and the search index's rowid. It never leaves the device; `id` is what syncs.
    public var rowid: Int64?
    public var id: UUID
    public var text: String
    public var link: URL?
    public var createdAt: Date
    /// Changes only when the user edits the item, for last-write-wins sync. Fetching a preview doesn't touch it.
    public var updatedAt: Date
    /// Deleted items stay as tombstones.
    public var deletedAt: Date?
    /// Has changes the sync backend hasn't received yet.
    public var isDirty: Bool
    public var previewSiteName: String?
    public var previewTitle: String?
    public var previewSummary: String?
    public var previewImageID: String?
    public var previewImageIsLarge: Bool
    /// When the preview was last fetched, or nil if it hasn't been. A fetch that finds nothing still sets it.
    public var previewFetchedAt: Date?

    init(text: String, link: URL?, date: Date) {
        id = UUID()
        self.text = text
        self.link = link
        createdAt = date
        updatedAt = date
        isDirty = true
        previewImageIsLarge = false
    }
}

extension Item: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "item"
    static let previewImage = belongsTo(MediaRecord.self, key: "previewImage", using: ForeignKey(["previewImageID"]))

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        rowid = inserted.rowID
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let link = Column(CodingKeys.link)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let deletedAt = Column(CodingKeys.deletedAt)
        public static let previewFetchedAt = Column(CodingKeys.previewFetchedAt)
    }
}

/// One image, like Telegram's image media plus its StorageBox entry: where it comes from, its size, the tiny
/// placeholder shown before it loads, and how much disk its cached file takes. The file itself is in `MediaStore`,
/// named by `id`.
public struct MediaRecord: Codable, Hashable, Sendable, Identifiable {
    /// "http-" plus a hash of `url`. Also the file name in `MediaStore`.
    public var id: String
    public var url: URL
    public var width: Int
    public var height: Int
    public var placeholder: Data?
    /// Bytes on disk, or nil when the file isn't there.
    public var byteCount: Int?
    public var lastUsedAt: Date?
}

extension MediaRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "media"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let byteCount = Column(CodingKeys.byteCount)
        public static let lastUsedAt = Column(CodingKeys.lastUsedAt)
    }
}

/// An item with its preview image, as the feed shows it.
public struct FeedEntry: Decodable, FetchableRecord, Hashable, Sendable {
    public var item: Item
    public var previewImage: MediaRecord?

    /// Nil until a preview has been fetched, and when the fetch found nothing to show.
    public var preview: LinkPreview? {
        let image = previewImage.map {
            PreviewImage(url: $0.url, width: $0.width, height: $0.height, isLarge: item.previewImageIsLarge, placeholder: $0.placeholder)
        }
        guard item.previewSiteName != nil || item.previewTitle != nil || item.previewSummary != nil || image != nil else { return nil }
        return LinkPreview(siteName: item.previewSiteName, title: item.previewTitle, summary: item.previewSummary, image: image)
    }
}

/// The newest items, oldest first, and whether older ones exist.
public struct FeedPage: Hashable, Sendable {
    public var entries: [FeedEntry]
    public var hasOlder: Bool
}
