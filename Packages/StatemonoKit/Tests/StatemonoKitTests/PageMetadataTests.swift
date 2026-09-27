import Foundation
import Testing
@testable import StatemonoKit

struct PageMetadataTests {
    let base = URL(string: "https://example.com/blog/post")!

    @Test func `reads OpenGraph tags`() {
        let html = """
        <html><head>
        <title>Ignored when og:title exists</title>
        <meta property="og:site_name" content="scriptc"/>
        <meta property="og:title" content="scriptc | TypeScript-to-Native Compiler"/>
        <meta property="og:description" content="Small, fast native executables."/>
        <meta property="og:image" content="https://scriptc.dev/og"/>
        <meta property="og:type" content="website"/>
        <meta name="twitter:card" content="summary_large_image"/>
        </head><body></body></html>
        """
        let page = PageMetadata(html: html, baseURL: base)
        #expect(page == PageMetadata(
            siteName: "scriptc",
            title: "scriptc | TypeScript-to-Native Compiler",
            description: "Small, fast native executables.",
            imageURL: URL(string: "https://scriptc.dev/og"),
            type: "website",
            twitterCard: "summary_large_image"
        ))
    }

    @Test func `falls back to Twitter tags, then the plain title and description`() {
        let twitter = PageMetadata(html: """
        <head><meta name="twitter:title" content="Card title"><meta name="twitter:description" content="Card text">
        <meta name="twitter:image:src" content="/card.png"></head>
        """, baseURL: base)
        #expect(twitter.title == "Card title")
        #expect(twitter.description == "Card text")
        #expect(twitter.imageURL == URL(string: "https://example.com/card.png"))

        let plain = PageMetadata(html: """
        <head><title>
          SQLite FTS5 Extension
        </title><meta name="description" content="Full-text search."></head>
        """, baseURL: base)
        #expect(plain.title == "SQLite FTS5 Extension")
        #expect(plain.description == "Full-text search.")
        #expect(plain.siteName == nil)
        #expect(plain.imageURL == nil)
    }

    @Test(arguments: [
        ("image.jpg", "https://example.com/blog/image.jpg"),
        ("/static/image.jpg", "https://example.com/static/image.jpg"),
        ("//cdn.example.net/image.jpg", "https://cdn.example.net/image.jpg"),
        ("https://other.org/a b.jpg", "https://other.org/a%20b.jpg"),
    ])
    func `resolves image URLs against the page`(raw: String, expected: String) {
        let page = PageMetadata(html: "<head><meta property='og:image' content='\(raw)'></head>", baseURL: base)
        #expect(page.imageURL?.absoluteString == expected)
    }

    @Test func `ignores non-web image URLs`() {
        let page = PageMetadata(html: #"<head><meta property="og:image" content="data:image/png;base64,AAAA"></head>"#, baseURL: base)
        #expect(page.imageURL == nil)
    }

    @Test func `decodes entities and collapses whitespace`() {
        let page = PageMetadata(html: """
        <head><meta content="Tom &amp; Jerry&#39;s &#x2014; &quot;best&quot;
            of&nbsp;&hellip;" property="og:title"></head>
        """, baseURL: base)
        #expect(page.title == "Tom & Jerry's — \"best\" of …")
    }

    @Test func `keeps the first value and only reads the head`() {
        let page = PageMetadata(html: """
        <head><meta property="og:title" content="First"><meta property="og:title" content="Second"></head>
        <body><meta property="og:description" content="From the body"></body>
        """, baseURL: base)
        #expect(page.title == "First")
        #expect(page.description == nil)
    }

    @Test func `decodes the page's declared charset`() {
        let latin1 = "<head><meta charset=\"iso-8859-1\"><title>Café</title></head>".data(using: .isoLatin1)!
        #expect(LinkPreviewFetcher.decodeText(latin1, encodingName: nil).contains("Café"))
        let utf8 = Data("<head><title>Đường</title></head>".utf8)
        #expect(LinkPreviewFetcher.decodeText(utf8, encodingName: "utf-8").contains("Đường"))
    }
}
