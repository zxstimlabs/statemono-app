import Foundation

// Phase 0 of docs/search-plan.md. Every command reads docs/search-test-links.md and writes to Data/.
//
//   probe     Checks what only a run can: Apple's English text model and Apple Intelligence, from a command line.
//   snapshot  Fetches each link's preview once, with the app's fetcher, into Data/snapshot.json. `--refresh` fetches
//             them all again.
//   tag       Asks Apple Intelligence for tags, into Data/tags.json: links not tried yet, or `--all` to re-tag every
//             link, or `--link <number>` to re-tag one.
//   eval      Measures recall for each tier, plus speed, with Apple's models and the open ones in OpenModels.swift.
//             `--queries <file>` reads the queries from another file; `--model <name>`, repeatable, compares only
//             those models ("apple" for Apple's, "app" for the app's own bge-small).
//   check     Checks the app's own bge-small against swift-embeddings': same tokens, same vectors, and its speed.
//             `--download` also installs the model as the app does, into a temporary folder.
//   try       Searches the test links for one query, to test by hand: today's matches, then the closest links by
//             meaning for Apple's model and the app's bge-small, or the models named with `--model`.

let arguments = Array(CommandLine.arguments.dropFirst())
let paths = Paths()

do {
    switch arguments.first {
    case "probe":
        try await Probe.run()
    case "snapshot":
        try await Snapshot.run(paths: paths, refresh: arguments.contains("--refresh"))
    case "tag":
        let scope: Tagger.Scope = if arguments.contains("--all") {
            .all
        } else if let index = arguments.firstIndex(of: "--link"), index + 1 < arguments.count, let id = Int(arguments[index + 1]) {
            .link(id)
        } else {
            .untried
        }
        try await Tagger.run(paths: paths, scope: scope)
    case "eval":
        let queriesFile = arguments.firstIndex(of: "--queries").map { URL(fileURLWithPath: arguments[$0 + 1]) }
        try await Eval.run(paths: paths, queriesFile: queriesFile, only: values(of: "--model"))
    case "check":
        try await Check.run(paths: paths, download: arguments.contains("--download"))
    case "try":
        guard let query = arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) else {
            print("usage: swift run SearchEval try \"<query>\" [--model <name>]…")
            exit(2)
        }
        try await Try.run(paths: paths, query: query, models: values(of: "--model"))
    default:
        print("usage: swift run SearchEval probe | snapshot [--refresh] | tag [--all | --link <number>] | eval [--queries <file>] [--model <name>]… | check [--download] | try \"<query>\" [--model <name>]…")
        exit(2)
    }
} catch {
    print("error: \(error)")
    exit(1)
}

/// Every value given after `flag`, for options that can repeat.
func values(of flag: String) -> [String] {
    arguments.indices.filter { arguments[$0] == flag && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
}

/// Where the test set and the outputs live, found from this source file so the tool runs from any folder.
struct Paths {
    let tool = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var testSet: URL { tool.appending(path: "../../docs/search-test-links.md").standardizedFileURL }
    var snapshot: URL { tool.appending(path: "Data/snapshot.json") }
    var tags: URL { tool.appending(path: "Data/tags.json") }
    /// Open models downloaded from Hugging Face, ignored by git.
    var models: URL { tool.appending(path: "Data/Models") }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

/// Seconds since `start`, for timings.
func seconds(since start: ContinuousClock.Instant) -> Double {
    let duration = ContinuousClock.now - start
    return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
