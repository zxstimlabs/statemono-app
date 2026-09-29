import Foundation

/// The links and queries in docs/search-test-links.md, read from its tables.
struct TestSet {
    struct Link: Codable {
        let id: Int
        let url: URL
        let about: String
    }

    struct Query {
        let text: String
        let expected: Set<Int>
        let kind: String
    }

    let links: [Link]
    let queries: [Query]

    /// Links come from rows like `| 12 | https://… | What it is |`, queries from the table under "## Queries".
    init(markdown: String, queriesMarkdown: String? = nil) {
        links = markdown.split(separator: "\n").compactMap { line in
            let cells = Self.cells(line)
            guard cells.count == 3, let id = Int(cells[0]), let url = URL(string: cells[1]), url.scheme != nil else { return nil }
            return Link(id: id, url: url, about: cells[2])
        }
        queries = Self.queries(in: queriesMarkdown ?? markdown)
    }

    private static func queries(in markdown: String) -> [Query] {
        let section = markdown.components(separatedBy: "## Queries").dropFirst().first?.components(separatedBy: "\n## ").first ?? ""
        return section.split(separator: "\n").compactMap { line in
            let cells = cells(line)
            guard cells.count == 3, !cells[0].isEmpty, cells[0] != "Query", !cells[0].hasPrefix("---") else { return nil }
            let expected = Set(cells[1].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) })
            guard !expected.isEmpty else { return nil }
            return Query(text: cells[0], expected: expected, kind: cells[2].lowercased())
        }
    }

    private static func cells(_ line: Substring) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return [] }
        return trimmed.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func load(_ paths: Paths, queriesFile: URL? = nil) throws -> TestSet {
        let markdown = try String(contentsOf: paths.testSet, encoding: .utf8)
        let queries = try queriesFile.map { try String(contentsOf: $0, encoding: .utf8) }
        return TestSet(markdown: markdown, queriesMarkdown: queries)
    }
}
