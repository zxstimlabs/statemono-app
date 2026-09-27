import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// Loads link-preview images the way Telegram loads chat media:
/// - Disk first. Every image is downloaded once into `MediaStore` and read from there afterwards, across launches.
/// - Decoded at display size. Each view asks for the pixels it draws (Telegram's `drawingSize`), not the original's.
/// - Memory stays small. Recently shown images are kept in `ImageCache` for scrolling back; re-reading from disk is
///   cheap, so the budget only needs to cover a few screens. It empties when the system reports memory pressure.
/// - One download per image. Views asking for the same URL share it, and it's cancelled only when all of them have
///   stopped waiting (MediaBox's per-resource fetch).
/// - The database is told what's stored and shown (`attach(_:)`), so its `media` table can report usage and clean up
///   the least recently used files first.
public final class PreviewImageLoader: Sendable {
    public static let shared = PreviewImageLoader(store: .shared, download: PreviewImageLoader.fetch)

    /// About 9 large previews on a 2x Mac (see `ImageCache.cost(of:)`); decoding from disk covers the rest.
    static let memoryLimit = 32 << 20

    private let store: MediaStore
    private let download: @Sendable (URL) async throws -> Data
    private let memory = Mutex(ImageCache(limit: memoryLimit))
    private let downloads = Mutex<[URL: SharedDownload]>([:])
    private let index = Mutex<(any MediaIndex)?>(nil)
    /// When each image was last reported as used. Reports go out at most once an hour per image, like Telegram's
    /// batched `utime` calls.
    private let lastReportedUse = Mutex<[String: Date]>([:])
    private let memoryPressure: DispatchSourceMemoryPressure

    init(store: MediaStore, download: @escaping @Sendable (URL) async throws -> Data) {
        self.store = store
        self.download = download
        memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        memoryPressure.setEventHandler { [weak self] in
            self?.memory.withLock { $0.removeAll() }
        }
        memoryPressure.activate()
    }

    deinit {
        memoryPressure.cancel()
    }

    /// Reports stored and shown images to `index`, normally the app's database.
    public func attach(_ index: any MediaIndex) {
        self.index.withLock { $0 = index }
    }

    /// The image if it's in memory, at whatever size it was last decoded, for showing it on the first frame.
    public func cachedImage(for url: URL) -> CGImage? {
        memory.withLock { $0.image(for: url) }
    }

    /// Whether showing the image needs no download.
    public func isStored(_ url: URL) -> Bool {
        url.isFileURL || store.contains(url)
    }

    /// The image decoded to at most `maxPixelSize` on its longest side, from memory, disk, or the network, in that order.
    public func image(for url: URL, maxPixelSize: Int) async throws -> CGImage {
        if let cached = cachedImage(for: url), max(cached.width, cached.height) >= maxPixelSize {
            return cached
        }
        let image = try await Self.decode(try await data(for: url), maxPixelSize: maxPixelSize)
        memory.withLock { $0.insert(image, for: url) }
        return image
    }

    /// Drops the image from memory and disk, so the next request downloads it again.
    public func forget(_ url: URL) {
        memory.withLock { $0.remove(url) }
        store.remove(url)
    }

    // MARK: - Fetching

    /// Size and placeholder for a new preview. Downloads the image into the store, so it's ready when first shown.
    func info(for url: URL) async throws -> ImageInfo {
        try await Self.inspect(try await data(for: url))
    }

    /// The image's bytes, from disk or downloaded once and stored.
    func data(for url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        if let data = store.data(for: url) {
            reportUse(of: url)
            return data
        }

        let shared = downloads.withLock { active in
            if let existing = active[url] {
                existing.waiters.withLock { $0 += 1 }
                return existing
            }
            let id = UUID()
            let task = Task { [self] in
                defer { downloads.withLock { if $0[url]?.id == id { $0[url] = nil } } }
                let data = try await download(url)
                if (try? store.store(data, for: url)) != nil, let bytes = store.fileSize(for: url) {
                    index.withLock { $0 }?.mediaStored(id: MediaStore.id(for: url), byteCount: bytes)
                }
                return data
            }
            let started = SharedDownload(id: id, task: task)
            active[url] = started
            return started
        }
        return try await withTaskCancellationHandler {
            try await shared.task.value
        } onCancel: {
            // The last waiter to leave cancels the download itself.
            if shared.waiters.withLock({ $0 -= 1; return $0 == 0 }) {
                shared.task.cancel()
            }
        }
    }

    private func reportUse(of url: URL) {
        let id = MediaStore.id(for: url)
        let now = Date()
        let due = lastReportedUse.withLock { reported in
            guard reported[id].map({ now.timeIntervalSince($0) >= 3600 }) ?? true else { return false }
            reported[id] = now
            return true
        }
        if due { index.withLock { $0 }?.mediaUsed(id: id) }
    }

    private final class SharedDownload: Sendable {
        let id: UUID
        let task: Task<Data, Error>
        let waiters = Mutex(1)

        init(id: UUID, task: Task<Data, Error>) {
            self.id = id
            self.task = task
        }
    }

    @Sendable
    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(LinkPreviewFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.uncached.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LinkPreviewError.badStatus(http.statusCode)
        }
        return data
    }

    // MARK: - Decoding

    struct ImageInfo: Sendable {
        var width: Int
        var height: Int
        var placeholder: Data?
    }

    /// Decodes at most `maxPixelSize` on the longest side (ImageIO never decodes the full image), and decodes it now
    /// rather than on the first draw, so showing it doesn't stall a frame.
    @concurrent
    private static func decode(_ data: Data, maxPixelSize: Int) async throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
              ] as CFDictionary)
        else { throw LinkPreviewError.unreadableImage }
        return image
    }

    /// Displayed size (EXIF orientation applied) and a tiny placeholder, without decoding the full image.
    @concurrent
    private static func inspect(_ data: Data) async throws -> ImageInfo {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw LinkPreviewError.unreadableImage }
        // Orientations 5–8 are rotated a quarter turn.
        if let orientation = properties[kCGImagePropertyOrientation] as? UInt32, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        return ImageInfo(width: width, height: height, placeholder: PreviewPlaceholder.make(from: source))
    }
}

/// The most recently used images, kept under a byte budget. `NSCache` treats its cost limit as a hint: measured
/// here, it held every image scrolled past, about twice its limit, and never evicted.
struct ImageCache {
    let limit: Int
    private(set) var totalCost = 0
    private var entries: [URL: (image: CGImage, cost: Int)] = [:]
    /// Least recently used first.
    private var order: [URL] = []

    init(limit: Int) {
        self.limit = limit
    }

    var count: Int { entries.count }

    /// Twice the pixel data. Once an image has been on screen, the renderer keeps its own copy for as long as the
    /// image lives: measured here, the cache's real footprint was about double its pixel bytes.
    static func cost(of image: CGImage) -> Int {
        2 * image.bytesPerRow * image.height
    }

    mutating func image(for url: URL) -> CGImage? {
        guard let entry = entries[url] else { return nil }
        order.removeAll { $0 == url }
        order.append(url)
        return entry.image
    }

    mutating func insert(_ image: CGImage, for url: URL) {
        remove(url)
        let cost = Self.cost(of: image)
        entries[url] = (image, cost)
        order.append(url)
        totalCost += cost
        while totalCost > limit, let oldest = order.first {
            remove(oldest)
        }
    }

    mutating func remove(_ url: URL) {
        guard let entry = entries.removeValue(forKey: url) else { return }
        totalCost -= entry.cost
        order.removeAll { $0 == url }
    }

    mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
        totalCost = 0
    }
}

extension URLSession {
    /// No URL cache. Images are kept in `MediaStore` instead, and pages and API responses aren't kept at all.
    static let uncached: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
