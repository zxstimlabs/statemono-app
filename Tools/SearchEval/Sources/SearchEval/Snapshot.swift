import Foundation
@testable import StatemonoKit

/// Every test link's preview, fetched once with the app's own fetcher and kept, so every run searches the same text.
enum Snapshot {
    struct Entry: Codable {
        let id: Int
        let url: URL
        var siteName: String?
        var title: String?
        var summary: String?
        /// Why there's no preview: a failed request, or a page with nothing to show.
        var problem: String?

        var hasText: Bool { siteName != nil || title != nil || summary != nil }

        /// What the plan's Smart Search and tags read: the preview's title, site name and description, then the
        /// message text, which for these links is the link itself.
        var document: String {
            [title, siteName, summary, url.absoluteString].compactMap { $0 }.joined(separator: "\n")
        }

        /// The preview's text alone, without the link, which is mostly noise for meaning.
        var previewText: String {
            [title, siteName, summary].compactMap { $0 }.joined(separator: "\n")
        }
    }

    /// Keeps previews already fetched for the same link, and fetches only new links and ones still missing a preview,
    /// unless `refresh` is set.
    static func run(paths: Paths, refresh: Bool) async throws {
        let links = try TestSet.load(paths).links
        let kept = refresh ? [:] : Dictionary(((try? load(paths)) ?? []).filter(\.hasText).map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
        let toFetch = links.filter { kept[$0.url] == nil }
        // Images go to a throwaway folder: the fetcher downloads them, but search only needs the text.
        let media = MediaStore(directory: FileManager.default.temporaryDirectory.appending(path: "SearchEval-media-\(UUID())"))
        let session = URLSession(configuration: .ephemeral)
        let fetcher = LinkPreviewFetcher(
            images: PreviewImageLoader(store: media, download: { try await session.data(from: $0).0 }),
            session: .uncached
        )
        print("fetching \(toFetch.count) of \(links.count) links…")
        var entries = links.compactMap { link in kept[link.url].map { Entry(id: link.id, url: $0.url, siteName: $0.siteName, title: $0.title, summary: $0.summary) } }
        await withTaskGroup(of: Entry.self) { group in
            var pending = toFetch.makeIterator()
            func addNext() {
                guard let link = pending.next() else { return }
                group.addTask { await fetch(link, with: fetcher) }
            }
            for _ in 0..<6 { addNext() }
            for await entry in group {
                entries.append(entry)
                print(entry.problem.map { "  #\(entry.id) \(entry.url.host() ?? ""): \($0)" } ?? "  #\(entry.id) ok")
                addNext()
            }
        }
        entries.sort { $0.id < $1.id }
        try JSONEncoder.pretty.encode(entries).write(to: paths.snapshot)
        try? FileManager.default.removeItem(at: media.directory)
        let missing = entries.filter { !$0.hasText }
        print("\(entries.count - missing.count) of \(entries.count) have a preview. Without: \(missing.map { "#\($0.id)" }.joined(separator: ", "))")
    }

    private static func fetch(_ link: TestSet.Link, with fetcher: LinkPreviewFetcher) async -> Entry {
        var entry = Entry(id: link.id, url: link.url)
        do {
            if let preview = try await fetcher.preview(for: link.url) {
                entry.siteName = preview.siteName
                entry.title = preview.title
                entry.summary = preview.summary
                if !entry.hasText { entry.problem = "preview has no text" }
            } else {
                entry.problem = "no preview"
            }
        } catch {
            entry.problem = "\(error)"
        }
        return entry
    }

    static func load(_ paths: Paths) throws -> [Entry] {
        try JSONDecoder().decode([Entry].self, from: Data(contentsOf: paths.snapshot))
    }
}
