import Foundation

/// The preview-relevant parts of a web page's `<head>`: OpenGraph tags first, then Twitter card tags, then plain
/// `<title>` and `<meta name="description">`.
struct PageMetadata: Equatable, Sendable {
    var siteName: String?
    var title: String?
    var description: String?
    var imageURL: URL?
    /// `og:type`, such as "website", "article", "video.other".
    var type: String?
    /// `twitter:card`, such as "summary" or "summary_large_image".
    var twitterCard: String?

    init(siteName: String? = nil, title: String? = nil, description: String? = nil, imageURL: URL? = nil,
         type: String? = nil, twitterCard: String? = nil) {
        self.siteName = siteName
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.type = type
        self.twitterCard = twitterCard
    }

    /// Parses `html` (only its `<head>` counts). `baseURL` resolves relative image URLs; pass the URL the page was
    /// served from, after redirects.
    init(html: String, baseURL: URL) {
        let head = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.lowerBound]) } ?? html

        var meta: [String: String] = [:]
        for tag in head.matches(of: /<meta\b[^>]*>/.ignoresCase()) {
            let attributes = Self.attributes(of: tag.output)
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"].map(Self.clean), !content.isEmpty,
                  meta[key] == nil
            else { continue }
            meta[key] = content
        }
        let htmlTitle = head.firstMatch(of: /<title[^>]*>(.*?)<\/title>/.ignoresCase().dotMatchesNewlines())
            .map { Self.clean(String($0.output.1)) }

        siteName = meta["og:site_name"]
        title = meta["og:title"] ?? meta["twitter:title"] ?? htmlTitle.flatMap { $0.isEmpty ? nil : $0 }
        description = meta["og:description"] ?? meta["twitter:description"] ?? meta["description"]
        imageURL = ["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src"]
            .lazy
            .compactMap { meta[$0].flatMap { Self.resolve($0, against: baseURL) } }
            .first
        type = meta["og:type"]?.lowercased()
        twitterCard = meta["twitter:card"]?.lowercased()
    }

    /// Attribute names (lowercased) to values, with quotes removed and entities decoded.
    private static func attributes(of tag: Substring) -> [String: String] {
        var attributes: [String: String] = [:]
        let pattern = /([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'<>]+))/
        for match in tag.matches(of: pattern) {
            let value = match.output.2 ?? match.output.3 ?? match.output.4 ?? ""
            attributes[match.output.1.lowercased()] = HTMLEntities.decode(String(value))
        }
        return attributes
    }

    /// Decodes entities and collapses runs of whitespace, including newlines, into single spaces.
    static func clean(_ text: String) -> String {
        HTMLEntities.decode(text)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func resolve(_ string: String, against base: URL) -> URL? {
        let url = URL(string: string, relativeTo: base)
            ?? string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap { URL(string: $0, relativeTo: base) }
        guard let url = url?.absoluteURL, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}

enum HTMLEntities {
    /// Decodes numeric entities and the named ones that show up in page titles and descriptions.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacing(/&(#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z]{2,8});/) { match in
            let name = match.output.1
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                return UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
            }
            if name.hasPrefix("#") {
                return UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
            }
            return named[String(name)] ?? String(match.output.0)
        }
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "laquo": "«", "raquo": "»", "middot": "·", "bull": "•", "copy": "©", "reg": "®", "trade": "™",
    ]
}
