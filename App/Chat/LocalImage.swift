import SwiftUI

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

/// An image file on disk: bundled samples for now, downsampled previews in the App Group later.
struct LocalImage: View {
    let url: URL
    @State private var image: PlatformImage?

    init(url: URL) {
        self.url = url
        _image = State(initialValue: ImageCache.shared.cached(url))
    }

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .overlay {
                if let image {
                    #if os(macOS)
                    Image(nsImage: image).resizable().scaledToFill()
                    #else
                    Image(uiImage: image).resizable().scaledToFill()
                    #endif
                }
            }
            .clipped()
            .task(id: url) {
                if image == nil { image = await ImageCache.shared.load(url) }
            }
    }
}

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let images = NSCache<NSURL, PlatformImage>()

    func cached(_ url: URL) -> PlatformImage? {
        images.object(forKey: url as NSURL)
    }

    func load(_ url: URL) async -> PlatformImage? {
        if let image = cached(url) { return image }
        let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
        guard let data, let image = PlatformImage(data: data) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }
}
