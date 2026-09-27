import Foundation
import ImageIO
import Testing
@testable import StatemonoKit

struct LinkPreviewFetcherTests {
    @Test(arguments: [
        // (og:type, twitter:card, has description, host, image width, expected)
        (nil, "summary_large_image", true, "scriptc.dev", 1200, true),   // the page asks for a big card
        ("article", "summary", true, "blog.example.com", 1200, false),   // article with text: small thumbnail
        ("website", nil, false, "example.com", 800, true),               // no description: large
        ("video.other", nil, true, "vimeo.com", 1280, true),             // video pages: large
        (nil, nil, true, "www.instagram.com", 1080, true),               // Instagram: large
        (nil, "summary_large_image", true, "example.com", 150, false),   // under 200px: always small
    ] as [(String?, String?, Bool, String, CGFloat, Bool)])
    func `sizes images like Telegram`(type: String?, card: String?, hasDescription: Bool, host: String, width: CGFloat, large: Bool) {
        let page = PageMetadata(description: hasDescription ? "text" : nil, type: type, twitterCard: card)
        #expect(LinkPreviewFetcher.showsLargeImage(page: page, host: host, imagePixelWidth: width) == large)
    }

    @Test func `shortens long summaries at a word`() {
        let long = String(repeating: "word ", count: 200)
        let short = LinkPreviewFetcher.truncated(long)
        #expect(short.count <= LinkPreviewFetcher.maxSummaryLength + 1)
        #expect(short.hasSuffix("word…"))
        #expect(LinkPreviewFetcher.truncated("Short enough.") == "Short enough.")
    }

    @Test func `names sites without www`() {
        #expect(LinkPreviewFetcher.displayHost(URL(string: "https://www.sqlite.org/fts5.html")!) == "sqlite.org")
        #expect(LinkPreviewFetcher.displayHost(URL(string: "https://docs.github.com")!) == "docs.github.com")
    }
}
