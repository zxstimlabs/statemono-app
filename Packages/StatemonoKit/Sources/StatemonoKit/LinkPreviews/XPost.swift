import Foundation

/// A link to a post on X (Twitter). x.com serves an empty JavaScript shell to anything that isn't a known crawler,
/// so posts are read from the fxtwitter API (api.fxtwitter.com), which exists for embeds like this.
struct XPost: Equatable, Sendable {
    let id: String

    private static let hosts: Set<String> = [
        "x.com", "www.x.com", "mobile.x.com",
        "twitter.com", "www.twitter.com", "mobile.twitter.com",
        "fxtwitter.com", "fixupx.com", "vxtwitter.com",
    ]

    /// Recognizes `/{user}/status/{id}`, `/i/status/{id}`, `/i/web/status/{id}`, and `/{user}/statuses/{id}`.
    init?(url: URL) {
        guard let host = url.host()?.lowercased(), Self.hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let status = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }), status + 1 < parts.count else {
            return nil
        }
        let id = parts[status + 1]
        guard !id.isEmpty, id.allSatisfy(\.isASCII), id.allSatisfy(\.isNumber) else { return nil }
        self.id = id
    }

    var apiURL: URL {
        URL(string: "https://api.fxtwitter.com/status/\(id)")!
    }
}

/// The parts of an fxtwitter response that make a Telegram-style preview.
struct XPostContent: Equatable, Sendable {
    /// X's own `og:site_name`, which is what Telegram shows.
    static let siteName = "X (formerly Twitter)"

    var title: String
    var text: String
    /// The first photo, or a video's thumbnail. Shown large.
    var mediaURL: URL?
    /// Shown as a small thumbnail when the post has no media.
    var avatarURL: URL?

    init(fxTwitterJSON data: Data) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        guard let tweet = response.tweet else { throw LinkPreviewError.badStatus(response.code) }

        title = "\(tweet.author.name) (@\(tweet.author.screenName)) on X"
        text = tweet.text
        mediaURL = (tweet.media?.photos?.first?.url ?? tweet.media?.videos?.first?.thumbnailUrl).map(Self.mediumSize)
        avatarURL = tweet.author.avatarUrl
    }

    /// fxtwitter links photos at `?name=orig`, often several megapixels. `medium` is 1200px, plenty for a preview.
    private static func mediumSize(_ url: URL) -> URL {
        guard url.host() == "pbs.twimg.com", var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name == "name" }) == true
        else { return url }
        components.queryItems = components.queryItems?.map { $0.name == "name" ? URLQueryItem(name: "name", value: "medium") : $0 }
        return components.url ?? url
    }

    private struct Response: Decodable {
        let code: Int
        let tweet: Tweet?
    }

    private struct Tweet: Decodable {
        let text: String
        let author: Author
        let media: Media?

        struct Author: Decodable {
            let name: String
            let screenName: String
            let avatarUrl: URL?
        }

        struct Media: Decodable {
            let photos: [Photo]?
            let videos: [Video]?
        }

        struct Photo: Decodable {
            let url: URL
        }

        struct Video: Decodable {
            let thumbnailUrl: URL?
        }
    }
}
