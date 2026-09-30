import Accelerate
import Foundation
import GRDB
@testable import StatemonoKit

/// Recall for each tier of the plan, on the test queries, plus the speed of each step.
///
/// Keyword methods return link numbers in the order the app would show them, newest first (links are saved in list
/// order, so a higher number is newer). Vector methods rank every link by similarity.
enum Eval {
    /// One way of making vectors: a model, and the text it's given.
    struct Model {
        let name: String
        let embedder: any EvalEmbedder
        /// Whether the link itself is part of the text, as the plan has it, or only the preview's text.
        let includesLink: Bool
        /// The open models' download size; Apple's is managed by the system.
        var megabytes: Double?
    }

    /// A model's vectors for every link, compared as they are or centered.
    struct Variant {
        let name: String
        let megabytes: Double?
        let linkTime: Double
        let queryTime: Double
    }

    /// How many related links the combined result shows after the keyword matches.
    static let relatedCount = 3

    /// Apple's two models, as in the first Phase 0 runs, then the open models: all of them, or those named.
    static func models(paths: Paths, only names: [String]) async throws -> [Model] {
        var models: [Model] = []
        if names.isEmpty || names.contains("apple") {
            let contextual = try Embedder(.contextual)
            try await contextual.prepare()
            let sentence = try Embedder(.sentence)
            models += [
                Model(name: "apple contextual, with link (plan)", embedder: contextual, includesLink: true),
                Model(name: "apple contextual, preview only", embedder: contextual, includesLink: false),
                Model(name: "apple sentence, preview only", embedder: sentence, includesLink: false),
            ]
        }
        // The app's own bge-small (`BertEmbedder`), reading the files swift-embeddings downloads for "bge-small".
        if names.isEmpty || names.contains("app") {
            do {
                let embedder = try BertEmbedder(directory: paths.models.appending(path: "models/BAAI/bge-small-en-v1.5"), model: .bgeSmall)
                models.append(Model(name: "app (bge-small)", embedder: embedder, includesLink: true, megabytes: Double(SearchModel.bgeSmall.downloadSize) / 1_000_000))
            } catch {
                print("skipped the app's model: run eval with --model bge-small once to download it (\(error))")
            }
        }
        for open in OpenModel.all where names.isEmpty || names.contains(open.name) {
            do {
                let embedder = try await OpenEmbedder(open, paths: paths)
                models.append(Model(name: open.name, embedder: embedder, includesLink: true, megabytes: embedder.megabytes))
            } catch {
                print("skipped \(open.name) (\(open.repo)): \(error)")
            }
        }
        return models
    }

    static func run(paths: Paths, queriesFile: URL?, only names: [String]) async throws {
        let testSet = try TestSet.load(paths, queriesFile: queriesFile)
        let snapshot = try Snapshot.load(paths)
        let tags = (try? Tagger.tags(paths)) ?? [:]
        print("\(snapshot.count) links, \(tags.count) with tags, \(testSet.queries.count) queries")

        let plain = try await Library(snapshot: snapshot, tags: [:])
        let tagged = try await Library(snapshot: snapshot, tags: tags)
        let models = try await models(paths: paths, only: names)

        guard !testSet.queries.isEmpty else {
            print("\nNo queries yet: write them in docs/search-test-links.md, then run eval again.")
            return
        }

        var results = try await testSet.queries.asyncMap { query in
            QueryResult(
                query: query,
                keyword: try await plain.keyword(query.text),
                typo: try await plain.keyword(query.text, typos: true),
                tags: try await tagged.keyword(query.text, typos: true),
                related: []
            )
        }
        var variants: [Variant] = []
        for model in models {
            var vectors: [Int: [Float]] = [:]
            var linkTimes: [Double] = []
            for entry in snapshot {
                let start = ContinuousClock.now
                vectors[entry.id] = try await model.embedder.vector(for: model.includesLink ? entry.document : entry.previewText, role: .document)
                linkTimes.append(seconds(since: start))
            }
            let space = VectorSpace(vectors: vectors)
            var queryTimes: [Double] = []
            for index in results.indices {
                let start = ContinuousClock.now
                let vector = try await model.embedder.vector(for: results[index].query.text, role: .query)
                queryTimes.append(seconds(since: start))
                results[index].related.append(space.similarities(to: vector))
                results[index].related.append(space.similarities(to: vector, centered: true))
            }
            let linkTime = median(linkTimes)
            let queryTime = median(queryTimes)
            variants.append(Variant(name: model.name, megabytes: model.megabytes, linkTime: linkTime, queryTime: queryTime))
            variants.append(Variant(name: model.name + ", centered", megabytes: model.megabytes, linkTime: linkTime, queryTime: queryTime))
        }
        report(results, variants: variants)
        printSpeed(plain: plain)
    }

    // MARK: - Report

    struct QueryResult {
        let query: TestSet.Query
        let keyword: [Int]
        let typo: [Int]
        let tags: [Int]
        /// Every link by similarity, best first, for each variant.
        var related: [[(id: Int, score: Float)]]

        /// Keyword matches (with typos and tags), then the best related links not already matched.
        func combined(_ variant: Int) -> [Int] {
            tags + related[variant].map(\.id).filter { !tags.contains($0) }.prefix(Eval.relatedCount)
        }

        func rank(_ list: [Int]) -> Int? {
            list.firstIndex(where: query.expected.contains).map { $0 + 1 }
        }

        /// Whether the right link scored higher than every wrong one.
        func rightScoresHighest(_ variant: Int) -> Bool {
            related[variant].first.map { query.expected.contains($0.id) } ?? false
        }
    }

    static func report(_ results: [QueryResult], variants: [Variant]) {
        func within(_ k: Int, _ lists: [[Int]], _ group: [QueryResult] = results) -> Int {
            zip(lists, group).filter { ($1.rank($0) ?? .max) <= k }.count
        }
        func pad(_ text: String, _ width: Int) -> String { text.padding(toLength: width, withPad: " ", startingAt: 0) }
        let total = results.count

        print("\n== Keyword search: the expected link first, in the top 5, in the top 10 (of \(total)); average results shown")
        for (name, lists) in [("keywords", results.map(\.keyword)), ("+ typo tolerance (built)", results.map(\.typo)), ("+ tags", results.map(\.tags))] {
            let shown = Double(lists.map(\.count).reduce(0, +)) / Double(total)
            print(pad(name, 28) + pad("\(within(1, lists))", 6) + pad("\(within(5, lists))", 6) + pad("\(within(10, lists))", 6) + String(format: "%.1f", shown))
        }

        let meaning = results.filter { $0.query.kind == "meaning" }
        struct Row {
            let index: Int
            let combinedFirst: Int, combinedTop5: Int, meaningFound: Int
            let aloneFirst: Int, aloneTop5: Int, aloneTop10: Int, highest: Int
        }
        let rows = variants.indices.map { index in
            let alone = results.map { $0.related[index].map(\.id) }
            let combined = results.map { $0.combined(index) }
            return Row(
                index: index,
                combinedFirst: within(1, combined),
                combinedTop5: within(5, combined),
                meaningFound: zip(meaning.map { $0.combined(index) }, meaning).filter { $1.rank($0) != nil }.count,
                aloneFirst: within(1, alone),
                aloneTop5: within(5, alone),
                aloneTop10: within(10, alone),
                highest: results.filter { $0.rightScoresHighest(index) }.count
            )
        }.sorted { ($0.meaningFound, $0.combinedTop5, $0.aloneTop10) > ($1.meaningFound, $1.combinedTop5, $1.aloneTop10) }

        print("\n== Vector models, best first. \"+ \(relatedCount) related\": tags and typos, then the \(relatedCount) best links they missed (first, top 5).")
        print("   \"meaning\": meaning queries found at all (of \(meaning.count)). \"alone\": every link by similarity (first, top 5, top 10).")
        print("   \"best\": the right link scored highest. MB: download. Times: median on this Mac, per link and per query.")
        print(pad("model", 38) + pad("MB", 6) + pad("+related", 10) + pad("meaning", 9) + pad("alone", 13) + pad("best", 6) + "link / query")
        for row in rows {
            let variant = variants[row.index]
            print(pad(variant.name, 38)
                + pad(variant.megabytes.map { String(format: "%.0f", $0) } ?? "-", 6)
                + pad("\(row.combinedFirst) \(row.combinedTop5)", 10)
                + pad("\(row.meaningFound)", 9)
                + pad("\(row.aloneFirst) \(row.aloneTop5) \(row.aloneTop10)", 13)
                + pad("\(row.highest)", 6)
                + String(format: "%.1f / %.1fms", variant.linkTime * 1000, variant.queryTime * 1000))
        }

        // The rest compares the plan's Apple model with the best few, so it stays readable.
        let plan = variants.firstIndex { $0.name.hasSuffix("(plan), centered") }
        let shown = Array(([plan].compactMap { $0 } + rows.map(\.index)).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.prefix(4))

        print("\n== By kind, found in the top 10: keywords / + typos / + tags; vectors alone: " + shown.map { variants[$0].name }.joined(separator: " / "))
        for kind in Set(results.map(\.query.kind)).sorted() {
            let group = results.filter { $0.query.kind == kind }
            let vectors = shown.map { index in String(within(10, group.map { $0.related[index].map(\.id) }, group)) }
            print("\(kind) (\(group.count)): \(within(10, group.map(\.keyword), group)) / \(within(10, group.map(\.typo), group)) / \(within(10, group.map(\.tags), group)); \(vectors.joined(separator: " / "))")
        }

        print("\n== Each query: rank of the expected link (- when missing): keywords / + typos / + tags | vectors alone: " + shown.map { variants[$0].name }.joined(separator: " / "))
        for result in results {
            func show(_ list: [Int]) -> String { result.rank(list).map(String.init) ?? "-" }
            let vectors = shown.map { show(result.related[$0].map(\.id)) }.joined(separator: " / ")
            print("\(result.query.text) → \(result.query.expected.sorted().map(String.init).joined(separator: ",")) [\(result.query.kind)]: \(show(result.keyword)) / \(show(result.typo)) / \(show(result.tags)) | \(vectors)")
        }
    }

    static func median(_ values: [Float]) -> Float {
        values.isEmpty ? 0 : values.sorted()[values.count / 2]
    }

    static func median(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.sorted()[values.count / 2]
    }

    static func printSpeed(plain: Library) {
        func ms(_ seconds: Double) -> String { String(format: "%.1fms", seconds * 1000) }
        print("\n== Speed on this Mac")
        for dimension in [384, 512, 768] {
            for count in [10_000, 50_000] {
                print("comparing a query with \(count) link vectors of \(dimension) numbers: \(ms(VectorSpace.bruteForceTime(count: count, dimension: dimension)))")
            }
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

extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self { results.append(try await transform(element)) }
        return results
    }
}
