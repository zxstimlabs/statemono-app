import Foundation

/// A way to sync items between devices. Per the design principles, all sync goes through this one protocol, so the
/// backend can be swapped: `CloudKitSync` today, perhaps a server later. The rules for what a change means live on
/// `AppDatabase` (`AppDatabase+Sync`), for any backend to share.
public protocol SyncBackend: AnyObject, Sendable {
    /// Resumes from the backend's saved state and queues every item not uploaded yet.
    func start() async
    /// Stops syncing. What's waiting stays dirty in the database.
    func stop() async
    /// Queues items that changed here.
    func itemsChanged(_ ids: [UUID])
    /// Asks for other devices' changes now.
    func fetchChanges() async
}

/// What a backend reports, for the app's status.
public enum SyncEvent: Sendable, Equatable {
    case fetching
    case sending
    /// A fetch or a send finished.
    case finished
    case accountChanged
    /// The backend's storage is full, so changes wait here.
    case quotaExceeded
    /// The user deleted the app's data from the backend. Syncing should stop until they turn it on again.
    case dataDeletedRemotely
}
