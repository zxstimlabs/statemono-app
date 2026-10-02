import Accelerate
import CryptoKit
import Foundation
import GRDB

/// A link waiting for its Smart Search vector: the text the model reads, and that text's hash to store with the vector.
public struct VectorWork: Sendable {
    let rowid: Int64
    public let text: String
    let textHash: Data
}

/// How many live links have a current vector, out of those that can have one.
public struct VectorProgress: Equatable, Sendable {
    public let ready: Int
    public let total: Int
}

// Smart Search's vectors, one per item in `itemVector` (docs/search-plan.md, Database changes). Like saved previews, they
// don't touch `updatedAt` or `isDirty`: each device makes its own, and sync won't carry them.
extension AppDatabase {
    /// What the model reads for an item: the preview's title, site name and description, then the message text.
    static func vectorText(title: String?, siteName: String?, summary: String?, text: String) -> String {
        [title, siteName, summary, text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Live items whose vector is missing, was made by another model, or was made from text that has changed since,
    /// newest first, and how many are done. A link waits until its preview has been fetched, so its vector includes it.
    public func vectorWork(model: String) async throws -> (work: [VectorWork], progress: VectorProgress) {
        try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT item.rowid, item.text, item.previewTitle, item.previewSiteName, item.previewSummary,
                       itemVector.model, itemVector.textHash
                FROM item LEFT JOIN itemVector ON itemVector.itemRowID = item.rowid
                WHERE item.deletedAt IS NULL AND (item.link IS NULL OR item.previewFetchedAt IS NOT NULL)
                ORDER BY item.createdAt DESC
                """)
            var work: [VectorWork] = []
            for row in rows {
                let text = Self.vectorText(title: row[2], siteName: row[3], summary: row[4], text: row[1])
                let hash = Data(SHA256.hash(data: Data(text.utf8)))
                if row[5] as String? != model || row[6] as Data? != hash {
                    work.append(VectorWork(rowid: row[0], text: text, textHash: hash))
                }
            }
            return (work, VectorProgress(ready: rows.count - work.count, total: rows.count))
        }
    }

    /// Stores vectors made by `model`, replacing any the items had.
    public func saveVectors(_ vectors: [(work: VectorWork, vector: [Float])], model: String) async throws {
        try await writer.write { db in
            let now = Date.now
            for (work, vector) in vectors {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO itemVector (itemRowID, model, textHash, vector, computedAt) VALUES (?, ?, ?, ?, ?)",
                    arguments: [work.rowid, model, work.textHash, vector.withUnsafeBufferPointer { Data(buffer: $0) }, now]
                )
            }
        }
    }

    /// Deletes every vector, for turning Smart Search off.
    public func removeAllVectors() async throws {
        try await writer.write { db in try db.execute(sql: "DELETE FROM itemVector") }
        vectorIndexCache.withLock { $0 = nil }
    }

    /// Bytes the vectors take.
    public func vectorStorageSize() async throws -> Int64 {
        try await writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT CAST(total(length(vector) + length(textHash) + length(model)) AS INTEGER) FROM itemVector") ?? 0
        }
    }

    /// The live items whose vectors are closest to `query`, best first, leaving out `excluded` (the keyword matches).
    /// Every vector is compared, which takes a few milliseconds even for tens of thousands of links. They're kept in
    /// memory until items or vectors change. `centered` compares them with the average link vector subtracted from
    /// each, query included, which Apple's model needs (`TextEmbedder.centersVectors`).
    public func relatedItems(
        to query: [Float], model: String, centered: Bool = false, excluding excluded: Set<UUID>, count: Int
    ) async throws -> [UUID] {
        let index = try await vectorIndex(model: model, centered: centered)
        guard index.ids.count > 0, query.count == index.dimension else { return [] }
        let query = centered ? Self.centered(query, mean: index.mean) : query
        var scores = [Float](repeating: 0, count: index.ids.count)
        index.matrix.withUnsafeBufferPointer { matrix in
            cblas_sgemv(
                CblasRowMajor, CblasNoTrans, Int32(index.ids.count), Int32(index.dimension),
                1, matrix.baseAddress, Int32(index.dimension), query, 1, 0, &scores, 1
            )
        }
        return scores.indices
            .sorted { scores[$0] > scores[$1] }
            .lazy
            .map { index.ids[$0] }
            .filter { !excluded.contains($0) }
            .prefix(count)
            .map { $0 }
    }

    /// Calls `onChange` on the main actor whenever items may need new vectors: one added, edited or deleted, or a
    /// preview saved. Keep the returned object to keep it going.
    @MainActor
    public func observeSearchContent(onChange: @escaping @MainActor () -> Void) -> FeedObservation {
        let cancellable = ValueObservation
            .tracking { db in try VocabularyVersion(db) }
            .removeDuplicates()
            .start(in: writer, scheduling: .async(onQueue: .main), onError: { _ in }, onChange: { _ in
                MainActor.assumeIsolated { onChange() }
            })
        return FeedObservation(cancellable)
    }

    private func vectorIndex(model: String, centered: Bool) async throws -> VectorIndex {
        let version = try await writer.read { db in try VectorIndexVersion(db, model: model) }
        if let cached = vectorIndexCache.withLock({ $0 }), cached.version == version, cached.isCentered == centered {
            return cached
        }
        let index = try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT item.id, itemVector.vector FROM itemVector JOIN item ON item.rowid = itemVector.itemRowID
                WHERE item.deletedAt IS NULL AND itemVector.model = ?
                """, arguments: [model])
            var ids: [UUID] = []
            var matrix: [Float] = []
            var dimension = 0
            for row in rows {
                let data: Data = row[1]
                let vector = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                if dimension == 0 { dimension = vector.count }
                guard vector.count == dimension else { continue }
                ids.append(row[0])
                matrix += vector
            }
            var mean = [Float](repeating: 0, count: dimension)
            if centered, !ids.isEmpty {
                for row in 0..<ids.count {
                    vDSP.add(mean, matrix[(row * dimension)..<((row + 1) * dimension)], result: &mean)
                }
                mean = vDSP.divide(mean, Float(ids.count))
                matrix = (0..<ids.count).flatMap { row in
                    Self.centered(Array(matrix[(row * dimension)..<((row + 1) * dimension)]), mean: mean)
                }
            }
            return VectorIndex(
                version: try VectorIndexVersion(db, model: model), ids: ids, matrix: matrix, dimension: dimension,
                isCentered: centered, mean: mean
            )
        }
        vectorIndexCache.withLock { $0 = index }
        return index
    }
}

/// Every live item's vector, one row each, for comparing a query with all of them at once.
struct VectorIndex: Sendable {
    let version: VectorIndexVersion
    let ids: [UUID]
    /// Centered and normalized again when `isCentered`.
    let matrix: [Float]
    let dimension: Int
    let isCentered: Bool
    /// The average link vector, subtracted from each when `isCentered`.
    let mean: [Float]
}

extension AppDatabase {
    /// `vector` less the average link vector, made length 1 again.
    static func centered(_ vector: [Float], mean: [Float]) -> [Float] {
        let difference = vDSP.subtract(vector, mean)
        let length = sqrt(vDSP.sumOfSquares(difference))
        return length > 0 ? vDSP.divide(difference, length) : difference
    }
}

/// Changes whenever the index would: a vector saved or removed, or an item deleted (which changes its `updatedAt`).
struct VectorIndexVersion: Equatable, Sendable {
    let model: String
    let count: Int
    let lastVector: String?
    let lastUpdate: String?

    init(_ db: Database, model: String) throws {
        let row = try Row.fetchOne(db, sql: """
            SELECT (SELECT count(*) FROM itemVector), (SELECT max(computedAt) FROM itemVector), (SELECT max(updatedAt) FROM item)
            """)
        self.model = model
        count = row?[0] ?? 0
        lastVector = row?[1]
        lastUpdate = row?[2]
    }
}
