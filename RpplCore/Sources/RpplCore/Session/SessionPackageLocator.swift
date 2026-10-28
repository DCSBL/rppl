import Foundation

/// Discovers session packages by reading `manifest.json` (folder name ≠ session id).
public enum SessionPackageLocator {
    public struct Entry: Equatable, Sendable {
        /// Decoded once per scan; listings reuse it instead of reading `manifest.json` again.
        public var manifest: SessionManifest
        public var directoryURL: URL

        public var sessionId: String { manifest.sessionId }
        public var startedAt: Date { manifest.startedAt }

        public init(manifest: SessionManifest, directoryURL: URL) {
            self.manifest = manifest
            self.directoryURL = directoryURL
        }
    }

    /// All readable packages under `rootURL`, keyed by `manifest.sessionId`.
    public static func index(
        in rootURL: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder? = nil
    ) throws -> [String: Entry] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [:] }
        let jsonDecoder = decoder ?? makeDecoder()
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var result: [String: Entry] = [:]
        for dir in contents {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            guard let entry = try? readEntry(
                sessionDirectory: dir,
                fileManager: fileManager,
                decoder: jsonDecoder
            ) else {
                continue
            }
            guard SessionIdValidator.isValid(entry.sessionId) else { continue }
            if result[entry.sessionId] == nil {
                result[entry.sessionId] = entry
            }
        }
        return result
    }

    public static func sessionIDs(
        in rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        try index(in: rootURL, fileManager: fileManager).keys.sorted()
    }

    public static func directory(
        for sessionId: String,
        in rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try SessionIdValidator.validate(sessionId)
        let map = try index(in: rootURL, fileManager: fileManager)
        guard let entry = map[sessionId] else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }
        return entry.directoryURL
    }

    public static func readEntry(
        sessionDirectory: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder? = nil
    ) throws -> Entry {
        let jsonDecoder = decoder ?? makeDecoder()
        let manifestURL = sessionDirectory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SessionStoreError.sessionNotFound(sessionDirectory.lastPathComponent)
        }
        // Only the manifest: the derived view (stats + map tracks) is the largest file of a
        // package and nothing in a scan needs it.
        let manifest = try jsonDecoder.decode(
            SessionManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        return Entry(manifest: manifest, directoryURL: sessionDirectory)
    }

    public static func existingFolderNames(
        in rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> Set<String> {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return Set(
            contents
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map(\.lastPathComponent)
        )
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
