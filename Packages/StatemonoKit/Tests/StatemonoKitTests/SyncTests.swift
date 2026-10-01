import CloudKit
import Foundation
import Testing
@testable import StatemonoKit

/// Sync's rules (docs/sync-plan.md), without CloudKit's servers: what goes up, what comes down, and who wins.
@MainActor
struct SyncTests {
    let media = MediaStore(directory: FileManager.default.temporaryDirectory.appending(path: "sync-media-\(UUID().uuidString)"))
    let base = Date(timeIntervalSince1970: 1_000_000)
    let fields = Data([1, 2, 3])

    func makeDatabase() throws -> AppDatabase {
        try AppDatabase.inMemory(media: media)
    }

    func remote(_ item: SyncedItem) -> RemoteItem {
        RemoteItem(item: item, systemFields: fields)
    }

    @Test func `new items are dirty until the backend has them`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "https://example.com", link: URL(string: "https://example.com"), date: base)
        #expect(try await db.dirtyItemIDs() == [item.id])

        let toSync = try await db.itemsToSync([item.id])
        #expect(toSync[item.id]?.item.text == "https://example.com")
        #expect(toSync[item.id]?.systemFields == nil)

        let stillDirty = try await db.markSynced(item.id, updatedAt: item.updatedAt, systemFields: fields)
        #expect(stillDirty == false)
        #expect(try await db.dirtyItemIDs().isEmpty)
        #expect(try await db.itemsToSync([item.id])[item.id]?.systemFields == fields)
    }

    @Test func `an edit while the save was out keeps the item dirty`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "note", link: nil, date: base)
        // Deleted after the save went out with the original version.
        try db.deleteItem(item.id, date: base.addingTimeInterval(10))
        let stillDirty = try await db.markSynced(item.id, updatedAt: item.updatedAt, systemFields: fields)
        #expect(stillDirty)
        #expect(try await db.dirtyItemIDs() == [item.id])
    }

    @Test func `a new item from another device arrives clean, without a preview`() async throws {
        let db = try makeDatabase()
        let id = UUID()
        let incoming = SyncedItem(id: id, text: "https://swift.org", link: URL(string: "https://swift.org"), createdAt: base, updatedAt: base, deletedAt: nil)
        let results = try await db.applyRemote([remote(incoming)])
        #expect(results[id] == .applied)
        #expect(try await db.dirtyItemIDs().isEmpty)

        var page: FeedPage?
        let observation = db.observeFeed(from: nil) { page = $0 }
        defer { observation.cancel() }
        #expect(page?.entries.map(\.item.id) == [id])
        #expect(page?.entries.first?.item.previewFetchedAt == nil)
        // It's searchable like any other item.
        #expect(try await db.search("swift").items.map(\.id) == [id])
    }

    @Test func `the newer edit wins, by updatedAt`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "note", link: nil, date: base)
        try await db.markSynced(item.id, updatedAt: item.updatedAt, systemFields: fields)

        // Deleted on another device, later: the tombstone comes down and the item leaves the feed.
        var deleted = item.synced
        deleted.deletedAt = base.addingTimeInterval(5)
        deleted.updatedAt = base.addingTimeInterval(5)
        #expect(try await db.applyRemote([remote(deleted)])[item.id] == .applied)
        #expect(try db.oldestItemDate() == nil)
        #expect(try await db.dirtyItemIDs().isEmpty)

        // An older version arriving later loses, and what's here goes up again.
        #expect(try await db.applyRemote([remote(item.synced)])[item.id] == .keptLocal)
        #expect(try await db.dirtyItemIDs() == [item.id])

        // The same version again changes nothing.
        try await db.markSynced(item.id, updatedAt: deleted.updatedAt, systemFields: fields)
        #expect(try await db.applyRemote([remote(deleted)])[item.id] == .unchanged)
        #expect(try await db.dirtyItemIDs().isEmpty)
    }

    @Test func `a changed link drops the preview so it's fetched again`() async throws {
        let db = try makeDatabase()
        let item = try db.insertItem(text: "https://a.com", link: URL(string: "https://a.com"), date: base)
        try await db.savePreview(LinkPreview(siteName: "A", title: "A", summary: nil, image: nil), for: item.id)
        var edited = item.synced
        edited.text = "https://b.com"
        edited.link = URL(string: "https://b.com")
        edited.updatedAt = base.addingTimeInterval(1)
        try await db.applyRemote([remote(edited)])
        let entry = try await db.itemsToSync([item.id])[item.id]
        #expect(entry?.item.link == URL(string: "https://b.com"))
        #expect(try db.existingPreview(for: URL(string: "https://b.com")!) == nil)
    }

    @Test func `a reset forgets the backend and marks everything to go up again`() async throws {
        let db = try makeDatabase()
        let a = try db.insertItem(text: "a", link: nil, date: base)
        let b = try db.insertItem(text: "b", link: nil, date: base.addingTimeInterval(1))
        try await db.markSynced(a.id, updatedAt: a.updatedAt, systemFields: fields)
        try await db.markSynced(b.id, updatedAt: b.updatedAt, systemFields: fields)
        try await db.saveSyncState(Data([9]), backend: "test")

        #expect(try await db.hasSyncedItems())
        try await db.resetSync()
        #expect(try await db.hasSyncedItems() == false)
        #expect(Set(try await db.dirtyItemIDs()) == [a.id, b.id])
        #expect(try await db.itemsToSync([a.id])[a.id]?.systemFields == nil)
        // The engine's own state is kept: it follows the account itself.
        #expect(try await db.syncState("test") == Data([9]))

        // Re-uploading meets the server's copy of the same version: nothing left to send.
        #expect(try await db.applyRemote([remote(a.synced)])[a.id] == .unchanged)
        #expect(try await db.dirtyItemIDs() == [b.id])

        try await db.forgetSyncedRecords([a.id])
        #expect(Set(try await db.dirtyItemIDs()) == [a.id, b.id])
        try await db.saveSyncState(nil, backend: "test")
        #expect(try await db.syncState("test") == nil)
    }

    @Test func `records carry the text and link encrypted, and the dates`() throws {
        let item = SyncedItem(
            id: UUID(), text: "Read this https://swift.org", link: URL(string: "https://swift.org"),
            createdAt: base, updatedAt: base.addingTimeInterval(2), deletedAt: base.addingTimeInterval(2)
        )
        let record = CloudKitSync.record(for: item, systemFields: nil)
        #expect(record.recordType == "Item")
        #expect(record.recordID.zoneID.zoneName == "Items")
        #expect(record.recordID.recordName == item.id.uuidString)
        #expect(record.encryptedValues["text"] as? String == item.text)
        #expect(record["text"] == nil)
        #expect(CloudKitSync.syncedItem(from: record) == item)

        // The system fields come back as the same record, ready to save over.
        let restored = try #require(CloudKitSync.record(fromSystemFields: CloudKitSync.systemFields(of: record)))
        #expect(restored.recordID == record.recordID)
        let rebuilt = CloudKitSync.record(for: item, systemFields: CloudKitSync.systemFields(of: record))
        #expect(CloudKitSync.syncedItem(from: rebuilt) == item)
    }
}

/// The entitlements reader, on a minimal Mach-O file built here: a 64-bit header, one LC_CODE_SIGNATURE command, and a
/// code signature holding an entitlements plist. Checked by hand on real builds too (docs/sync-plan.md).
struct EntitlementsTests {
    let plist = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>aps-environment</key><string>production</string>
        <key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.com.statemono</string></array>
        </dict></plist>
        """.utf8)

    func machO(entitlements: Data?) -> Data {
        var data = Data()
        func le(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func be(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        let blob = entitlements.map { 8 + $0.count } ?? 0
        let signature = 12 + (entitlements == nil ? 0 : 8) + blob
        // mach_header_64: magic, cputype (arm64), cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved.
        [0xFEED_FACF, 0x0100_000C, 0, 2, 1, 16, 0, 0].forEach(le)
        // linkedit_data_command: LC_CODE_SIGNATURE, cmdsize, dataoff, datasize.
        [0x1D, 16, 48, UInt32(signature)].forEach(le)
        // SuperBlob: magic, length, count, then the entitlements slot (type 5) and its offset.
        be(0xFADE_0CC0); be(UInt32(signature)); be(entitlements == nil ? 0 : 1)
        if let entitlements {
            be(5); be(20)
            be(0xFADE_7171); be(UInt32(blob)); data.append(entitlements)
        }
        return data
    }

    @Test func `reads the entitlements from a code signature`() throws {
        #expect(Entitlements.entitlementsPlist(in: machO(entitlements: plist)) == plist)
        #expect(Entitlements.entitlementsPlist(in: machO(entitlements: nil)) == nil)
        #expect(Entitlements.entitlementsPlist(in: Data("not a binary".utf8)) == nil)
    }

    @Test func `searches each slice of a universal binary`() throws {
        let slice = machO(entitlements: plist)
        var fat = Data()
        func be(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { fat.append(contentsOf: $0) } }
        // fat_header, then one fat_arch: cputype, cpusubtype, offset, size, align.
        be(0xCAFE_BABE); be(1)
        be(0x0100_000C); be(0); be(64); be(UInt32(slice.count)); be(6)
        fat.append(Data(count: 64 - fat.count))
        fat.append(slice)
        #expect(Entitlements.entitlementsPlist(in: fat) == plist)
    }

    @Test func `parses containers and push`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "entitlements-\(UUID().uuidString)")
        try machO(entitlements: plist).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try #require(Entitlements.read(url))
        #expect(read.containers == ["iCloud.com.statemono"])
        #expect(read.push)
    }
}
