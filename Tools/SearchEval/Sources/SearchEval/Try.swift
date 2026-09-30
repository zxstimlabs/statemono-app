import Foundation

/// Searches the test links for one query, to test by hand: the matches the app finds today (keywords, typos, and
/// tags), then the closest links by meaning for each model, marking the ones Smart Search would add.
enum Try {
    /// Apple's model, which the plan started with, and the app's bge-small.
    static let defaultModels = ["apple", "app"]

    static func run(paths: Paths, query: String, models names: [String]) async throws {
        let snapshot = try Snapshot.load(paths)
        let entries = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
        let tags = (try? Tagger.tags(paths)) ?? [:]
        let library = try await Library(snapshot: snapshot, tags: tags)

        func describe(_ id: Int) -> String {
            guard let entry = entries[id] else { return "#\(id)" }
            let title = [entry.title, entry.siteName].compactMap { $0 }.joined(separator: " · ")
            return "#\(id)".padding(toLength: 5, withPad: " ", startingAt: 0) + (title.isEmpty ? entry.url.absoluteString : title)
        }

        let matches = try await library.keyword(query, typos: true)
        print("\"\(query)\"\n\nMatches, newest first (keywords, typos and tags): \(matches.isEmpty ? "none" : String(matches.count))")
        for id in matches.prefix(10) { print("  " + describe(id)) }
        if matches.count > 10 { print("  …") }

        let wanted = names.isEmpty ? defaultModels : names
        // Of Apple's models, only the plan's: the contextual one, with the link, centered.
        let models = try await Eval.models(paths: paths, only: wanted)
            .filter { !$0.name.hasPrefix("apple") || $0.name.hasSuffix("(plan)") }
        for model in models {
            var vectors: [Int: [Float]] = [:]
            for entry in snapshot {
                vectors[entry.id] = try await model.embedder.vector(for: model.includesLink ? entry.document : entry.previewText, role: .document)
            }
            let centered = model.name.hasPrefix("apple")
            let query = try await model.embedder.vector(for: query, role: .query)
            let ranked = VectorSpace(vectors: vectors).similarities(to: query, centered: centered)
            let added = Set(ranked.map(\.id).filter { !matches.contains($0) }.prefix(Eval.relatedCount))
            print("\nClosest by meaning, \(model.name)\(centered ? ", centered" : ""). → marks the \(Eval.relatedCount) Smart Search would add:")
            for hit in ranked.prefix(8) {
                let mark = added.contains(hit.id) ? "→" : matches.contains(hit.id) ? "=" : " "
                print("\(mark) " + String(format: "%.2f  ", hit.score) + describe(hit.id))
            }
        }
        print("\n= already a match. Models: apple, app, " + OpenModel.all.map(\.name).joined(separator: ", ") + ".")
    }
}
