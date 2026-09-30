import Accelerate
import Foundation

/// Whether a text is a search query or a saved link. Retrieval models like bge-small put an instruction before queries.
public enum TextRole: Sendable {
    case query
    case document
}

/// Turns text into one vector of length 1, so a dot product is the cosine similarity. Smart Search's interface to its
/// model, so the model can be swapped (docs/search-plan.md).
public protocol TextEmbedder: Sendable {
    /// Stored with each vector, so vectors made by another model, or another version of it, are made again.
    var modelID: String { get }
    var dimension: Int { get }
    func vector(for text: String, role: TextRole) -> [Float]
}

/// A BERT text encoder run on the CPU with Accelerate: bge-small-en-v1.5 for Smart Search. The weights are read in
/// place from the downloaded `.safetensors` file (`Safetensors`), and each call works in buffers of its own, so calls
/// can run at the same time. The vector is the [CLS] token's final hidden state, normalized, as bge pools it.
///
/// Checked against swift-embeddings (MLTensor) in `Tools/SearchEval` (`swift run SearchEval check`): the same tokens,
/// and vectors with a cosine similarity of 1 to within rounding.
public final class BertEmbedder: TextEmbedder {
    public let modelID: String
    public let dimension: Int
    private let queryPrefix: String
    private let tokenizer: WordPieceTokenizer
    private let weights: Safetensors
    private let config: Config
    private let embeddings: Embeddings
    private let layers: [Layer]

    struct Config: Decodable {
        let hiddenSize: Int
        let numHiddenLayers: Int
        let numAttentionHeads: Int
        let intermediateSize: Int
        let maxPositionEmbeddings: Int
        let layerNormEps: Float
        let hiddenAct: String
    }

    private struct Embeddings {
        let words: Safetensors.Tensor
        let positions: Safetensors.Tensor
        let tokenType: Safetensors.Tensor
        let normWeight: Safetensors.Tensor
        let normBias: Safetensors.Tensor
    }

    private struct Linear {
        let weight: Safetensors.Tensor
        let bias: Safetensors.Tensor
        let inputs: Int
        let outputs: Int
    }

    private struct Layer {
        let query: Linear
        let key: Linear
        let value: Linear
        let attentionOutput: Linear
        let attentionNorm: (weight: Safetensors.Tensor, bias: Safetensors.Tensor)
        let intermediate: Linear
        let output: Linear
        let outputNorm: (weight: Safetensors.Tensor, bias: Safetensors.Tensor)
    }

    /// Loads the model's files from `directory`: `config.json`, `vocab.txt` and `model.safetensors`.
    public init(directory: URL, model: SearchModel) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(Config.self, from: Data(contentsOf: directory.appending(path: "config.json")))
        guard config.hiddenAct == "gelu", config.hiddenSize % config.numAttentionHeads == 0 else {
            throw SearchModelError.unsupported("config.json")
        }
        let tokenizer = try WordPieceTokenizer(vocabulary: String(contentsOf: directory.appending(path: "vocab.txt"), encoding: .utf8))
        let weights = try Safetensors(contentsOf: directory.appending(path: "model.safetensors"))

        let hidden = config.hiddenSize
        func tensor(_ name: String, rows: Int?, _ columns: Int...) throws -> Safetensors.Tensor {
            // A nil row count takes the file's, for tables sized by the vocabulary.
            let rows = rows ?? weights.tensors[name]?.shape.first ?? 0
            return try weights.tensor(name, shape: [rows] + columns)
        }
        func linear(_ name: String, _ inputs: Int, _ outputs: Int) throws -> Linear {
            Linear(
                weight: try tensor(name + ".weight", rows: outputs, inputs),
                bias: try weights.tensor(name + ".bias", shape: [outputs]),
                inputs: inputs,
                outputs: outputs
            )
        }
        func norm(_ name: String) throws -> (weight: Safetensors.Tensor, bias: Safetensors.Tensor) {
            (try weights.tensor(name + ".weight", shape: [hidden]), try weights.tensor(name + ".bias", shape: [hidden]))
        }
        let embeddings = Embeddings(
            words: try tensor("embeddings.word_embeddings.weight", rows: nil, hidden),
            positions: try tensor("embeddings.position_embeddings.weight", rows: config.maxPositionEmbeddings, hidden),
            tokenType: try tensor("embeddings.token_type_embeddings.weight", rows: nil, hidden),
            normWeight: try weights.tensor("embeddings.LayerNorm.weight", shape: [hidden]),
            normBias: try weights.tensor("embeddings.LayerNorm.bias", shape: [hidden])
        )
        guard embeddings.words.shape[0] > Int(max(tokenizer.start, tokenizer.end, tokenizer.unknown)), embeddings.tokenType.shape[0] > 0 else {
            throw SearchModelError.damagedFile("model.safetensors")
        }
        let inner = config.intermediateSize
        let layers = try (0..<config.numHiddenLayers).map { index in
            let prefix = "encoder.layer.\(index)."
            return Layer(
                query: try linear(prefix + "attention.self.query", hidden, hidden),
                key: try linear(prefix + "attention.self.key", hidden, hidden),
                value: try linear(prefix + "attention.self.value", hidden, hidden),
                attentionOutput: try linear(prefix + "attention.output.dense", hidden, hidden),
                attentionNorm: try norm(prefix + "attention.output.LayerNorm"),
                intermediate: try linear(prefix + "intermediate.dense", hidden, inner),
                output: try linear(prefix + "output.dense", inner, hidden),
                outputNorm: try norm(prefix + "output.LayerNorm")
            )
        }

        modelID = model.id
        dimension = hidden
        queryPrefix = model.queryPrefix
        self.tokenizer = tokenizer
        self.weights = weights
        self.config = config
        self.embeddings = embeddings
        self.layers = layers
    }

    public func vector(for text: String, role: TextRole) -> [Float] {
        encode(tokenIDs(for: text, role: role))
    }

    /// The tokens the model reads for `text`, queries with their instruction first.
    func tokenIDs(for text: String, role: TextRole) -> [Int32] {
        tokenizer.tokenize((role == .query ? queryPrefix : "") + text, maxTokens: config.maxPositionEmbeddings)
    }

    // MARK: - Forward pass

    func encode(_ ids: [Int32]) -> [Float] {
        let count = ids.count
        let hidden = config.hiddenSize
        let heads = config.numAttentionHeads
        let headSize = hidden / heads
        let inner = config.intermediateSize
        let vocabularySize = embeddings.words.shape[0]

        let x = Buffer(count * hidden)
        let attended = Buffer(count * hidden)
        let q = Buffer(count * hidden)
        let k = Buffer(count * hidden)
        let v = Buffer(count * hidden)
        let context = Buffer(count * hidden)
        let intermediate = Buffer(count * inner)
        let scores = Buffer(count * count)
        defer { [x, attended, q, k, v, context, intermediate, scores].forEach { $0.free() } }

        return weights.data.withUnsafeBytes { raw -> [Float] in
            func pointer(_ tensor: Safetensors.Tensor) -> UnsafePointer<Float> {
                raw.baseAddress!.advanced(by: tensor.offset).assumingMemoryBound(to: Float.self)
            }
            func linear(_ layer: Linear, _ input: UnsafePointer<Float>, _ output: UnsafeMutablePointer<Float>) {
                // output = input · weightᵀ + bias. PyTorch stores a linear layer's weight as [outputs, inputs].
                cblas_sgemm(
                    CblasRowMajor, CblasNoTrans, CblasTrans,
                    Int32(count), Int32(layer.outputs), Int32(layer.inputs),
                    1, input, Int32(layer.inputs), pointer(layer.weight), Int32(layer.inputs),
                    0, output, Int32(layer.outputs)
                )
                for row in 0..<count {
                    vDSP_vadd(output + row * layer.outputs, 1, pointer(layer.bias), 1, output + row * layer.outputs, 1, vDSP_Length(layer.outputs))
                }
            }
            func layerNorm(_ values: UnsafeMutablePointer<Float>, _ weight: Safetensors.Tensor, _ bias: Safetensors.Tensor) {
                let length = vDSP_Length(hidden)
                for row in 0..<count {
                    let start = values + row * hidden
                    var mean: Float = 0
                    vDSP_meanv(start, 1, &mean, length)
                    var negated = -mean
                    vDSP_vsadd(start, 1, &negated, start, 1, length)
                    var squares: Float = 0
                    vDSP_svesq(start, 1, &squares, length)
                    var scale = 1 / (squares / Float(hidden) + config.layerNormEps).squareRoot()
                    vDSP_vsmul(start, 1, &scale, start, 1, length)
                    vDSP_vma(start, 1, pointer(weight), 1, pointer(bias), 1, start, 1, length)
                }
            }

            // Token, position and token type (all 0) embeddings, summed and normalized.
            for (position, id) in ids.enumerated() {
                let row = x.pointer + position * hidden
                let token = min(max(Int(id), 0), vocabularySize - 1)
                vDSP_vadd(pointer(embeddings.words) + token * hidden, 1, pointer(embeddings.positions) + position * hidden, 1, row, 1, vDSP_Length(hidden))
                vDSP_vadd(row, 1, pointer(embeddings.tokenType), 1, row, 1, vDSP_Length(hidden))
            }
            layerNorm(x.pointer, embeddings.normWeight, embeddings.normBias)

            let scale = 1 / Float(headSize).squareRoot()
            for layer in layers {
                // Self-attention, one head at a time over its slice of the hidden size. One sequence has no padding,
                // so nothing is masked.
                linear(layer.query, x.pointer, q.pointer)
                linear(layer.key, x.pointer, k.pointer)
                linear(layer.value, x.pointer, v.pointer)
                for head in 0..<heads {
                    let offset = head * headSize
                    cblas_sgemm(
                        CblasRowMajor, CblasNoTrans, CblasTrans, Int32(count), Int32(count), Int32(headSize),
                        scale, q.pointer + offset, Int32(hidden), k.pointer + offset, Int32(hidden),
                        0, scores.pointer, Int32(count)
                    )
                    Self.softmaxRows(scores.pointer, rows: count, columns: count)
                    cblas_sgemm(
                        CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(count), Int32(headSize), Int32(count),
                        1, scores.pointer, Int32(count), v.pointer + offset, Int32(hidden),
                        0, context.pointer + offset, Int32(hidden)
                    )
                }
                linear(layer.attentionOutput, context.pointer, attended.pointer)
                vDSP_vadd(attended.pointer, 1, x.pointer, 1, attended.pointer, 1, vDSP_Length(count * hidden))
                layerNorm(attended.pointer, layer.attentionNorm.weight, layer.attentionNorm.bias)

                // Feed-forward, with the exact (erf) GELU BERT uses.
                linear(layer.intermediate, attended.pointer, intermediate.pointer)
                for index in 0..<(count * inner) {
                    let value = intermediate.pointer[index]
                    intermediate.pointer[index] = 0.5 * value * (1 + erff(value * 0.70710677))
                }
                linear(layer.output, intermediate.pointer, x.pointer)
                vDSP_vadd(x.pointer, 1, attended.pointer, 1, x.pointer, 1, vDSP_Length(count * hidden))
                layerNorm(x.pointer, layer.outputNorm.weight, layer.outputNorm.bias)
            }
            return Self.normalized(Array(UnsafeBufferPointer(start: x.pointer, count: hidden)))
        }
    }

    private static func softmaxRows(_ values: UnsafeMutablePointer<Float>, rows: Int, columns: Int) {
        let length = vDSP_Length(columns)
        var elements = Int32(columns)
        for row in 0..<rows {
            let start = values + row * columns
            var largest: Float = 0
            vDSP_maxv(start, 1, &largest, length)
            var negated = -largest
            vDSP_vsadd(start, 1, &negated, start, 1, length)
            vvexpf(start, start, &elements)
            var sum: Float = 0
            vDSP_sve(start, 1, &sum, length)
            var inverse = 1 / sum
            vDSP_vsmul(start, 1, &inverse, start, 1, length)
        }
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        let length = sqrt(vDSP.sumOfSquares(vector))
        return length > 0 ? vDSP.divide(vector, length) : vector
    }

    /// Scratch memory for one call.
    private struct Buffer {
        let pointer: UnsafeMutablePointer<Float>

        init(_ count: Int) {
            pointer = .allocate(capacity: max(count, 1))
            pointer.initialize(repeating: 0, count: max(count, 1))
        }

        func free() {
            pointer.deallocate()
        }
    }
}
