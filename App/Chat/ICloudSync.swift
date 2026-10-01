import CloudKit
import Foundation
import Observation
import StatemonoKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// iCloud sync (docs/sync-plan.md) as Settings shows it. `CloudKitSync`, the `SyncBackend`, does the work; this starts
/// and stops it, hands it the items that change here, and keeps the status. The switch is per device, on by default, in `UserDefaults`.
@MainActor @Observable
final class ICloudSync {
    enum Account: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case unknown
    }

    enum Problem: Equatable {
        /// iCloud is full, so changes wait here.
        case quotaExceeded
        /// The user deleted Statemono's data from iCloud, which turned syncing off.
        case deletedInICloud
    }

    /// The iCloud container named in the app's Info.plist (`project.yml`), if the app is also signed to use it. Test
    /// harnesses name none. A build that lost its iCloud entitlements, as TestFlight build 19 did on iPhone, doesn't sync
    /// rather than crash: CloudKit traps on a container the app isn't entitled to (`CloudKitSync.canUse`).
    static let containerIdentifier: String? = {
        guard let container = Bundle.main.object(forInfoDictionaryKey: "StatemonoICloudContainer") as? String,
              CloudKitSync.canUse(containerIdentifier: container)
        else { return nil }
        return container
    }()

    private(set) var isOn: Bool
    private(set) var account: Account = .checking
    /// Items made or changed here that iCloud doesn't have yet.
    private(set) var pendingCount = 0
    private(set) var lastSynced: Date?
    private(set) var problem: Problem?
    /// Fetches and sends running now.
    private var operations = 0

    var isAvailable: Bool { Self.containerIdentifier != nil }
    var isSyncing: Bool { operations > 0 }

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private var backend: (any SyncBackend)?
    @ObservationIgnored private var dirtyObservation: FeedObservation?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private static let enabledKey = "sync.enabled"
    private static let lastSyncedKey = "sync.lastSynced"

    init(database: AppDatabase) {
        self.database = database
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        isOn = Self.containerIdentifier != nil && UserDefaults.standard.bool(forKey: Self.enabledKey)
        lastSynced = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Date
        dirtyObservation = database.observeDirtyItems { [weak self] ids in
            self?.pendingCount = ids.count
            self?.backend?.itemsChanged(ids)
        }
        guard isAvailable else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccount() }
        })
        observers.append(center.addObserver(forName: Self.didBecomeActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
        refreshAccount()
        if isOn { start() }
    }

    /// Turning it off stops syncing and keeps everything, here and in iCloud.
    func setOn(_ on: Bool) {
        guard isAvailable, on != isOn else { return }
        isOn = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            problem = nil
            start()
        } else {
            stop()
        }
    }

    // MARK: - Private

    #if os(macOS)
    private static let didBecomeActive = NSApplication.didBecomeActiveNotification
    #else
    private static let didBecomeActive = UIApplication.didBecomeActiveNotification
    #endif

    private func start() {
        guard let container = Self.containerIdentifier, backend == nil,
              let backend = CloudKitSync(containerIdentifier: container, database: database, onEvent: { [weak self] event in
                  Task { @MainActor in self?.handle(event) }
              })
        else { return }
        self.backend = backend
        Task { await backend.start() }
    }

    private func stop() {
        guard let backend else { return }
        self.backend = nil
        operations = 0
        Task { await backend.stop() }
    }

    private func handle(_ event: SyncEvent) {
        guard backend != nil else { return }
        switch event {
        case .fetching, .sending:
            operations += 1
        case .finished:
            operations = max(0, operations - 1)
            if account == .available {
                lastSynced = .now
                UserDefaults.standard.set(lastSynced, forKey: Self.lastSyncedKey)
            }
            if problem == .quotaExceeded, pendingCount == 0 { problem = nil }
        case .accountChanged:
            refreshAccount()
        case .quotaExceeded:
            problem = .quotaExceeded
        case .dataDeletedRemotely:
            problem = .deletedInICloud
            isOn = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            stop()
        }
    }

    /// Other devices' changes may have arrived while the app was away, and the user may have signed in or out.
    private func becameActive() {
        refreshAccount()
        if let backend {
            Task { await backend.fetchChanges() }
        }
    }

    private func refreshAccount() {
        guard let container = Self.containerIdentifier else { return }
        Task {
            account = switch await CloudKitSync.accountStatus(containerIdentifier: container) {
            case .none: .unknown
            case .available: .available
            case .noAccount: .noAccount
            case .restricted: .restricted
            case .temporarilyUnavailable: .temporarilyUnavailable
            default: .unknown
            }
        }
    }
}
