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
///   assumptions.jsonl
///   location-000.jsonl
///   motion-000.jsonl.zlib (framed zlib JSONL; legacy plain motion-000.jsonl still readable)
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
        let assumptionsURL = dir.appendingPathComponent("assumptions.jsonl")
        if !fileManager.fileExists(atPath: assumptionsURL.path) {
            fileManager.createFile(atPath: assumptionsURL.path, contents: nil)
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

    public func appendAssumption(_ event: AssumptionEvent, sessionId: String) throws {
        try appendJSONLine(event, to: "assumptions.jsonl", sessionId: sessionId)
    }

    public func appendLocationSamples(_ samples: [LocationSample], sessionId: String, chunkIndex: Int = 0) throws {
        let name = String(format: "location-%03d.jsonl", chunkIndex)
        for sample in samples {
            try appendJSONLine(sample, to: name, sessionId: sessionId)
        }
    }

    public func appendMotionSamples(_ samples: [MotionSample], sessionId: String, chunkIndex: Int = 0) throws {
        guard !samples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let dir = sessionDirectory(for: sessionId)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))

        var jsonl = Data()
        for sample in samples {
            var line = try encoder.encode(sample)
            line.append(contentsOf: "\n".utf8)
            jsonl.append(line)
        }
        try CompressedJSONLFrames.appendFrame(jsonlUTF8: jsonl, to: url, fileManager: fileManager)
    }

    /// Raw framed zlib bytes for WC transfer without expanding samples in memory.
    public func readMotionFrameData(sessionId: String, chunkIndex: Int = 0) throws -> Data? {
        let url = sessionDirectory(for: sessionId)
            .appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func writeMotionFrameData(_ data: Data, sessionId: String, chunkIndex: Int = 0) throws {
        let dir = sessionDirectory(for: sessionId)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))
        try data.write(to: url, options: [.atomic])
    }

    private static func motionCompressedFileName(chunkIndex: Int) -> String {
        String(format: "motion-%03d.jsonl.zlib", chunkIndex)
    }

    private static func motionLegacyFileName(chunkIndex: Int) -> String {
        String(format: "motion-%03d.jsonl", chunkIndex)
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

    /// On-disk byte size of one session package (manifest + JSONL checkpoints).
    public func sessionByteSize(sessionId: String) throws -> Int64 {
        let dir = sessionDirectory(for: sessionId)
        guard fileManager.fileExists(atPath: dir.path) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }
        return try directoryByteSize(at: dir)
    }

    /// Sum of all session packages under the store root (Watch local or phone synced).
    public func totalStoredByteSize() throws -> Int64 {
        try ensureRootExists()
        return try directoryByteSize(at: rootURL)
    }

    private func directoryByteSize(at url: URL) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    public func readLabels(sessionId: String) throws -> [LabelEvent] {
        try readJSONL(LabelEvent.self, from: "labels.jsonl", sessionId: sessionId)
    }

    public func readAssumptions(sessionId: String) throws -> [AssumptionEvent] {
        try readJSONL(AssumptionEvent.self, from: "assumptions.jsonl", sessionId: sessionId)
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
        for assumption in package.assumptions {
            try phoneStore.appendAssumption(assumption, sessionId: package.manifest.sessionId)
        }
        try phoneStore.appendLocationSamples(package.locations, sessionId: package.manifest.sessionId)
        if let frames = package.motionFramesZlib, !frames.isEmpty {
            try phoneStore.writeMotionFrameData(frames, sessionId: package.manifest.sessionId)
        } else if !package.motion.isEmpty {
            try phoneStore.appendMotionSamples(package.motion, sessionId: package.manifest.sessionId)
        }
        try phoneStore.appendHealthSamples(package.health, sessionId: package.manifest.sessionId)
        var imported = package.manifest
        imported.transferState = .acknowledged
        try phoneStore.writeManifest(imported)
    }

    public func buildTransferPackage(sessionId: String) throws -> SessionTransferPackage {
        let manifest = try readManifest(sessionId: sessionId)
        let labels = try readLabels(sessionId: sessionId)
        let assumptions = try readAssumptions(sessionId: sessionId)
        let locations = (try? readLocationSamples(sessionId: sessionId)) ?? []
        let motionFrames = try readMotionFrameData(sessionId: sessionId)
        // Prefer compressed frames on the wire; only expand legacy plain JSONL sessions.
        let motion: [MotionSample]
        if motionFrames == nil {
            motion = (try? readMotionSamples(sessionId: sessionId)) ?? []
        } else {
            motion = []
        }
        let health = (try? readJSONL(HealthMetricSample.self, from: "health-000.jsonl", sessionId: sessionId)) ?? []
        return SessionTransferPackage(
            manifest: manifest,
            labels: labels,
            assumptions: assumptions,
            locations: locations,
            motion: motion,
            motionFramesZlib: motionFrames,
            health: health
        )
    }

    public func readMotionSamples(sessionId: String, chunkIndex: Int = 0) throws -> [MotionSample] {
        let dir = sessionDirectory(for: sessionId)
        let zlibURL = dir.appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))
        if fileManager.fileExists(atPath: zlibURL.path) {
            let framed = try Data(contentsOf: zlibURL)
            let utf8 = try CompressedJSONLFrames.decodeFrames(framed)
            return try decodeJSONL(MotionSample.self, from: utf8)
        }
        return try readJSONL(
            MotionSample.self,
            from: Self.motionLegacyFileName(chunkIndex: chunkIndex),
            sessionId: sessionId
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
        let data = try Data(contentsOf: url)
        return try decodeJSONL(type, from: data)
    }

    private func decodeJSONL<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SessionStoreError.ioFailure("Invalid UTF-8 in JSONL")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var result: [T] = []
        result.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            // Cooperative cancel when called from a Task (detail load / export).
            if index.isMultiple(of: 256), Task.isCancelled {
                throw CancellationError()
            }
            guard let lineData = line.data(using: .utf8) else {
                throw SessionStoreError.ioFailure("Invalid UTF-8 in JSONL line")
            }
            result.append(try decoder.decode(T.self, from: lineData))
        }
        return result
    }
}

public struct SessionTransferPackage: Codable, Equatable, Sendable {
    public var manifest: SessionManifest
    public var labels: [LabelEvent]
    public var assumptions: [AssumptionEvent]
    public var locations: [LocationSample]
    /// Expanded motion samples (legacy packages / tiny fixtures). Prefer `motionFramesZlib` for sessions.
    public var motion: [MotionSample]
    /// Framed zlib JSONL bytes (`motion-000.jsonl.zlib`) — keeps WC transfer small.
    public var motionFramesZlib: Data?
    public var health: [HealthMetricSample]

    public init(
        manifest: SessionManifest,
        labels: [LabelEvent],
        assumptions: [AssumptionEvent] = [],
        locations: [LocationSample],
        motion: [MotionSample] = [],
        motionFramesZlib: Data? = nil,
        health: [HealthMetricSample]
    ) {
        self.manifest = manifest
        self.labels = labels
        self.assumptions = assumptions
        self.locations = locations
        self.motion = motion
        self.motionFramesZlib = motionFramesZlib
        self.health = health
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try container.decode(SessionManifest.self, forKey: .manifest)
        labels = try container.decode([LabelEvent].self, forKey: .labels)
        assumptions = try container.decodeIfPresent([AssumptionEvent].self, forKey: .assumptions) ?? []
        locations = try container.decode([LocationSample].self, forKey: .locations)
        motion = try container.decodeIfPresent([MotionSample].self, forKey: .motion) ?? []
        motionFramesZlib = try container.decodeIfPresent(Data.self, forKey: .motionFramesZlib)
        health = try container.decode([HealthMetricSample].self, forKey: .health)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manifest, forKey: .manifest)
        try container.encode(labels, forKey: .labels)
        try container.encode(assumptions, forKey: .assumptions)
        try container.encode(locations, forKey: .locations)
        if let motionFramesZlib, !motionFramesZlib.isEmpty {
            try container.encode(motionFramesZlib, forKey: .motionFramesZlib)
            // Omit expanded motion when frames present — avoids megabyte JSON arrays on the wire.
        } else {
            try container.encode(motion, forKey: .motion)
        }
        try container.encode(health, forKey: .health)
    }

    private enum CodingKeys: String, CodingKey {
        case manifest, labels, assumptions, locations, motion, motionFramesZlib, health
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
