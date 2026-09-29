import StatemonoKit
import SwiftUI

/// A link-preview image, loaded the way Telegram loads chat media (see `PreviewImageLoader`).
///
/// - It shows the preview's tiny placeholder, blurred, until the image is ready, so it never looks empty.
/// - It decodes the image at exactly the pixels it's drawn at.
/// - It loads only once it's on screen. The feed isn't lazy, so every image view exists up front, and loading them all
///   would read or download the whole history. Images already on disk load right away. Downloads wait until the image
///   has stayed in view for `settleDelay`, so images that fly past during a fast scroll aren't fetched, and scrolling
///   away cancels them.
/// - Off screen, it lets go of the decoded image. The loader's small memory cache and the disk bring it back.
struct RemoteImage: View {
    static let settleDelay: Duration = .milliseconds(100)

    let image: PreviewImage
    /// The size it's drawn at, in points.
    let size: CGSize

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: CGImage?
    @State private var isVisible = false

    init(image: PreviewImage, size: CGSize) {
        self.image = image
        self.size = size
        _loaded = State(initialValue: PreviewImageLoader.shared.cachedImage(for: image.url))
    }

    /// Longest side, in pixels, needed to fill `size` at this aspect ratio (Telegram's `drawingSize`).
    private var pixelSize: Int {
        let aspect = max(image.aspectRatio, 0.01)
        let heightToFill = max(size.width / aspect, size.height)
        return Int((max(aspect, 1) * heightToFill * displayScale).rounded(.up))
    }

    var body: some View {
        ZStack {
            if let placeholder = image.placeholder.flatMap(PreviewPlaceholder.image(from:)) {
                Image(decorative: placeholder, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.08))
            }
            if let loaded {
                Image(decorative: loaded, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipped()
        .onScrollVisibilityChange(threshold: 0.01) { visible in
            isVisible = visible
            loaded = visible ? loaded ?? PreviewImageLoader.shared.cachedImage(for: image.url) : nil
        }
        .task(id: LoadKey(url: image.url, isVisible: isVisible, pixelSize: pixelSize)) {
            // No size yet: on iOS the feed hasn't been measured.
            guard isVisible, pixelSize > 0 else { return }
            if let loaded, max(loaded.width, loaded.height) >= pixelSize { return }
            let loader = PreviewImageLoader.shared
            if !loader.isStored(image.url) {
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled else { return }
            }
            guard let decoded = try? await loader.image(for: image.url, maxPixelSize: pixelSize) else { return }
            withAnimation(.smooth(duration: 0.2)) { loaded = decoded }
        }
    }

    private struct LoadKey: Equatable {
        let url: URL
        let isVisible: Bool
        let pixelSize: Int
    }
}
