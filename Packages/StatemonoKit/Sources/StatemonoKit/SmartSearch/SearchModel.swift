import CryptoKit
import Foundation

/// The model Smart Search downloads when it's turned on: its files on Hugging Face, pinned to one revision and checked
/// by SHA-256, so every device gets exactly the model that was measured (docs/search-plan.md, Phase 0).
public struct SearchModel: Sendable {
    public struct File: Sendable {
        public let name: String
        public let byteCount: Int64
        let sha256: String
    }

    public let name: String
    let repository: String
    let revision: String
    public let files: [File]
    /// bge's instruction for queries. Saved links get none.
    let queryPrefix: String

    /// Stored with each vector: the model and its revision.
    public var id: String { "\(name)@\(revision.prefix(7))" }
    public var downloadSize: Int64 { files.reduce(0) { $0 + $1.byteCount } }

    func url(for file: File) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.name)")!
    }

    /// BAAI's bge-small-en-v1.5 (MIT): a 33M-parameter English BERT trained for search, 384 numbers per vector. In
    /// Phase 0 it found 6 of 7 meaning queries, where Apple's `NLContextualEmbedding` found 1.
    public static let bgeSmall = SearchModel(
        name: "bge-small-en-v1.5",
        repository: "BAAI/bge-small-en-v1.5",
        revision: "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a",
        files: [
            File(name: "config.json", byteCount: 743, sha256: "094f8e891b932f2000c92cfc663bac4c62069f5d8af5b5278c4306aef3084750"),
            File(name: "vocab.txt", byteCount: 231_508, sha256: "07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3"),
            File(name: "model.safetensors", byteCount: 133_466_304, sha256: "3c9f31665447c8911517620762200d2245a2518d6e7208acc78cd9db317e21ad"),
        ],
        queryPrefix: "Represent this sentence for searching relevant passages: "
    )
}

public enum SearchModelError: Error {
    case damagedFile(String)
    case missingTensor(String)
    case unsupported(String)
    case download(file: String, status: Int)
    case checksum(String)
}

/// Where a search model's files live: Application Support/<bundle id>/Models/<name>-<revision>, next to the database.
/// The folder is excluded from backups, since it can be downloaded again.
public struct SearchModelStore: Sendable {
    public let model: SearchModel
    public let directory: URL
    private let base: URL

    public init(model: SearchModel, base: URL = DatabaseLocation.default.directory.appending(path: "Models")) {
        self.model = model
        self.base = base
        directory = base.appending(path: "\(model.name)-\(model.revision.prefix(7))")
    }

    /// Every file is there at its full size. Their contents were checked when they were downloaded.
    public var isInstalled: Bool {
        model.files.allSatisfy { Self.size(of: directory.appending(path: $0.name)) == $0.byteCount }
    }

    /// Bytes on disk in the models folder, other versions included.
    public var sizeOnDisk: Int64 {
        let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? []
        return files.reduce(0) { $0 + Self.size(of: $1) }
    }

    /// Downloads the files that are missing, one after another, reporting the share of `model.downloadSize` done so
    /// far. Each file is checked against its SHA-256 before it's moved into place. Cancelling the task cancels the
    /// download; files already finished are kept for the next try.
    public func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = base
        try folder.setResourceValues(values)
        // Only this version is kept.
        for other in (try? fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [] where other.lastPathComponent != directory.lastPathComponent {
            try? fileManager.removeItem(at: other)
        }

        let total = Double(model.downloadSize)
        var done: Int64 = 0
        for file in model.files {
            let destination = directory.appending(path: file.name)
            if Self.size(of: destination) == file.byteCount {
                done += file.byteCount
                progress(Double(done) / total)
                continue
            }
            let before = done
            let partial = directory.appending(path: file.name + ".partial")
            defer { try? fileManager.removeItem(at: partial) }
            let response = try await FileDownload.run(model.url(for: file), to: partial) { written in
                progress(Double(before + min(written, file.byteCount)) / total)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw SearchModelError.download(file: file.name, status: status) }
            guard Self.size(of: partial) == file.byteCount, try Self.sha256(of: partial) == file.sha256 else {
                throw SearchModelError.checksum(file.name)
            }
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: partial, to: destination)
            done += file.byteCount
            progress(Double(done) / total)
        }
    }

    public func load() throws -> BertEmbedder {
        try BertEmbedder(directory: directory, model: model)
    }

    /// Deletes the model's files, every version.
    public func remove() throws {
        if FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.removeItem(at: base)
        }
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One file downloaded to `destination`, reporting bytes as they arrive. A download task with a delegate of its own:
/// URLSession's async `download(from:delegate:)` never reported progress when it was tried here.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let report: @Sendable (Int64) -> Void
    // Guarded by `lock`: the delegate's calls come on the session's queue.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLResponse, any Error>?
    private var moveError: (any Error)?

    private init(destination: URL, report: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.report = report
    }

    static func run(_ url: URL, to destination: URL, report: @escaping @Sendable (Int64) -> Void) async throws -> URLResponse {
        try Task.checkCancellation()
        let delegate = FileDownload(destination: destination, report: report)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.lock.withLock { delegate.continuation = continuation }
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(totalBytesWritten)
    }

    /// The system deletes `location` when this returns, so the file moves now.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { moveError = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, moveError) = lock.withLock {
            defer { self.continuation = nil }
            return (self.continuation, self.moveError)
        }
        if let error = error ?? moveError {
            continuation?.resume(throwing: error)
        } else if let response = task.response {
            continuation?.resume(returning: response)
        } else {
            continuation?.resume(throwing: URLError(.badServerResponse))
        }
    }
}
