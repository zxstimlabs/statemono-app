import CloudKit
import Foundation
import os
import Synchronization

/// Syncs items through the user's private iCloud database with Apple's `CKSyncEngine` (docs/sync-plan.md). The engine
/// schedules the work, listens for pushes, retries what fails for a while, and watches the account. This decides what
/// a change means, using `AppDatabase+Sync`'s rules.
///
/// - One record per item, type `Item`, named by the item's UUID, in one custom zone, `Items`.
/// - The text and link are end-to-end encrypted (`encryptedValues`). The dates aren't, so CloudKit can show them.
/// - Deletes travel as `deletedAt`. Records are never deleted, so tombstones mean the same everywhere.
/// - Nothing on the device is ever deleted, whatever happens to the account or the data in iCloud.
public final class CloudKitSync: SyncBackend, CKSyncEngineDelegate {
    public static let recordType: CKRecord.RecordType = "Item"
    public static let zoneID = CKRecordZone.ID(zoneName: "Items")
    /// The key of this backend's row in `syncState`.
    static let backend = "cloudkit"

    private let database: AppDatabase
    private let container: CKContainer
    private let onEvent: @Sendable (SyncEvent) -> Void
    private let engine = Mutex<CKSyncEngine?>(nil)
    private let logger = Logger(subsystem: "com.statemono", category: "sync")

    /// Nil if the app isn't entitled to the container (see `canUse(containerIdentifier:)`). `onEvent` is called on the
    /// engine's queue, not the main thread.
    public init?(containerIdentifier: String, database: AppDatabase, onEvent: @escaping @Sendable (SyncEvent) -> Void) {
        guard Self.canUse(containerIdentifier: containerIdentifier) else { return nil }
        self.database = database
        container = CKContainer(identifier: containerIdentifier)
        self.onEvent = onEvent
    }

    /// Whether the app is signed to use the container, and to receive the pushes `CKSyncEngine` needs. CloudKit traps,
    /// crashing the app, on a container it isn't entitled to, so nothing touches CloudKit until this says yes.
    public static func canUse(containerIdentifier: String) -> Bool {
        let entitled = Entitlements.iCloudContainers.contains(containerIdentifier) && Entitlements.hasPushEnvironment
        if !entitled {
            Logger(subsystem: "com.statemono", category: "sync")
                .error("Not entitled to \(containerIdentifier, privacy: .public) or to push; iCloud sync stays off.")
        }
        return entitled
    }

    /// Whether this device can sync with the container now, in the words of `CKAccountStatus`, or nil if the app isn't
    /// entitled to it.
    public static func accountStatus(containerIdentifier: String) async -> CKAccountStatus? {
        guard canUse(containerIdentifier: containerIdentifier) else { return nil }
        return (try? await CKContainer(identifier: containerIdentifier).accountStatus()) ?? .couldNotDetermine
    }

    /// Starts the engine from its saved state, and queues every item not uploaded yet. The engine stays idle until
    /// there's an account, then starts on its own.
    public func start() async {
        let saved = try? await database.syncState(Self.backend)
        let serialization = saved.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: serialization,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine.withLock { $0 = engine }
        if serialization == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
        await queueDirtyItems(on: engine)
    }

    /// Stops syncing. What's waiting to upload stays dirty in the database, and goes up after the next start.
    public func stop() async {
        let engine = engine.withLock { engine in
            defer { engine = nil }
            return engine
        }
        await engine?.cancelOperations()
    }

    /// Queues items that changed here.
    public func itemsChanged(_ ids: [UUID]) {
        guard let engine = engine.withLock({ $0 }) else { return }
        queue(ids, on: engine)
    }

    /// Asks for other devices' changes now, such as when the app comes to the front. Pushes don't always arrive.
    public func fetchChanges() async {
        guard let engine = engine.withLock({ $0 }) else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            logger.info("Fetch failed: \(error, privacy: .public)")
        }
    }

    // MARK: - CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        logger.debug("\(String(describing: event), privacy: .private)")
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                try? await database.saveSyncState(data, backend: Self.backend)
            }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn, .switchAccounts:
                // Everything here goes up to this account, merging with what's there.
                await reuploadEverything(on: syncEngine)
            case .signOut:
                // Everything stays here. What iCloud had is forgotten, so whichever account comes next gets it all.
                try? await database.resetSync()
            @unknown default:
                break
            }
            onEvent(.accountChanged)

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == Self.zoneID {
                if deletion.reason == .purged, (try? await database.hasSyncedItems()) == true {
                    // The user deleted Statemono's data in iCloud's settings. Keep everything here, and stop until
                    // they turn syncing on again.
                    try? await database.resetSync()
                    onEvent(.dataDeletedRemotely)
                } else {
                    // Gone some other way: the user reset their end-to-end encrypted data, or it was deleted before
                    // this device ever synced (a first fetch hears about old deletions too). Make it again and upload
                    // everything here.
                    await reuploadEverything(on: syncEngine)
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            await apply(changes, on: syncEngine)

        case .sentRecordZoneChanges(let sent):
            await handleSent(sent, on: syncEngine)

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                logger.error("Couldn't save zone \(failure.zone.zoneID.zoneName): \(failure.error)")
            }

        case .willFetchChanges:
            onEvent(.fetching)
        case .willSendChanges:
            onEvent(.sending)
        case .didFetchChanges, .didSendChanges:
            onEvent(.finished)
        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // A request holds at most 400 records, and the batch stops sooner if they're large. The rest stay pending.
        let changes = Array(syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }.prefix(400))
        guard !changes.isEmpty else { return nil }
        let ids = changes.compactMap { change -> UUID? in
            guard case .saveRecord(let recordID) = change else { return nil }
            return UUID(uuidString: recordID.recordName)
        }
        let items = (try? await database.itemsToSync(ids)) ?? [:]
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let id = UUID(uuidString: recordID.recordName), let entry = items[id] else {
                // Nothing to send for it: drop it, or it would wait forever.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return Self.record(for: entry.item, systemFields: entry.systemFields)
        }
    }

    // MARK: - Private

    private func apply(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges, on engine: CKSyncEngine) async {
        let incoming = changes.modifications.compactMap { modification -> RemoteItem? in
            guard let item = Self.syncedItem(from: modification.record) else { return nil }
            return RemoteItem(item: item, systemFields: Self.systemFields(of: modification.record))
        }
        if !incoming.isEmpty {
            do {
                let results = try await database.applyRemote(incoming)
                queue(results.filter { $0.value == .keptLocal }.map(\.key), on: engine)
            } catch {
                logger.error("Couldn't apply \(incoming.count) fetched items: \(error)")
            }
        }
        // Records are never deleted, since deletes are tombstones. One deleted some other way goes up again from here.
        let deleted = changes.deletions.filter { $0.recordType == Self.recordType }.compactMap { UUID(uuidString: $0.recordID.recordName) }
        if !deleted.isEmpty {
            try? await database.forgetSyncedRecords(deleted)
            queue(deleted, on: engine)
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, on engine: CKSyncEngine) async {
        var resend: [UUID] = []
        for record in sent.savedRecords {
            guard let item = Self.syncedItem(from: record) else { continue }
            // Still dirty if it changed while the save was out.
            if (try? await database.markSynced(item.id, updatedAt: item.updatedAt, systemFields: Self.systemFields(of: record))) == true {
                resend.append(item.id)
            }
        }
        for failure in sent.failedRecordSaves {
            guard let id = UUID(uuidString: failure.record.recordID.recordName) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                // Another device saved it first. The newer edit wins; if it's ours, it goes again on top of theirs.
                guard let server = failure.error.serverRecord, let item = Self.syncedItem(from: server) else { continue }
                let results = try? await database.applyRemote([RemoteItem(item: item, systemFields: Self.systemFields(of: server))])
                if results?[id] == .keptLocal { resend.append(id) }
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                resend.append(id)
            case .unknownItem:
                // The record is gone from the server; send it as new.
                try? await database.forgetSyncedRecords([id])
                resend.append(id)
            case .quotaExceeded:
                onEvent(.quotaExceeded)
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
                 .requestRateLimited, .accountTemporarilyUnavailable, .operationCancelled:
                // The engine retries these itself.
                break
            default:
                logger.error("Couldn't save item \(id): \(failure.error)")
            }
        }
        queue(resend, on: engine)
    }

    private func reuploadEverything(on engine: CKSyncEngine) async {
        try? await database.resetSync()
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        await queueDirtyItems(on: engine)
    }

    private func queueDirtyItems(on engine: CKSyncEngine) async {
        queue((try? await database.dirtyItemIDs()) ?? [], on: engine)
    }

    /// Adds saves for these items, skipping any already pending.
    private func queue(_ ids: [UUID], on engine: CKSyncEngine) {
        guard !ids.isEmpty else { return }
        let pending = Set(engine.state.pendingRecordZoneChanges)
        let changes = ids
            .map { CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID(for: $0)) }
            .filter { !pending.contains($0) }
        if !changes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: changes)
        }
    }

    // MARK: - Records

    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// The item as a record, built on the server's last version when there is one, so saving it doesn't conflict.
    static func record(for item: SyncedItem, systemFields: Data?) -> CKRecord {
        let record = systemFields.flatMap(Self.record(fromSystemFields:))
            ?? CKRecord(recordType: recordType, recordID: recordID(for: item.id))
        record.encryptedValues["text"] = item.text
        record.encryptedValues["link"] = item.link?.absoluteString
        record["createdAt"] = item.createdAt
        record["updatedAt"] = item.updatedAt
        record["deletedAt"] = item.deletedAt
        return record
    }

    /// The item a record holds, or nil if it isn't a well-formed item.
    static func syncedItem(from record: CKRecord) -> SyncedItem? {
        guard record.recordType == recordType,
              let id = UUID(uuidString: record.recordID.recordName),
              let text = record.encryptedValues["text"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date
        else { return nil }
        let link = (record.encryptedValues["link"] as? String).flatMap(URL.init(string:))
        return SyncedItem(id: id, text: text, link: link, createdAt: createdAt, updatedAt: updatedAt, deletedAt: record["deletedAt"] as? Date)
    }

    /// The record's metadata without its fields: what the next save builds on.
    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
