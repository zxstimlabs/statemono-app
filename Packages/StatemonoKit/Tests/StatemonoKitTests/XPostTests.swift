import Foundation
import Testing
@testable import StatemonoKit

struct XPostTests {
    @Test(arguments: [
        "https://x.com/brankopetric00/status/2103944884449382629?s=46&t=U3BTMI1LgUvDKo6q-PxApw",
        "https://twitter.com/brankopetric00/status/2103944884449382629",
        "https://mobile.twitter.com/brankopetric00/status/2103944884449382629/photo/1",
        "https://www.x.com/i/status/2103944884449382629",
        "https://x.com/i/web/status/2103944884449382629#reply",
        "https://fxtwitter.com/brankopetric00/status/2103944884449382629",
    ])
    func `recognizes post links`(link: String) throws {
        let post = try #require(XPost(url: URL(string: link)!))
        #expect(post.id == "2103944884449382629")
        #expect(post.apiURL.absoluteString == "https://api.fxtwitter.com/status/2103944884449382629")
    }

    @Test(arguments: [
        "https://x.com/brankopetric00",
        "https://x.com/search?q=swift",
        "https://x.com/brankopetric00/status/",
        "https://x.com/brankopetric00/status/abc",
        "https://example.com/brankopetric00/status/2103944884449382629",
    ])
    func `ignores other links`(link: String) {
        #expect(XPost(url: URL(string: link)!) == nil)
    }

    @Test func `reads a post from fxtwitter`() throws {
        let content = try XPostContent(fxTwitterJSON: Data(Self.fixture.utf8))
        #expect(content.title == "Branko (@brankopetric00) on X")
        #expect(content.text.hasPrefix("Inspired by @tobi"))
        #expect(content.mediaURL?.absoluteString == "https://pbs.twimg.com/media/HTK2a1qWoAAa45G.jpg?name=medium")
        #expect(content.avatarURL?.absoluteString == "https://pbs.twimg.com/profile_images/1836534038149955584/2dxKOQuW_200x200.jpg")
    }

    @Test func `fails on a missing post`() {
        #expect(throws: LinkPreviewError.badStatus(404)) {
            try XPostContent(fxTwitterJSON: Data(#"{"code": 404, "message": "NOT_FOUND", "tweet": null}"#.utf8))
        }
    }

    /// Trimmed from a real api.fxtwitter.com response.
    static let fixture = """
    {
      "code": 200, "message": "OK",
      "tweet": {
        "id": "2103944884449382629",
        "text": "Inspired by @tobi and his datatree I built the same thing but for AWS billing.\\n\\nIt shows per resource breakdown and you can export JSON and ask your AI agent to review.",
        "author": {
          "screen_name": "brankopetric00", "name": "Branko",
          "avatar_url": "https://pbs.twimg.com/profile_images/1836534038149955584/2dxKOQuW_200x200.jpg"
        },
        "media": {
          "photos": [{"type": "photo", "url": "https://pbs.twimg.com/media/HTK2a1qWoAAa45G.jpg?name=orig", "width": 2880, "height": 1720}]
        }
      }
    }
    """
}
