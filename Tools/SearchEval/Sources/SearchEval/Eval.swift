import Accelerate
import Foundation
import GRDB
@testable import StatemonoKit

/// Recall for each tier of the plan, on the test queries, plus the speed of each step.
///
/// Keyword methods return link numbers in the order the app would show them, newest first (links are saved in list
/// order, so a higher number is newer). Vector methods rank every link by similarity.
enum Eval {
    /// One way of making vectors, compared as they are or centered.
    struct Model {
        let name: String
        let embedder: Embedder
        /// Whether the link itself is part of the text, as the plan has it, or only the preview's text.
        let includesLink: Bool
    }

    /// How many related links the combined result shows after the keyword matches.
    static let relatedCount = 3

    static func run(paths: Paths, queriesFile: URL?) async throws {
        let testSet = try TestSet.load(paths, queriesFile: queriesFile)
        let snapshot = try Snapshot.load(paths)
        let tags = (try? Tagger.tags(paths)) ?? [:]
        print("\(snapshot.count) links, \(tags.count) with tags, \(testSet.queries.count) queries")

        let plain = try await Library(snapshot: snapshot, tags: [:])
        let tagged = try await Library(snapshot: snapshot, tags: tags)

        let contextual = try Embedder(.contextual)
        try await contextual.prepare()
        let sentence = try Embedder(.sentence)
        let models = [
            Model(name: "contextual, with link (plan)", embedder: contextual, includesLink: true),
            Model(name: "contextual, preview only", embedder: contextual, includesLink: false),
            Model(name: "sentence, preview only", embedder: sentence, includesLink: false),
        ]
        var spaces: [VectorSpace] = []
        var linkTimes: [Embedder.Kind: [Double]] = [:]
        for model in models {
            var vectors: [Int: [Float]] = [:]
            for entry in snapshot {
                let start = ContinuousClock.now
                vectors[entry.id] = try model.embedder.vector(for: model.includesLink ? entry.document : entry.previewText)
                linkTimes[model.embedder.kind, default: []].append(seconds(since: start))
            }
            spaces.append(VectorSpace(vectors: vectors))
        }

        printSpeed(linkTimes: linkTimes, embedders: [contextual, sentence], plain: plain)
        guard !testSet.queries.isEmpty else {
            print("\nNo queries yet: write them in docs/search-test-links.md, then run eval again.")
            return
        }

        var results: [QueryResult] = []
        for query in testSet.queries {
            var related: [[(id: Int, score: Float)]] = []
            for (model, space) in zip(models, spaces) {
                let vector = try model.embedder.vector(for: query.text)
                related.append(space.similarities(to: vector))
                related.append(space.similarities(to: vector, centered: true))
            }
            results.append(QueryResult(
                query: query,
                keyword: try await plain.keyword(query.text),
                typo: try await plain.keyword(query.text, typos: true),
                tags: try await tagged.keyword(query.text, typos: true),
                related: related
            ))
        }
        report(results, variants: models.flatMap { [$0.name, $0.name + ", centered"] })
    }

    // MARK: - Report

    struct QueryResult {
        let query: TestSet.Query
        let keyword: [Int]
        let typo: [Int]
        let tags: [Int]
        /// Every link by similarity, best first, for each variant.
        let related: [[(id: Int, score: Float)]]

        /// Keyword matches (with typos and tags), then the best related links not already matched.
        func combined(_ variant: Int) -> [Int] {
            tags + related[variant].map(\.id).filter { !tags.contains($0) }.prefix(Eval.relatedCount)
        }

        func rank(_ list: [Int]) -> Int? {
            list.firstIndex(where: query.expected.contains).map { $0 + 1 }
        }
    }

    static func report(_ results: [QueryResult], variants: [String]) {
        func line(_ name: String, _ lists: [[Int]]) {
            let ranks = zip(lists, results).map { $1.rank($0) }
            func within(_ k: Int) -> String { "\(ranks.filter { ($0 ?? .max) <= k }.count)/\(results.count)" }
            let shown = Double(lists.map(\.count).reduce(0, +)) / Double(lists.count)
            print(name.padding(toLength: 50, withPad: " ", startingAt: 0)
                + within(1).padding(toLength: 8, withPad: " ", startingAt: 0)
                + within(5).padding(toLength: 8, withPad: " ", startingAt: 0)
                + within(10).padding(toLength: 8, withPad: " ", startingAt: 0)
                + String(format: "%.1f", shown))
        }

        print("\n== Recall: the expected link first, in the top 5, in the top 10; average results shown")
        print("method".padding(toLength: 50, withPad: " ", startingAt: 0) + "first   top 5   top 10  results")
        line("keywords (today)", results.map(\.keyword))
        line("+ typo tolerance", results.map(\.typo))
        line("+ tags", results.map(\.tags))
        for (index, name) in variants.enumerated() {
            line("+ tags + \(relatedCount) related: \(name)", results.map { $0.combined(index) })
        }
        for (index, name) in variants.enumerated() {
            line("vectors alone: \(name)", results.map { $0.related[index].map(\.id) })
        }

        print("\n== By kind, found in the top 10")
        for kind in Set(results.map(\.query.kind)).sorted() {
            let group = results.filter { $0.query.kind == kind }
            func count(_ list: (QueryResult) -> [Int]) -> Int { group.filter { ($0.rank(list($0)) ?? .max) <= 10 }.count }
            let vectors = variants.indices.map { index in String(count { $0.related[index].map(\.id) }) }
            print("\(kind) (\(group.count)): keywords \(count(\.keyword)), + typos \(count(\.typo)), + tags \(count(\.tags)); vectors alone \(vectors.joined(separator: " / "))")
        }

        print("\n== Do the scores separate right from wrong? (right link scores highest; median right score; median best wrong)")
        for (index, name) in variants.enumerated() {
            var wins = 0
            var right: [Float] = []
            var wrong: [Float] = []
            for result in results {
                let scores = result.related[index]
                let best = scores.first { result.query.expected.contains($0.id) }?.score ?? 0
                let bestWrong = scores.first { !result.query.expected.contains($0.id) }?.score ?? 0
                if best > bestWrong { wins += 1 }
                right.append(best)
                wrong.append(bestWrong)
            }
            print(name.padding(toLength: 40, withPad: " ", startingAt: 0) + "\(wins)/\(results.count)   " + String(format: "%.2f   %.2f", median(right), median(wrong)))
        }

        print("\n== Each query: rank of the expected link (- when missing)")
        print("keywords / + typos / + tags | vectors: " + variants.joined(separator: " / "))
        for result in results {
            func show(_ list: [Int]) -> String { result.rank(list).map(String.init) ?? "-" }
            let vectors = result.related.map { show($0.map(\.id)) }.joined(separator: " / ")
            print("\(result.query.text) → \(result.query.expected.sorted().map(String.init).joined(separator: ",")) [\(result.query.kind)]: \(show(result.keyword)) / \(show(result.typo)) / \(show(result.tags)) | \(vectors)")
        }
    }

    static func median(_ values: [Float]) -> Float {
        values.isEmpty ? 0 : values.sorted()[values.count / 2]
    }

    static func printSpeed(linkTimes: [Embedder.Kind: [Double]], embedders: [Embedder], plain: Library) {
        func ms(_ seconds: Double) -> String { String(format: "%.1fms", seconds * 1000) }
        print("\n== Speed on this Mac")
        for embedder in embedders {
            let times = (linkTimes[embedder.kind] ?? [0]).sorted()
            var queryTimes: [Double] = []
            for text in ["remote desktop", "coffee", "how to get startup ideas", "space telescope photos", "swift"] {
                let start = ContinuousClock.now
                _ = try? embedder.vector(for: text)
                queryTimes.append(seconds(since: start))
            }
            print("\(embedder.kind) (\(embedder.dimension) numbers): link vector median \(ms(times[times.count / 2])), slowest \(ms(times.last ?? 0)); query vector median \(ms(queryTimes.sorted()[queryTimes.count / 2]))")
        }
        for count in [10_000, 50_000] {
            print("comparing a query with \(count) link vectors: \(ms(VectorSpace.bruteForceTime(count: count, dimension: 512)))")
        }
        // A year of links has far more words than the test set, so the same lookup also runs over words from the
        // Mac's dictionary.
        let dictionary = ((try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8)) ?? "")
            .split(separator: "\n").map { $0.lowercased() }.shuffled()
        for (name, entries) in [("the test set's", plain.vocabulary)]
            + [10_000, 50_000].map({ count in ("\(count) dictionary", dictionary.prefix(count).map { (text: $0, documents: 1) }) }) {
            let vocabulary = SearchVocabulary(entries)
            let start = ContinuousClock.now
            let rounds = 10
            for _ in 0..<rounds {
                _ = vocabulary.alternatives(for: "levenshtien", isLast: false)
                _ = vocabulary.alternatives(for: "distanse", isLast: true)
            }
            print("typo alternatives for a two-word query, \(name) words (\(entries.count)): \(ms(seconds(since: start) / Double(rounds)))")
        }
    }
}

// MARK: - Keyword search, with the plan's typo tolerance

/// The test links saved as messages in an in-memory copy of the app's database, with the app's own tokenizer and
/// search index. Tags, when given, are added to the message text, standing in for the plan's `tags` column.
final class Library {
    let database: AppDatabase
    private var linkIDs: [UUID: Int] = [:]
    /// Every folded word in the index, with the number of links it appears in, as the app's search reads it.
    private(set) var vocabulary: [(text: String, documents: Int)] = []

    init(snapshot: [Snapshot.Entry], tags: [Int: [String]]) async throws {
        database = try AppDatabase.inMemory(media: MediaStore(directory: FileManager.default.temporaryDirectory.appending(path: "SearchEval-unused")))
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        for entry in snapshot {
            let text = ([entry.url.absoluteString] + (tags[entry.id] ?? [])).joined(separator: "\n")
            let item = try database.insertItem(text: text, link: entry.url, date: start.addingTimeInterval(Double(entry.id) * 60))
            linkIDs[item.id] = entry.id
            let preview = entry.hasText ? LinkPreview(siteName: entry.siteName, title: entry.title, summary: entry.summary) : nil
            try await database.savePreview(preview, for: item.id)
        }
        vocabulary = try await database.searchVocabulary().words.map { (text: $0.text, documents: $0.documents) }
    }

    /// Link numbers, newest first, from the app's own search (`AppDatabase.search`). Without typos, only the results
    /// that matched as typed, which is the search before Phase 1.
    func keyword(_ query: String, typos: Bool = false) async throws -> [Int] {
        try await database.search(query).items
            .filter { typos || $0.match != .typo }
            .compactMap { linkIDs[$0.id] }
    }
}

// MARK: - Vectors

/// Every link's vector, compared with a query's by dot product. "Centered" subtracts the average link vector first,
/// a common fix when a model's vectors all point roughly the same way and every similarity comes out high.
struct VectorSpace {
    let ids: [Int]
    let vectors: [[Float]]
    let centered: [[Float]]
    let mean: [Float]

    init(vectors: [Int: [Float]]) {
        ids = vectors.keys.sorted()
        self.vectors = ids.map { vectors[$0]! }
        var sum = [Float](repeating: 0, count: self.vectors.first?.count ?? 0)
        for vector in self.vectors { vDSP.add(sum, vector, result: &sum) }
        mean = vDSP.divide(sum, Float(self.vectors.count))
        centered = self.vectors.map { [mean] vector in Embedder.normalized(vDSP.subtract(vector, mean)) }
    }

    func similarities(to query: [Float], centered useCentered: Bool = false) -> [(id: Int, score: Float)] {
        let target = useCentered ? Embedder.normalized(vDSP.subtract(query, mean)) : query
        let pool = useCentered ? centered : vectors
        return zip(ids, pool).map { ($0, vDSP.dot($1, target)) }.sorted { $0.score > $1.score }
    }

    /// Median time to score one query against `count` random vectors in one matrix multiply, as the app would.
    static func bruteForceTime(count: Int, dimension: Int) -> Double {
        let matrix = (0..<(count * dimension)).map { _ in Float.random(in: -1...1) }
        let query = (0..<dimension).map { _ in Float.random(in: -1...1) }
        var scores = [Float](repeating: 0, count: count)
        var times: [Double] = []
        for _ in 0..<15 {
            let start = ContinuousClock.now
            vDSP_mmul(matrix, 1, query, 1, &scores, 1, vDSP_Length(count), 1, vDSP_Length(dimension))
            times.append(seconds(since: start))
        }
        return times.sorted()[times.count / 2]
    }
}
