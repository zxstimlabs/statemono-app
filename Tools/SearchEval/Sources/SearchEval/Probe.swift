import Foundation
import FoundationModels
import NaturalLanguage

/// What only a run can confirm: whether a command-line process can use Apple's English text model and
/// Apple Intelligence on this Mac.
enum Probe {
    static func run() async throws {
        print("== Apple's English text model (NLContextualEmbedding)")
        let embedder = try Embedder()
        let model = embedder.contextual
        print("model: \(model.modelIdentifier), revision \(model.revision), \(model.dimension) dimensions, up to \(model.maximumSequenceLength) tokens")
        print("files already on this Mac: \(model.hasAvailableAssets)")
        let start = ContinuousClock.now
        try await embedder.prepare()
        print("ready after \(String(format: "%.2f", seconds(since: start)))s (download if needed, then load)")
        let vector = try embedder.vector(for: "A great, free remote access tool, made secure and easy with Tailscale.")
        print("a sentence's vector: \(vector.count) numbers, first three \(vector.prefix(3).map { String(format: "%.4f", $0) })")

        print("\n== Apple Intelligence (FoundationModels)")
        for (name, model) in [("default", SystemLanguageModel.default), ("contentTagging", SystemLanguageModel(useCase: .contentTagging))] {
            print("\(name): \(model.availability)")
        }
        guard case .available = SystemLanguageModel(useCase: .contentTagging).availability else { return }
        let session = LanguageModelSession(model: SystemLanguageModel(useCase: .contentTagging))
        let answerStart = ContinuousClock.now
        let response = try await session.respond(to: "Tailscale and RustDesk: Secure remote access to all your desktops", generating: LinkTags.self)
        print("tags for one title: \(response.content.tags) in \(String(format: "%.2f", seconds(since: answerStart)))s")
    }
}
