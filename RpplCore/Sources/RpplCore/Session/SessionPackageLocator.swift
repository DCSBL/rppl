import Foundation

/// Discovers session packages by reading `manifest.json` (folder name ≠ session id).
public enum SessionPackageLocator {
    public struct Entry: Equatable, Sendable {
        public var sessionId: String
        public var directoryURL: URL
        public var startedAt: Date
        public var cityName: String?

        public init(sessionId: String, directoryURL: URL, startedAt: Date, cityName: String? = nil) {
            self.sessionId = sessionId
            self.directoryURL = directoryURL
            self.startedAt = startedAt
            self.cityName = cityName
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
        let manifest = try jsonDecoder.decode(
            SessionManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        var cityName: String?
        let viewURL = sessionDirectory
            .appendingPathComponent("derived", isDirectory: true)
            .appendingPathComponent("view.json")
        if fileManager.fileExists(atPath: viewURL.path),
           let view = try? jsonDecoder.decode(DerivedSessionView.self, from: Data(contentsOf: viewURL)) {
            cityName = view.cityName
        }
        return Entry(
            sessionId: manifest.sessionId,
            directoryURL: sessionDirectory,
            startedAt: manifest.startedAt,
            cityName: cityName
        )
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
