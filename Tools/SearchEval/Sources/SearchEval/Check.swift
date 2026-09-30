import CoreML
import Embeddings
import Foundation
@testable import StatemonoKit

/// Checks the app's own bge-small (`BertEmbedder`, Accelerate) against swift-embeddings' (MLTensor), which `eval`
/// measured: every link's and query's tokens must match, and their vectors must agree. Then it times the app's, and with
/// `--download` installs the model the way the app does (`SearchModelStore`) into a temporary folder.
enum Check {
    static func run(paths: Paths, download: Bool) async throws {
        let snapshot = try Snapshot.load(paths)
        let smoke = (try? TestSet(markdown: "", queriesMarkdown: String(contentsOf: paths.tool.appending(path: "Data/smoke-queries.md"), encoding: .utf8)).queries) ?? []
        let queries = try TestSet.load(paths).queries.map(\.text) + smoke.map(\.text)
        let texts = snapshot.map { (AppDatabase.vectorText(title: $0.title, siteName: $0.siteName, summary: $0.summary, text: $0.url.absoluteString), TextRole.document) }
            + queries.map { ($0, TextRole.query) }
            // Accents, punctuation, CJK, and a long run of text that has to be cut at 512 tokens.
            + [("Café naïve — “quoted” $5.00 @user #tag 東京 강남스타일 Ωμέγα", .document), (String(repeating: "levenshtein distance ", count: 300), .document)]

        let app = try BertEmbedder(directory: paths.models.appending(path: "models/BAAI/bge-small-en-v1.5"), model: .bgeSmall)
        let reference = try await Bert.loadModelBundle(from: "BAAI/bge-small-en-v1.5", downloadBase: paths.models)
        var options = reference.defaultEncodeOptions
        options.postProcess = .clsTokenPool(normalize: true)
        options.maxLength = 512
        options.computePolicy = MLComputePolicy(.cpuOnly)
        let prefix = "Represent this sentence for searching relevant passages: "

        var tokenMismatches = 0
        var lowest: Float = 1
        for (text, role) in texts {
            let input = (role == .query ? prefix : "") + text
            let expected = try reference.tokenizer.tokenizeText(input, maxLength: 512)
            let tokens = app.tokenIDs(for: text, role: role)
            if tokens != expected {
                tokenMismatches += 1
                if tokenMismatches <= 5 { print("tokens differ for \(input.prefix(40))…: app \(tokens.count), ending \(tokens.suffix(4)); reference \(expected.count), ending \(expected.suffix(4))") }
            }
            let mine = app.vector(for: text, role: role)
            let theirs = await (try reference.encode(input, options: options)).cast(to: Float.self).shapedArray(of: Float.self).scalars
            let similarity = zip(mine, theirs).map(*).reduce(0, +)
            if similarity < 0.9999 { print(String(format: "cosine %.6f (%d tokens) for \(input.prefix(40))…", similarity, tokens.count)) }
            lowest = min(lowest, similarity)
        }
        print("\(texts.count) texts: tokens differ for \(tokenMismatches); lowest cosine similarity between the two vectors \(String(format: "%.6f", lowest))")

        var linkTimes: [Double] = []
        for (text, role) in texts where role == .document {
            let start = ContinuousClock.now
            _ = app.vector(for: text, role: role)
            linkTimes.append(seconds(since: start))
        }
        var queryTimes: [Double] = []
        for query in queries {
            let start = ContinuousClock.now
            _ = app.vector(for: query, role: .query)
            queryTimes.append(seconds(since: start))
        }
        print(String(format: "app's model on this Mac: link median %.1fms, slowest %.1fms; query median %.1fms",
                     Eval.median(linkTimes) * 1000, (linkTimes.max() ?? 0) * 1000, Eval.median(queryTimes) * 1000))

        guard download else { return }
        let folder = FileManager.default.temporaryDirectory.appending(path: "SearchEval-model-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SearchModelStore(model: .bgeSmall, base: folder)
        let reports = Reports()
        let start = ContinuousClock.now
        try await store.install { reports.add($0) }
        let installed = try store.load()
        let same = installed.vector(for: "graduation speech", role: .query) == app.vector(for: "graduation speech", role: .query)
        print(String(format: "downloaded in %.1fs, %d progress reports, installed: \(store.isInstalled), same vectors: \(same), %.0f MB on disk",
                     seconds(since: start), reports.count, Double(store.sizeOnDisk) / 1_000_000))
    }
}

private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func add(_ value: Double) {
        lock.withLock { values.append(value) }
    }

    var count: Int { lock.withLock { values.count } }
}
