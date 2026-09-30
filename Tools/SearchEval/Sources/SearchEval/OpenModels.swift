import CoreML
import Embeddings
import Foundation
import StatemonoKit

/// Turns text into one vector of length 1, so a dot product is the cosine similarity. The app's `BertEmbedder`
/// satisfies it as it is.
protocol EvalEmbedder {
    var dimension: Int { get }
    func vector(for text: String, role: TextRole) async throws -> [Float]
}

extension BertEmbedder: EvalEmbedder {}

extension Embedder: EvalEmbedder {
    /// Apple's models have no query or document prefixes.
    func vector(for text: String, role: TextRole) async throws -> [Float] {
        try vector(for: text)
    }
}

/// Open English embedding models from Hugging Face, run with swift-embeddings on `MLTensor`, which the apps' oldest
/// systems have (iOS 18, macOS 15). They're the plan's "Swapping later" candidates: trained for search, unlike
/// Apple's `NLContextualEmbedding`. Pooling and prefixes follow each model card. Three more didn't load in
/// swift-embeddings 0.0.16 and aren't listed: Snowflake/snowflake-arctic-embed-s (no pooler weights), IBM's
/// granite-embedding-small-english-r2 (BF16 weights, which MLTensor can't hold) and
/// sentence-transformers/static-retrieval-mrl-en-v1 (its tokenizer isn't where the package looks).
struct OpenModel {
    enum Architecture {
        case bert
        case nomicBert
        case model2Vec
    }

    /// The name used in reports and with `--model`.
    let name: String
    let repo: String
    let architecture: Architecture
    let pooling: PostProcess?
    let queryPrefix: String
    let documentPrefix: String

    init(_ name: String, _ repo: String, _ architecture: Architecture, pooling: PostProcess? = nil, query: String = "", document: String = "") {
        self.name = name
        self.repo = repo
        self.architecture = architecture
        self.pooling = pooling
        queryPrefix = query
        documentPrefix = document
    }

    private static let bgeQuery = "Represent this sentence for searching relevant passages: "

    static let all: [OpenModel] = [
        OpenModel("minilm-l6", "sentence-transformers/all-MiniLM-L6-v2", .bert, pooling: .meanPool(normalize: true)),
        OpenModel("bge-small", "BAAI/bge-small-en-v1.5", .bert, pooling: .clsTokenPool(normalize: true), query: bgeQuery),
        OpenModel("e5-small", "intfloat/e5-small-v2", .bert, pooling: .meanPool(normalize: true), query: "query: ", document: "passage: "),
        OpenModel("gte-small", "thenlper/gte-small", .bert, pooling: .meanPool(normalize: true)),
        OpenModel("bge-base", "BAAI/bge-base-en-v1.5", .bert, pooling: .clsTokenPool(normalize: true), query: bgeQuery),
        OpenModel("nomic-v1.5", "nomic-ai/nomic-embed-text-v1.5", .nomicBert, pooling: .meanPool(normalize: true), query: "search_query: ", document: "search_document: "),
        OpenModel("potion-retrieval", "minishlab/potion-retrieval-32M", .model2Vec),
    ]

}

/// A loaded open model. Its files are downloaded once into Data/Models, which git ignores.
struct OpenEmbedder: EvalEmbedder {
    private enum Bundle {
        case bert(Bert.ModelBundle)
        case nomicBert(NomicBert.ModelBundle)
        case model2Vec(Model2Vec.ModelBundle)
    }

    let model: OpenModel
    private(set) var dimension = 0
    /// The downloaded weights, in MB, roughly what the app would download.
    let megabytes: Double
    private let bundle: Bundle

    init(_ model: OpenModel, paths: Paths) async throws {
        self.model = model
        let base = paths.models
        bundle = switch model.architecture {
        case .bert: .bert(try await Bert.loadModelBundle(from: model.repo, downloadBase: base))
        case .nomicBert: .nomicBert(try await NomicBert.loadModelBundle(from: model.repo, downloadBase: base))
        case .model2Vec: .model2Vec(try await Model2Vec.loadModelBundle(from: model.repo, downloadBase: base))
        }
        megabytes = Self.weightsSize(in: base.appending(path: "models/\(model.repo)"))
        dimension = try await raw("probe").count
    }

    func vector(for text: String, role: TextRole) async throws -> [Float] {
        try await raw((role == .query ? model.queryPrefix : model.documentPrefix) + text)
    }

    private func raw(_ text: String) async throws -> [Float] {
        let tensor: MLTensor
        switch bundle {
        case .bert(let bundle): tensor = try bundle.encode(text, options: options(bundle.defaultEncodeOptions))
        case .nomicBert(let bundle): tensor = try bundle.encode(text, options: options(bundle.defaultEncodeOptions))
        case .model2Vec(let bundle): tensor = try bundle.encode(text, normalize: true, computePolicy: Self.policy)
        }
        let scalars = await tensor.cast(to: Float.self).shapedArray(of: Float.self).scalars
        return Embedder.normalized(scalars)
    }

    /// The model card's pooling, and at most 512 tokens, which every saved link fits in.
    private func options(_ defaults: EncodeOptions) -> EncodeOptions {
        var options = defaults
        if let pooling = model.pooling { options.postProcess = pooling }
        options.maxLength = min(options.maxLength, 512)
        options.computePolicy = Self.policy
        return options
    }

    /// CPU only. On this Mac, MLTensor's default (CPU and GPU) took 190ms for a link with bge-small and MiniLM, and
    /// the CPU alone about 30–60ms, with the same results. Asking for the Neural Engine ran as fast as the CPU.
    static let policy = MLComputePolicy(.cpuOnly)

    private static func weightsSize(in folder: URL) -> Double {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? []
        let bytes = files.filter { $0.pathExtension == "safetensors" }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0, +)
        return Double(bytes) / 1_000_000
    }
}
