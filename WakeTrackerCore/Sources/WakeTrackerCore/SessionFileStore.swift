import Foundation

public enum SessionStoreError: Error, Equatable, Sendable {
    case sessionNotFound(String)
    case invalidManifest
    case ioFailure(String)
}

/// File layout for one session package:
/// ```
/// <root>/<sessionId>/
///   manifest.json
///   labels.jsonl
///   location-000.jsonl
///   motion-000.jsonl
///   health-000.jsonl
/// ```
public final class SessionFileStore: @unchecked Sendable {
    public let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func ensureRootExists() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func sessionDirectory(for sessionId: String) -> URL {
        rootURL.appendingPathComponent(sessionId, isDirectory: true)
    }

    public func createSession(manifest: SessionManifest) throws -> URL {
        try ensureRootExists()
        let dir = sessionDirectory(for: manifest.sessionId)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeManifest(manifest)
        let labelsURL = dir.appendingPathComponent("labels.jsonl")
        if !fileManager.fileExists(atPath: labelsURL.path) {
            fileManager.createFile(atPath: labelsURL.path, contents: nil)
        }
        return dir
    }

    public func writeManifest(_ manifest: SessionManifest) throws {
        let url = sessionDirectory(for: manifest.sessionId).appendingPathComponent("manifest.json")
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    public func readManifest(sessionId: String) throws -> SessionManifest {
        let url = sessionDirectory(for: sessionId).appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(SessionManifest.self, from: data)
        } catch {
            throw SessionStoreError.invalidManifest
        }
    }

    public func appendLabel(_ event: LabelEvent, sessionId: String) throws {
        try appendJSONLine(event, to: "labels.jsonl", sessionId: sessionId)
    }

    public func appendLocationSamples(_ samples: [LocationSample], sessionId: String, chunkIndex: Int = 0) throws {
        let name = String(format: "location-%03d.jsonl", chunkIndex)
        for sample in samples {
            try appendJSONLine(sample, to: name, sessionId: sessionId)
        }
    }

    public func appendMotionSamples(_ samples: [MotionSample], sessionId: String, chunkIndex: Int = 0) throws {
        let name = String(format: "motion-%03d.jsonl", chunkIndex)
        for sample in samples {
            try appendJSONLine(sample, to: name, sessionId: sessionId)
        }
    }

    public func appendHealthSamples(_ samples: [HealthMetricSample], sessionId: String, chunkIndex: Int = 0) throws {
        let name = String(format: "health-%03d.jsonl", chunkIndex)
        for sample in samples {
            try appendJSONLine(sample, to: name, sessionId: sessionId)
        }
    }

    public func listSessionIDs() throws -> [String] {
        try ensureRootExists()
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    public func readLabels(sessionId: String) throws -> [LabelEvent] {
        try readJSONL(LabelEvent.self, from: "labels.jsonl", sessionId: sessionId)
    }

    public func readLocationSamples(sessionId: String, chunkIndex: Int = 0) throws -> [LocationSample] {
        let name = String(format: "location-%03d.jsonl", chunkIndex)
        return try readJSONL(LocationSample.self, from: name, sessionId: sessionId)
    }

    public func markReadyToTransfer(sessionId: String, endedAt: Date = Date()) throws {
        var manifest = try readManifest(sessionId: sessionId)
        manifest.endedAt = endedAt
        manifest.transferState = .readyToTransfer
        try writeManifest(manifest)
    }

    public func markTransferring(sessionId: String) throws {
        var manifest = try readManifest(sessionId: sessionId)
        manifest.transferState = .transferring
        try writeManifest(manifest)
    }

    public func markAcknowledged(sessionId: String) throws {
        var manifest = try readManifest(sessionId: sessionId)
        manifest.transferState = .acknowledged
        try writeManifest(manifest)
    }

    /// Sessions waiting for a successful phone ack. Never delete these on transfer failure.
    public func sessionsNeedingTransfer() throws -> [SessionManifest] {
        let manifests = try listSessionIDs().map { try readManifest(sessionId: $0) }
        return TransferPendingFilter.needingTransfer(manifests)
    }

    public func zipSessionForTransfer(sessionId: String, to destinationURL: URL) throws -> URL {
        let dir = sessionDirectory(for: sessionId)
        guard fileManager.fileExists(atPath: dir.path) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }

        let zipURL = destinationURL.appendingPathComponent("\(sessionId).json")
        // For alpha: package as a single JSON bundle for reliable WC transfer without zip deps.
        let package = try buildTransferPackage(sessionId: sessionId)
        let data = try encoder.encode(package)
        try data.write(to: zipURL, options: [.atomic])
        return zipURL
    }

    public func importTransferPackage(_ package: SessionTransferPackage, intoPhoneStore phoneRoot: URL) throws {
        let phoneStore = SessionFileStore(rootURL: phoneRoot, fileManager: fileManager)
        _ = try phoneStore.createSession(manifest: package.manifest)
        for label in package.labels {
            try phoneStore.appendLabel(label, sessionId: package.manifest.sessionId)
        }
        try phoneStore.appendLocationSamples(package.locations, sessionId: package.manifest.sessionId)
        try phoneStore.appendMotionSamples(package.motion, sessionId: package.manifest.sessionId)
        try phoneStore.appendHealthSamples(package.health, sessionId: package.manifest.sessionId)
        var imported = package.manifest
        imported.transferState = .acknowledged
        try phoneStore.writeManifest(imported)
    }

    public func buildTransferPackage(sessionId: String) throws -> SessionTransferPackage {
        let manifest = try readManifest(sessionId: sessionId)
        let labels = try readLabels(sessionId: sessionId)
        let locations = (try? readLocationSamples(sessionId: sessionId)) ?? []
        let motion = (try? readJSONL(MotionSample.self, from: "motion-000.jsonl", sessionId: sessionId)) ?? []
        let health = (try? readJSONL(HealthMetricSample.self, from: "health-000.jsonl", sessionId: sessionId)) ?? []
        return SessionTransferPackage(
            manifest: manifest,
            labels: labels,
            locations: locations,
            motion: motion,
            health: health
        )
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to fileName: String, sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let dir = sessionDirectory(for: sessionId)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        var data = try encoder.encode(value)
        data.append(contentsOf: "\n".utf8)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func readJSONL<T: Decodable>(_ type: T.Type, from fileName: String, sessionId: String) throws -> [T] {
        let url = sessionDirectory(for: sessionId).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                guard let data = line.data(using: .utf8) else {
                    throw SessionStoreError.ioFailure("Invalid UTF-8 in \(fileName)")
                }
                return try decoder.decode(T.self, from: data)
            }
    }
}

public struct SessionTransferPackage: Codable, Equatable, Sendable {
    public var manifest: SessionManifest
    public var labels: [LabelEvent]
    public var locations: [LocationSample]
    public var motion: [MotionSample]
    public var health: [HealthMetricSample]

    public init(
        manifest: SessionManifest,
        labels: [LabelEvent],
        locations: [LocationSample],
        motion: [MotionSample],
        health: [HealthMetricSample]
    ) {
        self.manifest = manifest
        self.labels = labels
        self.locations = locations
        self.motion = motion
        self.health = health
    }
}

public enum TesterIdentity {
    public static let defaultsKey = "wakeTracker.anonymousTesterId"

    public static func resolve(store: UserDefaults = .standard) -> String {
        if let existing = store.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        store.set(id, forKey: defaultsKey)
        return id
    }
}
