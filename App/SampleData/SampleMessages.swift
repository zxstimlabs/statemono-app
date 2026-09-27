import Foundation

/// Mock feed that mirrors the Telegram screenshot the UI was built from. The two images are cropped from it.
/// Delete this folder once the feed reads from the database.
enum SampleMessages {
    static func make(now: Date = .now, calendar: Calendar = .current) -> [Message] {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        func at(_ hour: Int, _ minute: Int, on day: Date = now) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func image(_ name: String, aspectRatio: CGFloat) -> PreviewImage? {
            Bundle.main.url(forResource: name, withExtension: "png").map { PreviewImage(url: $0, aspectRatio: aspectRatio) }
        }

        return [
            Message(
                id: UUID(),
                text: "https://github.com/groue/GRDB.swift",
                date: at(9, 41, on: yesterday),
                preview: LinkPreview(
                    siteName: "GitHub",
                    title: "GitHub - groue/GRDB.swift: A toolkit for SQLite databases, with a focus on application development",
                    summary: "A toolkit for SQLite databases, with a focus on application development - groue/GRDB.swift"
                )
            ),
            Message(
                id: UUID(),
                text: "https://www.sqlite.org/fts5.html",
                date: at(9, 43, on: yesterday),
                preview: LinkPreview(siteName: "SQLite", title: "SQLite FTS5 Extension")
            ),
            Message(
                id: UUID(),
                text: "FTS5 strips tone marks but keeps đ, so \"duong\" won't find \"đường\". Needs a wrapper tokenizer.",
                date: at(21, 7, on: yesterday)
            ),
            Message(
                id: UUID(),
                text: """
                Before the weekend:
                - share the globalcard llc docs
                - set up the App Group before the share extension
                - decide on sync before it quietly slips another month
                """,
                date: at(12, 15)
            ),
            Message(
                id: UUID(),
                text: "https://x.com/brankopetric00/status/2103944884449382629?s=46&t=U3BTMI1LgUvDKo6q-PxApw",
                date: at(14, 25),
                preview: LinkPreview(
                    siteName: "X (formerly Twitter)",
                    title: "Branko (@brankopetric00) on X",
                    summary: """
                    Inspired by @tobi and his datatree I built the same thing but for AWS billing.

                    It shows per resource breakdown and you can export JSON and ask your AI agent to review.
                    """,
                    image: image("sample-awstree", aspectRatio: 533.0 / 316.0)
                )
            ),
            Message(
                id: UUID(),
                text: "https://scriptc.dev/",
                date: at(15, 15),
                preview: LinkPreview(
                    siteName: "scriptc",
                    title: "scriptc | TypeScript-to-Native Compiler",
                    summary: "scriptc compiles ordinary TypeScript into small, fast native executables — no Node, no V8, no JavaScript engine in the binary. Same code, checked by the real TypeScript compiler, compiled to native.",
                    image: image("sample-scriptc", aspectRatio: 533.0 / 276.0)
                )
            ),
        ]
    }
}
