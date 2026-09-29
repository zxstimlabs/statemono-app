import Foundation
import FoundationModels

@Generable
struct LinkTags {
    @Guide(description: "Short lowercase keywords for what the link is about, without # symbols", .count(3...8))
    var tags: [String]
}

/// The plan's Apple Intelligence tags: 3–8 per link from the content-tagging model, one link at a time. As in the plan,
/// each link is tagged once; re-tagging everything, or one link, is asked for explicitly.
enum Tagger {
    /// Tags exist so keyword search finds related words, so they ask for topics beyond the page's own words.
    static let instructions = """
        Tag a saved web link so it can be found by searching later. Give 3 to 8 short lowercase keywords: what it is \
        about, its broader topics, and related words someone might search for that aren't in the text. Write every tag in \
        English, whatever the language of the text.
        """

    enum Scope {
        /// Links never tried. A link the model refused was tried, so it isn't retried: the plan's `tagsAttemptedAt`.
        case untried
        /// Every link: the plan's Re-tag All.
        case all
        /// One link: the plan's Re-tag in a message's Tags sheet.
        case link(Int)
    }

    struct Output: Codable {
        var instructions: String
        var entries: [Entry]
    }

    struct Entry: Codable {
        let id: Int
        var tags: [String]?
        /// Why the last try gave no tags. A re-tag that fails keeps the tags from before.
        var problem: String?
        var seconds: Double
        /// The plan's `tagsAttemptedAt`.
        var attemptedAt: Date?
        /// The plan's `tagsOSVersion`: the model has no version of its own, and it updates with the OS.
        var osVersion: String?
    }

    static func run(paths: Paths, scope: Scope) async throws {
        let model = SystemLanguageModel(useCase: .contentTagging)
        guard case .available = model.availability else {
            print("Apple Intelligence isn't available: \(model.availability)")
            return
        }
        var entries = Dictionary(uniqueKeysWithValues: ((try? load(paths).entries) ?? []).map { ($0.id, $0) })
        let snapshot = try Snapshot.load(paths).filter(\.hasText)
        let links: [Snapshot.Entry] = switch scope {
        case .untried: snapshot.filter { entries[$0.id] == nil }
        case .all: snapshot
        case .link(let id): snapshot.filter { $0.id == id }
        }
        if case .link(let id) = scope, links.isEmpty {
            print("No link #\(id) with a preview in the snapshot.")
            return
        }
        print("tagging \(links.count) of \(snapshot.count) links…")
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        var times: [Double] = []
        var refused: [Int] = []
        for link in links {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let start = ContinuousClock.now
            var entry = entries[link.id] ?? Entry(id: link.id, seconds: 0)
            do {
                let response = try await session.respond(to: link.document, generating: LinkTags.self)
                entry.tags = response.content.tags.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces)) }
                entry.problem = nil
                entry.osVersion = osVersion
            } catch {
                entry.problem = "\(error)"
                refused.append(link.id)
            }
            entry.seconds = seconds(since: start)
            entry.attemptedAt = .now
            entries[link.id] = entry
            times.append(entry.seconds)
            print("  #\(link.id) \(String(format: "%.2f", entry.seconds))s \(entry.problem.map { "refused (\($0)); kept: \(entry.tags?.joined(separator: ", ") ?? "none")" } ?? entry.tags?.joined(separator: ", ") ?? "")")
        }
        let output = Output(instructions: instructions, entries: entries.values.sorted { $0.id < $1.id })
        try JSONEncoder.pretty.encode(output).write(to: paths.tags)
        guard !times.isEmpty else { return }
        times.sort()
        print("tagged \(links.count - refused.count) of \(links.count); median \(String(format: "%.2f", times[times.count / 2]))s, slowest \(String(format: "%.2f", times.last ?? 0))s"
            + (refused.isEmpty ? "" : "; refused: \(refused.map { "#\($0)" }.joined(separator: ", "))"))
    }

    static func load(_ paths: Paths) throws -> Output {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Output.self, from: Data(contentsOf: paths.tags))
    }

    /// Each link's current tags, for search.
    static func tags(_ paths: Paths) throws -> [Int: [String]] {
        Dictionary(uniqueKeysWithValues: try load(paths).entries.compactMap { entry in entry.tags.map { (entry.id, $0) } })
    }
}
