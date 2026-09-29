import Accelerate
import Foundation
import NaturalLanguage

/// Turns text into one vector of length 1, so a dot product is the cosine similarity. Two of Apple's English models:
/// - `contextual`: the plan's choice, `NLContextualEmbedding`. It gives a vector per token, averaged here.
/// - `sentence`: `NLEmbedding.sentenceEmbedding`, older and made to compare whole sentences, tried as an alternative.
struct Embedder {
    enum Kind: String, CaseIterable {
        case contextual
        case sentence
    }

    let kind: Kind
    let contextual: NLContextualEmbedding
    private let sentence: NLEmbedding?

    init(_ kind: Kind = .contextual) throws {
        guard let contextual = NLContextualEmbedding(language: .english) else { throw EmbedderError.noModel }
        self.kind = kind
        self.contextual = contextual
        sentence = kind == .sentence ? NLEmbedding.sentenceEmbedding(for: .english) : nil
        if kind == .sentence, sentence == nil { throw EmbedderError.noModel }
    }

    var dimension: Int { kind == .contextual ? contextual.dimension : sentence!.dimension }

    /// Downloads the contextual model's files if they aren't on the device yet, then loads it.
    func prepare() async throws {
        guard kind == .contextual else { return }
        if !contextual.hasAvailableAssets {
            let result = try await contextual.requestAssets()
            guard result == .available else { throw EmbedderError.assets(result) }
        }
        try contextual.load()
    }

    func vector(for text: String) throws -> [Float] {
        switch kind {
        case .contextual:
            let result = try contextual.embeddingResult(for: text, language: .english)
            var sum = [Double](repeating: 0, count: contextual.dimension)
            var count = 0
            result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                vDSP.add(sum, vector, result: &sum)
                count += 1
                return true
            }
            return Self.normalized(sum.map { Float($0 / Double(max(count, 1))) })
        case .sentence:
            let vector = sentence!.vector(for: text) ?? []
            return Self.normalized(vector.isEmpty ? [Float](repeating: 0, count: dimension) : vector.map(Float.init))
        }
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        let length = sqrt(vDSP.sumOfSquares(vector))
        return length > 0 ? vDSP.divide(vector, length) : vector
    }

    enum EmbedderError: Error {
        case noModel
        case assets(NLContextualEmbedding.AssetsResult)
    }
}

extension NLContextualEmbedding.AssetsResult: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .available: "available"
        case .notAvailable: "notAvailable"
        case .error: "error"
        @unknown default: "unknown"
        }
    }
}
