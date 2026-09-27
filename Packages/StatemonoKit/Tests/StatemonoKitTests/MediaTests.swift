import Foundation
import ImageIO
import Synchronization
import Testing
@testable import StatemonoKit

/// A fresh store in a temporary directory, removed after the test.
private func temporaryStore() -> MediaStore {
    MediaStore(directory: FileManager.default.temporaryDirectory.appending(path: "media-\(UUID().uuidString)"))
}

private func pngData(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

struct MediaStoreTests {
    let a = URL(string: "https://example.com/a.jpg")!
    let b = URL(string: "https://example.com/b.jpg")!

    @Test func `stores one file per URL and reads it back`() throws {
        let store = temporaryStore()
        defer { store.removeAll() }
        #expect(store.data(for: a) == nil)
        try store.store(Data("alpha".utf8), for: a)
        #expect(store.contains(a))
        #expect(store.data(for: a) == Data("alpha".utf8))
        #expect(store.file(for: a).lastPathComponent.hasPrefix("http-"))
        #expect(store.file(for: a) != store.file(for: b))
        store.remove(a)
        #expect(!store.contains(a))
    }
}

struct PreviewImageLoaderTests {
    let url = URL(string: "https://example.com/photo.png")!

    @Test func `downloads once, then reads from disk at the size asked for`() async throws {
        let store = temporaryStore()
        defer { store.removeAll() }
        let png = try pngData(width: 3000, height: 1500)
        let downloads = Mutex(0)
        let loader = PreviewImageLoader(store: store) { _ in
            downloads.withLock { $0 += 1 }
            return png
        }

        let info = try await loader.info(for: url)
        #expect(info.width == 3000)
        #expect(info.height == 1500)
        #expect(loader.isStored(url))

        let small = try await loader.image(for: url, maxPixelSize: 108)
        #expect(small.width == 108)
        let large = try await loader.image(for: url, maxPixelSize: 600)
        #expect(large.width == 600)
        #expect(downloads.withLock { $0 } == 1)

        // A new loader, as after a relaunch: the image comes from disk, not the network.
        let relaunched = PreviewImageLoader(store: store) { _ in
            downloads.withLock { $0 += 1 }
            return png
        }
        #expect(relaunched.cachedImage(for: url) == nil)
        _ = try await relaunched.image(for: url, maxPixelSize: 300)
        #expect(downloads.withLock { $0 } == 1)
    }

    @Test func `requests for the same image share one download`() async throws {
        let store = temporaryStore()
        defer { store.removeAll() }
        let png = try pngData(width: 400, height: 200)
        let downloads = Mutex(0)
        let loader = PreviewImageLoader(store: store) { _ in
            downloads.withLock { $0 += 1 }
            try await Task.sleep(for: .milliseconds(100))
            return png
        }
        async let first = loader.image(for: url, maxPixelSize: 200)
        async let second = loader.image(for: url, maxPixelSize: 200)
        _ = try await (first, second)
        #expect(downloads.withLock { $0 } == 1)
    }

    @Test func `cancels the download only when nobody is waiting`() async throws {
        let store = temporaryStore()
        defer { store.removeAll() }
        let cancelled = Mutex(false)
        let loader = PreviewImageLoader(store: store) { _ in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                cancelled.withLock { $0 = true }
                throw error
            }
            return Data()
        }
        let waiter = Task { try await loader.image(for: url, maxPixelSize: 100) }
        try await Task.sleep(for: .milliseconds(50))
        waiter.cancel()
        _ = await waiter.result
        try await Task.sleep(for: .milliseconds(50))
        #expect(cancelled.withLock { $0 })
        #expect(!loader.isStored(url))
    }

    @Test func `forgetting removes the image from memory and disk`() async throws {
        let store = temporaryStore()
        defer { store.removeAll() }
        let png = try pngData(width: 200, height: 100)
        let loader = PreviewImageLoader(store: store) { _ in png }
        _ = try await loader.image(for: url, maxPixelSize: 100)
        #expect(loader.cachedImage(for: url) != nil && loader.isStored(url))
        loader.forget(url)
        #expect(loader.cachedImage(for: url) == nil && !loader.isStored(url))
    }
}

struct PreviewPlaceholderTests {
    @Test func `is tiny and renders blurred at thumbnail size`() throws {
        let png = try pngData(width: 1200, height: 630)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let data = try #require(PreviewPlaceholder.make(from: source))
        #expect(data.count < 1024)
        let image = try #require(PreviewPlaceholder.image(from: data))
        #expect(image.width == PreviewPlaceholder.pixelSize)
        #expect(image.height == 21)
        #expect(PreviewPlaceholder.image(from: data) === image)
    }
}

struct ImageCacheTests {
    @Test func `evicts least recently used images past its budget`() throws {
        func image(_ side: Int) throws -> CGImage {
            let context = try #require(CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            return try #require(context.makeImage())
        }
        let url = { (name: String) in URL(string: "https://example.com/\(name).jpg")! }
        // Each 100×100 image costs 80,000 bytes (twice its 40,000 pixel bytes); the budget fits two.
        var cache = ImageCache(limit: 180_000)
        cache.insert(try image(100), for: url("a"))
        cache.insert(try image(100), for: url("b"))
        _ = cache.image(for: url("a"))               // a is now the most recently used
        cache.insert(try image(100), for: url("c"))  // over budget: b goes
        #expect(cache.image(for: url("a")) != nil)
        #expect(cache.image(for: url("b")) == nil)
        #expect(cache.image(for: url("c")) != nil)
        #expect(cache.totalCost == 160_000)
        cache.removeAll()
        #expect(cache.count == 0 && cache.totalCost == 0)
    }
}
