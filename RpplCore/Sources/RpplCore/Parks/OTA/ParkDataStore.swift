import Foundation

/// On-disk home of downloaded park data: `<root>/v<dataVersion>/<id>.yaml` plus an atomically
/// replaced `current.json` pointer. The pointer only moves after a full, validated install, so a
/// failed or interrupted download never touches the data in use.
public struct ParkDataStore: Sendable {
    public struct Pointer: Codable, Equatable, Sendable {
        public var dataVersion: Int
        public var directory: String
        public var publishedAt: String
        public var installedAt: Date
        /// `false` while the manifest's kill switch is on: the directory is kept but not used.
        public var enabled: Bool
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The store the app uses; also read by the widgets through the app group.
    public static var app: ParkDataStore { ParkDataStore(root: AppConstants.localPhoneParkDataRoot) }

    private var pointerURL: URL { root.appendingPathComponent("current.json") }

    public func pointer() -> Pointer? {
        guard let data = try? Data(contentsOf: pointerURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Pointer.self, from: data)
    }

    /// Directory holding the installed files, whether or not the kill switch is on.
    public func installedDirectory() -> URL? {
        guard let pointer else { return nil }
        let url = root.appendingPathComponent(pointer.directory, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Directory the park catalog should read, or nil when there is none or the kill switch is on.
    public func activeDirectory() -> URL? {
        pointer()?.enabled == true ? installedDirectory() : nil
    }

    public func installedFile(_ name: String) -> Data? {
        installedDirectory().flatMap { try? Data(contentsOf: $0.appendingPathComponent(name)) }
    }

    /// Validates `files` against `manifest`, writes them next to the current data and switches over.
    public func install(manifest: ParkDataManifest, files: [String: Data], now: Date = Date()) throws {
        try manifest.validate(files: files)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let name = "v\(manifest.dataVersion)"
        let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for entry in manifest.parks {
                guard let data = files[entry.file] else { throw ParkDataError.missingFile(entry.file) }
                try data.write(to: staging.appendingPathComponent(entry.file))
            }
            // Not the directory the pointer uses right now when the version is unchanged (re-enable
            // path never reaches here), so replacing it is safe.
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staging, to: destination)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }

        try writePointer(Pointer(
            dataVersion: manifest.dataVersion,
            directory: name,
            publishedAt: manifest.publishedAt,
            installedAt: now,
            enabled: true
        ))
        removeStaleDirectories(keeping: name)
    }

    /// Flips the kill switch on already-installed data. No-op when nothing is installed.
    public func setEnabled(_ enabled: Bool) throws {
        guard var pointer = pointer(), pointer.enabled != enabled else { return }
        pointer.enabled = enabled
        try writePointer(pointer)
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    private func writePointer(_ pointer: Pointer) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(pointer).write(to: pointerURL, options: .atomic)
    }

    private func removeStaleDirectories(keeping name: String) {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for url in urls {
            let last = url.lastPathComponent
            guard last != name, last.hasPrefix("v") || last.hasPrefix(".staging-") else { continue }
            try? fm.removeItem(at: url)
        }
    }
}
