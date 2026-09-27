import CryptoKit
import Foundation

/// Downloaded media on disk, modeled on Telegram's MediaBox: one file per resource, named from its URL, written once and
/// read every time it's shown. As with Telegram's default settings, nothing is removed automatically. The database's
/// `media` table indexes these files (size, last use) and drives cleanup, like Telegram's StorageBox. Files are
/// excluded from backups.
public final class MediaStore: Sendable {
    public static let shared = MediaStore(directory: MediaStore.defaultDirectory)

    /// Application Support/<bundle id>/Media. Moves into the App Group container with the share extension (plan step 4).
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Statemono")
            .appending(path: "Media")
    }

    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Telegram names web resources "http-" plus a hash of the URL; a SHA-256 hash here, so names never collide.
    public static func id(for url: URL) -> String {
        "http-" + SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func file(for url: URL) -> URL {
        directory.appending(path: Self.id(for: url))
    }

    func contains(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: file(for: url).path)
    }

    func data(for url: URL) -> Data? {
        try? Data(contentsOf: file(for: url))
    }

    func fileSize(for url: URL) -> Int? {
        try? file(for: url).resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
    }

    /// Written to a temporary file and moved into place, so a half-written file is never read (MediaBox's `_partial`).
    func store(_ data: Data, for url: URL) throws {
        try prepareDirectory()
        try data.write(to: file(for: url), options: .atomic)
    }

    func remove(_ url: URL) {
        remove(id: Self.id(for: url))
    }

    func remove(id: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: id))
    }

    /// Bytes on disk, counted from the files themselves.
    public func size() -> Int64 {
        files().reduce(0) { $0 + $1.size }
    }

    /// Deletes every file. `AppDatabase.removeAllCachedMedia()` also updates the index.
    func removeAll() {
        for file in files() {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    // MARK: - Private

    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    private func files() -> [(url: URL, size: Int64)] {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
            return []
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return (url, Int64(values.totalFileAllocatedSize ?? 0))
        }
    }
}
