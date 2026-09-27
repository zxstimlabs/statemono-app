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
    @ObservationIgnored private let previews: LinkPreviewFetcher?
    /// The oldest loaded message's date; nil loads all of history.
    @ObservationIgnored private var start: Date?
    @ObservationIgnored private var observation: FeedObservation?
    /// Previews that failed this session, so they aren't retried in a loop. The reload button still retries them.
    @ObservationIgnored private var failedPreviews: Set<Message.ID> = []

    init(database: AppDatabase, previews: LinkPreviewFetcher?) {
        self.database = database
        self.previews = previews
        start = try? database.feedStart(newest: Self.pageSize)
        observe()
    }

    /// Loads the next page of older messages.
    func loadOlder() {
        guard hasOlder, let start else { return }
        self.start = try? database.feedStart(before: start, adding: Self.pageSize)
        observe()
    }

    /// Loads history back to `id`, plus a few messages above it, for jumping to a search result or a date.
    func ensureLoaded(_ id: Message.ID) {
        guard let start, !messages.contains(where: { $0.id == id }),
              let date = try? database.createdAt(of: id), date < start
        else { return }
        self.start = try? database.feedStart(before: date, adding: 10)
        observe()
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

    /// The first page arrives before this returns, so the feed never shows empty for a frame.
    private func observe() {
        observation?.cancel()
        observation = database.observeFeed(from: start) { [weak self] page in
            self?.show(page)
        }
    }

    private func show(_ page: FeedPage) {
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
