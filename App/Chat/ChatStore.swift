import Foundation
import Observation
import StatemonoKit

/// The feed, read from the database a page at a time. Sending saves an item, fetching its preview saves that too, and
/// the database's observation brings both back here: the UI reads only from the database.
///
/// What's loaded is everything from `start` on (see `AppDatabase.observeFeed(from:)`): new messages extend it at the
/// bottom without pushing old ones out of the top, and loading older messages moves `start` back.
@MainActor @Observable
final class ChatStore {
    /// Messages loaded per page, as Telegram loads history in windows. The feed isn't lazy, so keeping it to a few
    /// pages keeps each scroll frame cheap (see CLAUDE.md).
    static let pageSize = 50

    private(set) var messages: [Message] = []
    private(set) var hasOlder = false
    /// Messages whose preview is being fetched, for the spinning reload icon.
    private(set) var loadingPreviews: Set<Message.ID> = []

    @ObservationIgnored let database: AppDatabase
    /// Finds links by meaning, once turned on in Settings.
    @ObservationIgnored let smartSearch: SmartSearch
    /// Syncs messages through iCloud (docs/sync-plan.md). Its changes reach the feed through the database, like sends.
    @ObservationIgnored let sync: ICloudSync
    @ObservationIgnored private let previews: LinkPreviewFetcher?
    /// The oldest loaded message's date; nil loads all of history.
    @ObservationIgnored private var start: Date?
    @ObservationIgnored private var observation: FeedObservation?
    /// Previews that failed this session, so they aren't retried in a loop. The reload button still retries them.
    @ObservationIgnored private var failedPreviews: Set<Message.ID> = []
    /// Set while the reader moves the window's start back, which is the one time it should grow by more than a page at
    /// once. See `show(_:)`.
    @ObservationIgnored private var isLoadingHistory = false

    init(database: AppDatabase, previews: LinkPreviewFetcher?) {
        self.database = database
        self.previews = previews
        smartSearch = SmartSearch(database: database)
        sync = ICloudSync(database: database)
        start = try? database.feedStart(newest: Self.pageSize)
        observe()
    }

    /// Loads the next page of older messages.
    func loadOlder() {
        guard hasOlder, let start else { return }
        self.start = try? database.feedStart(before: start, adding: Self.pageSize)
        observeHistory()
    }

    /// Messages kept loaded above one the chat jumps to. Centering a message at the very top of what's loaded would
    /// reach the top, and the next page would load in the middle of the jump and throw it off.
    static let jumpMargin = 10

    /// Loads history back to `jumpMargin` messages above `id`, for jumping to a search result or a date: when `id`
    /// isn't loaded, or fewer than that are loaded above it while older ones exist. `willPrepend` runs first if older
    /// messages are about to load, so the feed can keep what's on screen in place.
    func loadHistory(before id: Message.ID, willPrepend: () -> Void) {
        guard hasOlder, let start else { return }
        if let index = messages.firstIndex(where: { $0.id == id }), index >= Self.jumpMargin { return }
        guard let date = try? database.createdAt(of: id) else { return }
        let newStart = try? database.feedStart(before: date, adding: Self.jumpMargin)
        // Only ever further back. Nil loads all of history.
        guard newStart.map({ $0 < start }) ?? true else { return }
        willPrepend()
        self.start = newStart
        observeHistory()
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let link = Linkifier.firstURL(in: text)
        guard let item = try? database.insertItem(text: text, link: link), let link else { return }
        // A link that's already in the feed reuses its preview instead of fetching it again.
        if let known = try? database.existingPreview(for: link) {
            Task { try? await database.savePreview(known, for: item.id) }
        } else {
            loadPreview(for: item.id, link: link)
        }
    }

    /// Deletes a message, leaving a tombstone. It leaves the feed when the database's observation reports the change.
    func delete(_ id: Message.ID) {
        try? database.deleteItem(id)
    }

    /// Fetches the preview again, image included, replacing the current one when the new one arrives.
    func reloadPreview(for id: Message.ID) {
        guard let message = messages.first(where: { $0.id == id }), let link = message.link else { return }
        if let image = message.preview?.image {
            PreviewImageLoader.shared.forget(image.url)
        }
        failedPreviews.remove(id)
        loadPreview(for: id, link: link)
    }

    // MARK: - Private

    /// Observes from the new start; the page arrives before this returns.
    private func observeHistory() {
        isLoadingHistory = true
        observe()
        isLoadingHistory = false
    }

    /// The first page arrives before this returns, so the feed never shows empty for a frame.
    private func observe() {
        observation?.cancel()
        observation = database.observeFeed(from: start) { [weak self] page in
            self?.show(page)
        }
    }

    private func show(_ page: FeedPage) {
        // Synced messages can arrive by the thousand inside the window. The feed isn't lazy, so when it would grow by
        // more than a page at once, other than by loading history, it goes back to the newest page.
        if !isLoadingHistory, page.entries.count > messages.count + Self.pageSize {
            start = try? database.feedStart(newest: Self.pageSize)
            observe()
            return
        }
        messages = page.entries.map(Message.init)
        hasOlder = page.hasOlder
        // Links saved without a preview, because the app quit mid-fetch or the fetch failed, get another try.
        for message in messages where !message.hasFetchedPreview && !failedPreviews.contains(message.id) {
            if let link = message.link { loadPreview(for: message.id, link: link) }
        }
    }

    /// Fetches on the device and saves the result. A page with nothing to show is saved as such; a failure keeps what
    /// was there.
    private func loadPreview(for id: Message.ID, link: URL) {
        guard let previews, !loadingPreviews.contains(id) else { return }
        loadingPreviews.insert(id)
        Task {
            defer { loadingPreviews.remove(id) }
            do {
                let preview = try await previews.preview(for: link)
                try await database.savePreview(preview, for: id)
            } catch {
                failedPreviews.insert(id)
            }
        }
    }
}
