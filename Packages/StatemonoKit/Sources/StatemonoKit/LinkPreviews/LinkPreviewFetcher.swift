import CoreGraphics
import Foundation

/// Builds a link's preview on the device: X posts through fxtwitter, everything else from the page's own metadata.
public struct LinkPreviewFetcher: Sendable {
    /// A current Safari. Some sites refuse, or serve a bare page to, the default networking user agent.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    /// Stop reading a page here if `</head>` hasn't shown up.
    static let maxHeadBytes = 1 << 20
    static let maxSummaryLength = 500

    private let session: URLSession
    private let images: PreviewImageLoader

    /// Images are downloaded through `images` into its disk store, so they're ready by the time the preview shows.
    public init(images: PreviewImageLoader = .shared) {
        self.init(images: images, session: .uncached)
    }

    init(images: PreviewImageLoader, session: URLSession) {
        self.images = images
        self.session = session
    }

    /// The preview for `url`, or nil when the page has nothing worth showing.
    public func preview(for url: URL) async throws -> LinkPreview? {
        if let post = XPost(url: url) {
            return try await preview(for: post)
        }
        return try await webPreview(for: url)
    }

    // MARK: - X

    private func preview(for post: XPost) async throws -> LinkPreview {
        let (data, _) = try await get(post.apiURL, accept: "application/json")
        let content = try XPostContent(fxTwitterJSON: data)
        var preview = LinkPreview(
            siteName: XPostContent.siteName,
            title: content.title,
            summary: content.text.isEmpty ? nil : Self.truncated(content.text)
        )
        if let media = content.mediaURL, let info = try? await images.info(for: media) {
            preview.image = PreviewImage(url: media, width: info.width, height: info.height, isLarge: info.width >= 200, placeholder: info.placeholder)
        } else if let avatar = content.avatarURL, let info = try? await images.info(for: avatar) {
            preview.image = PreviewImage(url: avatar, width: info.width, height: info.height, isLarge: false, placeholder: info.placeholder)
        }
        return preview
    }

    // MARK: - Websites

    private func webPreview(for url: URL) async throws -> LinkPreview? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            bytes.task.cancel()
            throw LinkPreviewError.badStatus(http.statusCode)
        }
        let pageURL = response.url ?? url
        let mimeType = response.mimeType?.lowercased() ?? ""

        // A direct link to an image: show the image itself.
        if mimeType.hasPrefix("image/") {
            bytes.task.cancel()
            let info = try await images.info(for: pageURL)
            return LinkPreview(
                siteName: Self.displayHost(pageURL),
                image: PreviewImage(url: pageURL, width: info.width, height: info.height, placeholder: info.placeholder)
            )
        }
        guard mimeType.contains("html") else {
            bytes.task.cancel()
            return nil
        }

        let head = try await Self.readHead(bytes)
        let page = await Self.parse(head, encodingName: response.textEncodingName, baseURL: pageURL)
        guard page.title != nil || page.description != nil || page.imageURL != nil else { return nil }

        let siteName = page.siteName ?? Self.displayHost(pageURL)
        var preview = LinkPreview(
            siteName: siteName,
            // Home pages often use the site's name as the title too; showing it twice adds nothing.
            title: page.title?.caseInsensitiveCompare(siteName ?? "") == .orderedSame ? nil : page.title,
            summary: page.description.map(Self.truncated)
        )
        if let imageURL = page.imageURL, let info = try? await images.info(for: imageURL) {
            preview.image = PreviewImage(
                url: imageURL,
                width: info.width,
                height: info.height,
                isLarge: Self.showsLargeImage(page: page, host: pageURL.host(), imagePixelWidth: CGFloat(info.width)),
                placeholder: info.placeholder
            )
        }
        return preview
    }

    /// Telegram's rule for full-width images (TelegramSwift `WPArticleLayout.isFullImageSize`): photo and video pages,
    /// X and Instagram, and pages without a description, unless the image is under 200px wide. Everything else gets a
    /// small thumbnail. Telegram's server can also mark media as large; `twitter:card = summary_large_image`, the
    /// page asking for a big card, stands in for that here.
    static func showsLargeImage(page: PageMetadata, host: String?, imagePixelWidth: CGFloat) -> Bool {
        guard imagePixelWidth >= 200 else { return false }
        if let host = host?.lowercased(), host == "instagram.com" || host.hasSuffix(".instagram.com") { return true }
        if let type = page.type, type == "photo" || type.hasPrefix("video") { return true }
        if page.twitterCard == "summary_large_image" { return true }
        return page.description == nil
    }

    // MARK: - Helpers

    private func get(_ url: URL, accept: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LinkPreviewError.badStatus(http.statusCode)
        }
        return (data, response)
    }

    /// Reads until `</head>` or `maxHeadBytes`, then stops the download: the rest of the page isn't needed.
    private static func readHead(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        data.reserveCapacity(64 * 1024)
        for try await byte in bytes {
            data.append(byte)
            if byte == UInt8(ascii: ">"), data.count >= 7,
               String(decoding: data.suffix(7), as: UTF8.self).lowercased() == "</head>" { break }
            if data.count >= maxHeadBytes { break }
        }
        bytes.task.cancel()
        return data
    }

    @concurrent
    private static func parse(_ data: Data, encodingName: String?, baseURL: URL) async -> PageMetadata {
        PageMetadata(html: decodeText(data, encodingName: encodingName), baseURL: baseURL)
    }

    /// Uses the charset from the response, then from a `<meta charset>`, then UTF-8 (replacing invalid bytes).
    static func decodeText(_ data: Data, encodingName: String?) -> String {
        let sniffed = String(decoding: data.prefix(4096), as: UTF8.self)
            .firstMatch(of: /charset\s*=\s*["']?([-A-Za-z0-9_:.]+)/.ignoresCase())
            .map { String($0.output.1) }
        if let name = encodingName ?? sniffed {
            let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if encoding != kCFStringEncodingInvalidId,
               let text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))) {
                return text
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// The host without a leading "www.", used when a page doesn't name itself.
    static func displayHost(_ url: URL) -> String? {
        guard let host = url.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func truncated(_ text: String) -> String {
        guard text.count > maxSummaryLength else { return text }
        let cut = text.prefix(maxSummaryLength)
        let end = cut.lastIndex(where: \.isWhitespace) ?? cut.endIndex
        return cut[..<end].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }
}
