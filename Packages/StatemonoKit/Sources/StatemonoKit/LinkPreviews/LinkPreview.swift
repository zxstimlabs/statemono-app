import Foundation

/// What a link shows under it in the feed. The fields are Telegram's webpage preview: site name, title, description,
/// and an optional image.
public struct LinkPreview: Hashable, Sendable {
    public var siteName: String?
    public var title: String?
    public var summary: String?
    public var image: PreviewImage?

    public init(siteName: String? = nil, title: String? = nil, summary: String? = nil, image: PreviewImage? = nil) {
        self.siteName = siteName
        self.title = title
        self.summary = summary
        self.image = image
    }
}

public struct PreviewImage: Hashable, Sendable {
    /// The image's `media` row, and its file name in `MediaStore`.
    public var id: String
    /// Where the image comes from. It's downloaded once into `MediaStore` and read from disk after that.
    public var url: URL
    /// Pixel size, known up front so the bubble doesn't jump when the image loads.
    public var width: Int
    public var height: Int
    /// Full width under the text, or a small thumbnail beside it.
    public var isLarge: Bool
    /// A tiny JPEG (`PreviewPlaceholder`), shown blurred until the image loads. Stored with the preview.
    public var placeholder: Data?

    public var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(max(height, 1))
    }

    public init(url: URL, width: Int, height: Int, isLarge: Bool = true, placeholder: Data? = nil) {
        id = MediaStore.id(for: url)
        self.url = url
        self.width = width
        self.height = height
        self.isLarge = isLarge
        self.placeholder = placeholder
    }
}

public enum LinkPreviewError: Error, Equatable {
    case badStatus(Int)
    case unreadableImage
}
