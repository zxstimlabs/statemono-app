import Accelerate
import Foundation
import NaturalLanguage
import Synchronization

/// Apple's on-device English text model, `NLContextualEmbedding`: Smart Search's default engine (docs/search-plan.md,
/// Phase 4). The system provides it, so the app downloads nothing of its own; the system fetches the model's files the
/// first time they're asked for. It gives a vector per token, averaged into one, the way Phase 0 measured it. Its
/// vectors all point roughly the same way, so they're compared centered (`centersVectors`), which Phase 0 found best.
public final class AppleEmbedder: TextEmbedder {
    public let modelID: String
    public let dimension: Int
    public var centersVectors: Bool { true }
    /// The model isn't documented as safe to use from several threads at once, so calls take turns.
    private let model: Mutex<NLContextualEmbedding>

    private init(_ model: sending NLContextualEmbedding) {
        modelID = "apple-\(model.modelIdentifier)-r\(model.revision)"
        dimension = model.dimension
        self.model = Mutex(model)
    }

    /// Asks the system for the model's files if they aren't on the device yet, then loads it. Gives up after
    /// `timeout`: the request has no deadline of its own, and in the simulator it never finished.
    public static func load(timeout: Duration = .seconds(90)) async throws -> AppleEmbedder {
        guard let model = NLContextualEmbedding(language: .english) else { throw AppleEmbedderError.noModel }
        if !model.hasAvailableAssets {
            guard try await requestAssets(model, timeout: timeout) == .available else { throw AppleEmbedderError.assetsUnavailable }
        }
        try model.load()
        return AppleEmbedder(model)
    }

    /// The system's answer to the asset request, or `AppleEmbedderError.assetsUnavailable` if none comes in time.
    private static func requestAssets(_ model: NLContextualEmbedding, timeout: Duration) async throws -> NLContextualEmbedding.AssetsResult {
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            model.requestAssets { result, error in
                guard once.claim() else { return }
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if once.claim() { continuation.resume(throwing: AppleEmbedderError.assetsUnavailable) }
            }
        }
    }

    /// Whether the system has the model's files already, so loading needs no download.
    public static var hasAssets: Bool {
        NLContextualEmbedding(language: .english)?.hasAvailableAssets ?? false
    }

    public func vector(for text: String, role: TextRole) -> [Float] {
        model.withLock { model in
            guard !text.isEmpty, let result = try? model.embeddingResult(for: text, language: .english) else {
                return [Float](repeating: 0, count: dimension)
            }
            var sum = [Double](repeating: 0, count: dimension)
            var count = 0
            result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                if vector.count == sum.count { vDSP.add(sum, vector, result: &sum) }
                count += 1
                return true
            }
            return Self.normalized(sum.map { Float($0 / Double(max(count, 1))) })
        }
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        let length = sqrt(vDSP.sumOfSquares(vector))
        return length > 0 ? vDSP.divide(vector, length) : vector
    }
}

/// Lets only the first of several callers through.
private final class Once: Sendable {
    private let claimed = Mutex(false)

    func claim() -> Bool {
        claimed.withLock { claimed in
            defer { claimed = true }
            return !claimed
        }
    }
}

public enum AppleEmbedderError: Error {
    /// This OS has no English model.
    case noModel
    /// The system couldn't fetch the model's files, for example offline.
    case assetsUnavailable
}
