import Foundation

public enum SessionStoreError: Error, Equatable, Sendable, LocalizedError {
    case sessionNotFound(String)
    case invalidManifest
    case invalidSessionId(String)
    case importTooLarge(Int)
    case importLimitExceeded(String)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let sessionId):
            return "Session not found: \(sessionId)"
        case .invalidManifest:
            return "Invalid session manifest"
        case .invalidSessionId(let sessionId):
            return "Invalid session id: \(sessionId)"
        case .importTooLarge(let bytes):
            return "Import exceeds size limit: \(bytes) bytes"
        case .importLimitExceeded(let detail):
            return "Import exceeds element limit: \(detail)"
        case .ioFailure(let message):
            return message
        }
    }
}

/// File layout for one session package:
/// ```
/// <root>/<YYYY-MM-DD HH-mm - City>/   # display name; identity is manifest.sessionId
///   manifest.json
///   detections.jsonl
///   location-000.jsonl
///   motion-000.jsonl.zlib (framed zlib JSONL; legacy plain motion-000.jsonl still readable)
///   health-000.jsonl
///   water-000.jsonl (optional; Ultra submerged water temperature)
///   battery-000.jsonl (optional; Watch battery level + state)
///   derived/view.json (optional; SessionStats + MapTrackFrame)
/// ```
/// Legacy packages may still live under a bare UUID folder (migrated on open) or have
/// `assumptions.jsonl` / `labels.jsonl` (migrated or ignored).
public final class SessionFileStore: @unchecked Sendable {
    public let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()
    /// `sessionId` → package directory. Rebuilt by scanning `manifest.json` files.
    private var packageIndex: [String: URL]?

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

    /// Resolves the on-disk package directory for `sessionId` (folder name may differ).
    public func sessionDirectory(for sessionId: String) throws -> URL {
        try SessionIdValidator.validate(sessionId)
        if let cached = cachedDirectory(for: sessionId),
           fileManager.fileExists(atPath: cached.path) {
            return cached
        }
        try migratePackageFolderNamesIfNeeded()
        let map = try rebuildPackageIndex()
        guard let url = map[sessionId] else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }
        return url
    }

    public func createSession(manifest: SessionManifest) throws -> URL {
        try SessionIdValidator.validate(manifest.sessionId)
        try ensureRootExists()
        try migratePackageFolderNamesIfNeeded()

        if let existing = try? sessionDirectory(for: manifest.sessionId),
           fileManager.fileExists(atPath: existing.path) {
            try writeManifest(manifest)
            return existing
        }

        let existingNames = try SessionPackageLocator.existingFolderNames(
            in: rootURL,
            fileManager: fileManager
        )
        let base = SessionPackageNaming.baseFolderName(
            startedAt: manifest.startedAt,
            cityName: nil
        )
        let folderName = SessionPackageNaming.uniqueFolderName(
            base: base,
            existingNames: existingNames
        )
        let dir = try SessionPackageNaming.packageDirectory(
            folderName: folderName,
            rootURL: rootURL
        )
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        rememberDirectory(dir, for: manifest.sessionId)
        try writeManifest(manifest)
        let detectionsURL = dir.appendingPathComponent("detections.jsonl")
        if !fileManager.fileExists(atPath: detectionsURL.path) {
            fileManager.createFile(atPath: detectionsURL.path, contents: nil)
        }
        return dir
    }

    public func writeManifest(_ manifest: SessionManifest) throws {
        let url = try sessionDirectory(for: manifest.sessionId).appendingPathComponent("manifest.json")
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    public func readManifest(sessionId: String) throws -> SessionManifest {
        let url = try sessionDirectory(for: sessionId).appendingPathComponent("manifest.json")
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

    // MARK: - Derived view (`derived/view.json`)

    public func derivedViewURL(sessionId: String) throws -> URL {
        try sessionDirectory(for: sessionId)
            .appendingPathComponent("derived", isDirectory: true)
            .appendingPathComponent("view.json")
    }

    public func readDerivedView(sessionId: String) throws -> DerivedSessionView? {
        let url = try derivedViewURL(sessionId: sessionId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(DerivedSessionView.self, from: data)
        } catch {
            // Stale / unreadable sidecar (e.g. schema drift) → missing so ensure rebuilds from raw.
            return nil
        }
    }

    public func writeDerivedView(_ view: DerivedSessionView, sessionId: String) throws {
        let dir = try sessionDirectory(for: sessionId).appendingPathComponent("derived", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(view)
        try data.write(to: try derivedViewURL(sessionId: sessionId), options: [.atomic])
    }

    /// Phone-only city write-back; does not change stats / mapFrame.
    /// Phone-only city write-back; renames package folder when still app-generated.
    public func updateDerivedCityName(_ cityName: String, sessionId: String) throws {
        guard var view = try readDerivedView(sessionId: sessionId) else { return }
        view.cityName = cityName
        try writeDerivedView(view, sessionId: sessionId)
        let manifest = try readManifest(sessionId: sessionId)
        try relocatePackageIfNeeded(
            sessionId: sessionId,
            startedAt: manifest.startedAt,
            cityName: cityName
        )
    }

    /// First `limit` location samples for cheap geocode without full GPS parse.
    public func peekLocationSamples(sessionId: String, limit: Int = 48, chunkIndex: Int = 0) throws -> [LocationSample] {
        let name = String(format: "location-%03d.jsonl", chunkIndex)
        return try readJSONL(LocationSample.self, from: name, sessionId: sessionId, limit: limit)
    }

    /// Returns current derived view, rebuilding from raw when missing or analyzer stale.
    /// Preserves phone-only `cityName` across rebuilds when present.
    @discardableResult
    public func ensureDerivedView(sessionId: String) throws -> DerivedSessionView {
        if let existing = try readDerivedView(sessionId: sessionId), existing.isCurrentAnalyzer {
            return existing
        }
        let previousCity = try readDerivedView(sessionId: sessionId)?.cityName
        let rebuilt = try buildDerivedView(sessionId: sessionId, cityName: previousCity)
        try writeDerivedView(rebuilt, sessionId: sessionId)
        return rebuilt
    }

    /// Force rebuild from raw (tests / future tooling). Does not touch HealthKit.
    @discardableResult
    public func reanalyzeSession(sessionId: String) throws -> DerivedSessionView {
        let previousCity = try readDerivedView(sessionId: sessionId)?.cityName
        let rebuilt = try buildDerivedView(sessionId: sessionId, cityName: previousCity)
        try writeDerivedView(rebuilt, sessionId: sessionId)
        return rebuilt
    }

    public func buildDerivedView(
        sessionId: String,
        cityName: String? = nil
    ) throws -> DerivedSessionView {
        let manifest = try readManifest(sessionId: sessionId)
        let detections = try readDetections(sessionId: sessionId)
        let locations = (try? readLocationSamples(sessionId: sessionId)) ?? []
        let health = (try? readHealthSamples(sessionId: sessionId)) ?? []
        let water = (try? readWaterTemperatureSamples(sessionId: sessionId)) ?? []
        let stats = SessionStatsBuilder.build(
            manifest: manifest,
            detections: detections,
            locations: locations,
            health: health,
            water: water
        )
        let coords = locations.map { (latitude: $0.latitude, longitude: $0.longitude) }
        let mapFrame = MapTrackFitter.frame(locations: coords)
        let mapTracks = SessionMapTrackBuilder.build(locations: locations, sets: stats.sets)
        if manifest.schemaVersion < SessionSchema.currentVersion {
            var updated = manifest
            updated.schemaVersion = SessionSchema.currentVersion
            try writeManifest(updated)
        }
        return DerivedSessionView(
            analyzerVersion: SessionAnalyzer.version,
            stats: stats,
            mapFrame: mapFrame,
            mapTracks: mapTracks,
            cityName: cityName
        )
    }

    public func appendDetection(_ event: DetectionEvent, sessionId: String) throws {
        try migrateAssumptionsIfNeeded(sessionId: sessionId)
        try migratePausedToInactiveIfNeeded(sessionId: sessionId)
        var event = event
        event.code = DetectionCodes.normalize(event.code)
        try appendJSONLine(event, to: "detections.jsonl", sessionId: sessionId)
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

        let dir = try sessionDirectory(for: sessionId)
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

    public func appendHealthSamples(_ samples: [HealthMetricSample], sessionId: String, chunkIndex: Int = 0) throws {
        let name = String(format: "health-%03d.jsonl", chunkIndex)
        for sample in samples {
            try appendJSONLine(sample, to: name, sessionId: sessionId)
        }
    }

    public func appendWaterTemperatureSamples(
        _ samples: [WaterTemperatureSample],
        sessionId: String,
        chunkIndex: Int = 0
    ) throws {
        let name = String(format: "water-%03d.jsonl", chunkIndex)
        for sample in samples {
            try appendJSONLine(sample, to: name, sessionId: sessionId)
        }
    }

    public func appendBatterySamples(
        _ samples: [BatterySample],
        sessionId: String,
        chunkIndex: Int = 0
    ) throws {
        let name = String(format: "battery-%03d.jsonl", chunkIndex)
        for sample in samples {
            try appendJSONLine(sample, to: name, sessionId: sessionId)
        }
    }

    public func writeMotionFrameData(_ data: Data, sessionId: String, chunkIndex: Int = 0) throws {
        guard data.count <= SessionImportLimits.maxMotionFramesZlibBytes else {
            throw SessionStoreError.importTooLarge(data.count)
        }
        _ = try CompressedJSONLFrames.decodeFrames(data)
        let dir = try sessionDirectory(for: sessionId)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))
        try data.write(to: url, options: [.atomic])
    }

    public func readMotionFrameData(sessionId: String, chunkIndex: Int = 0) throws -> Data? {
        let url = try sessionDirectory(for: sessionId)
            .appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private static func motionCompressedFileName(chunkIndex: Int) -> String {
        String(format: "motion-%03d.jsonl.zlib", chunkIndex)
    }

    private static func motionLegacyFileName(chunkIndex: Int) -> String {
        String(format: "motion-%03d.jsonl", chunkIndex)
    }

    public func listSessionIDs() throws -> [String] {
        try ensureRootExists()
        try migratePackageFolderNamesIfNeeded()
        return try rebuildPackageIndex().keys.sorted()
    }

    /// Permanently removes one session package directory from this store.
    public func deleteSession(sessionId: String) throws {
        let dir = try sessionDirectory(for: sessionId)
        guard fileManager.fileExists(atPath: dir.path) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }
        try fileManager.removeItem(at: dir)
        forgetDirectory(for: sessionId)
    }

    /// Renames legacy bare-UUID package folders to `YYYY-MM-DD HH-mm - City`.
    /// Skips user-renamed folders (not app-generated).
    @discardableResult
        public func migratePackageFolderNamesIfNeeded() throws -> [String] {
        try ensureRootExists()
        let entries = try SessionPackageLocator.index(
            in: rootURL,
            fileManager: fileManager,
            decoder: decoder
        )
        var migrated: [String] = []
        for entry in entries.values {
            let currentName = entry.directoryURL.lastPathComponent
            let isBareUUID = SessionPackageNaming.isLegacyUUIDFolder(currentName)
                && currentName == entry.sessionId
            let isDateOnly = SessionPackageNaming.matchesDateOnlyPattern(currentName)
            guard isBareUUID || isDateOnly else { continue }
            try relocatePackageIfNeeded(
                sessionId: entry.sessionId,
                startedAt: entry.startedAt,
                cityName: entry.cityName,
                forceLegacyUUID: isBareUUID
            )
            migrated.append(entry.sessionId)
        }
if !migrated.isEmpty {
            invalidatePackageIndex()
        }
        return migrated.sorted()
    }

    // MARK: - Watch distilled view (manifest + derived only)

    /// True when any raw stream file remains under the session package.
    public func hasRawStreams(sessionId: String) -> Bool {
        guard let dir = try? sessionDirectory(for: sessionId) else { return false }
        guard fileManager.fileExists(atPath: dir.path) else { return false }
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return false }
        return names.contains { Self.isRawStreamFileName($0) }
    }

    /// Writes phone-authored manifest + derived view. Does not prune raw streams (local ack only).
    public func applyDistilledView(_ update: WatchViewUpdate) throws {
        try SessionIdValidator.validate(update.manifest.sessionId)
        let sessionId = update.manifest.sessionId
        if let dir = try? sessionDirectory(for: sessionId),
           fileManager.fileExists(atPath: dir.path) {
            try writeManifest(update.manifest)
        } else {
            _ = try createSession(manifest: update.manifest)
            try writeManifest(update.manifest)
        }
        try writeDerivedView(update.derived, sessionId: sessionId)
    }

    /// Removes raw streams after phone ack. Keeps `manifest.json` and `derived/view.json`.
    public func pruneRawStreams(sessionId: String) throws {
        let manifest = try readManifest(sessionId: sessionId)
        guard manifest.transferState == .acknowledged else {
            throw SessionStoreError.ioFailure("Cannot prune before phone ack: \(sessionId)")
        }
        guard try readDerivedView(sessionId: sessionId) != nil else {
            throw SessionStoreError.ioFailure("Cannot prune without derived view: \(sessionId)")
        }
        guard hasRawStreams(sessionId: sessionId) else { return }

        let dir = try sessionDirectory(for: sessionId)
        let names = try fileManager.contentsOfDirectory(atPath: dir.path)
        for name in names where Self.isRawStreamFileName(name) {
            try fileManager.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private static func isRawStreamFileName(_ name: String) -> Bool {
        if name == "detections.jsonl" { return true }
        if name == "assumptions.jsonl" || name == "labels.jsonl" { return true }
        if name.hasPrefix("location-") && name.hasSuffix(".jsonl") { return true }
        if name.hasPrefix("health-") && name.hasSuffix(".jsonl") { return true }
        if name.hasPrefix("water-") && name.hasSuffix(".jsonl") { return true }
        if name.hasPrefix("battery-") && name.hasSuffix(".jsonl") { return true }
        if name.hasPrefix("motion-") && (name.hasSuffix(".jsonl") || name.hasSuffix(".jsonl.zlib")) {
            return true
        }
        return false
    }

    /// On-disk byte size of one session package (manifest + JSONL checkpoints).
    public func sessionByteSize(sessionId: String) throws -> Int64 {
        let dir = try sessionDirectory(for: sessionId)
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

    /// Reads detections, migrating legacy assumptions / `paused` codes once when needed.
    public func readDetections(sessionId: String) throws -> [DetectionEvent] {
        try migrateAssumptionsIfNeeded(sessionId: sessionId)
        try migratePausedToInactiveIfNeeded(sessionId: sessionId)
        return try readJSONL(DetectionEvent.self, from: "detections.jsonl", sessionId: sessionId)
    }

    /// Copy/rename legacy assumptions → detections when detections file is missing or empty
    /// and assumptions exist.
    @discardableResult
    public func migrateAssumptionsIfNeeded(sessionId: String) throws -> Bool {
        let dir = try sessionDirectory(for: sessionId)
        let detectionsURL = dir.appendingPathComponent("detections.jsonl")
        let assumptionsURL = dir.appendingPathComponent("assumptions.jsonl")

        let detectionsExists = fileManager.fileExists(atPath: detectionsURL.path)
        let assumptionsExists = fileManager.fileExists(atPath: assumptionsURL.path)
        guard assumptionsExists else {
            if !detectionsExists {
                fileManager.createFile(atPath: detectionsURL.path, contents: nil)
            }
            return false
        }

        let detectionsEmpty: Bool = {
            guard detectionsExists,
                  let attrs = try? fileManager.attributesOfItem(atPath: detectionsURL.path),
                  let size = attrs[.size] as? NSNumber
            else {
                return true
            }
            return size.intValue == 0
        }()

        guard detectionsEmpty else { return false }

        // Legacy AssumptionEvent JSON is a subset of DetectionEvent fields except missing detectorId.
        // Re-encode through a bridge decode.
        let legacyLines = try readLegacyAssumptionLines(from: assumptionsURL)
        if !fileManager.fileExists(atPath: detectionsURL.path) {
            fileManager.createFile(atPath: detectionsURL.path, contents: nil)
        }
        for event in legacyLines {
            var migrated = event
            migrated.code = DetectionCodes.normalize(migrated.code)
            try appendJSONLine(migrated, to: "detections.jsonl", sessionId: sessionId)
        }
        try? fileManager.removeItem(at: assumptionsURL)
        return true
    }

    /// Rewrite legacy detection code `paused` → `inactive` once (schema v4).
    @discardableResult
    public func migratePausedToInactiveIfNeeded(sessionId: String) throws -> Bool {
        let detectionsURL = try sessionDirectory(for: sessionId).appendingPathComponent("detections.jsonl")
        guard fileManager.fileExists(atPath: detectionsURL.path) else { return false }

        let events = try readJSONL(DetectionEvent.self, from: "detections.jsonl", sessionId: sessionId)
        guard events.contains(where: { $0.code == DetectionCodes.legacyPaused }) else {
            return false
        }

        let migrated = events.map { event -> DetectionEvent in
            var copy = event
            copy.code = DetectionCodes.normalize(copy.code)
            return copy
        }
        try rewriteDetections(migrated, sessionId: sessionId)

        var manifest = try readManifest(sessionId: sessionId)
        if manifest.schemaVersion < SessionSchema.currentVersion {
            manifest.schemaVersion = SessionSchema.currentVersion
            try writeManifest(manifest)
        }
        return true
    }

    public func readLocationSamples(sessionId: String, chunkIndex: Int = 0) throws -> [LocationSample] {
        let name = String(format: "location-%03d.jsonl", chunkIndex)
        return try readJSONL(LocationSample.self, from: name, sessionId: sessionId)
    }

    public func readHealthSamples(sessionId: String, chunkIndex: Int = 0) throws -> [HealthMetricSample] {
        let name = String(format: "health-%03d.jsonl", chunkIndex)
        return try readJSONL(HealthMetricSample.self, from: name, sessionId: sessionId)
    }

    public func readWaterTemperatureSamples(
        sessionId: String,
        chunkIndex: Int = 0
    ) throws -> [WaterTemperatureSample] {
        let name = String(format: "water-%03d.jsonl", chunkIndex)
        return try readJSONL(WaterTemperatureSample.self, from: name, sessionId: sessionId)
    }

    public func readBatterySamples(
        sessionId: String,
        chunkIndex: Int = 0
    ) throws -> [BatterySample] {
        let name = String(format: "battery-%03d.jsonl", chunkIndex)
        return try readJSONL(BatterySample.self, from: name, sessionId: sessionId)
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

    /// Marks the session acknowledged after phone import.
    /// - Returns: `true` when this call newly transitioned to `.acknowledged`;
    ///   `false` when it was already acknowledged (idempotent re-ack / heal).
    @discardableResult
    public func markAcknowledged(sessionId: String) throws -> Bool {
        var manifest = try readManifest(sessionId: sessionId)
        if manifest.transferState == .acknowledged {
            return false
        }
        manifest.transferState = .acknowledged
        try writeManifest(manifest)
        return true
    }

    /// Sessions waiting for a successful phone ack. Never delete these on transfer failure.
    public func sessionsNeedingTransfer() throws -> [SessionManifest] {
        let manifests = try listReadableManifests()
        return TransferPendingFilter.needingTransfer(manifests)
    }

    public func listReadableManifests() throws -> [SessionManifest] {
        try listSessionIDs().compactMap { sessionId in
            try? readManifest(sessionId: sessionId)
        }
    }

    public func zipSessionForTransfer(sessionId: String, to destinationURL: URL) throws -> URL {
        let dir = try sessionDirectory(for: sessionId)
        guard fileManager.fileExists(atPath: dir.path) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }

        let zipURL = destinationURL.appendingPathComponent("\(sessionId).json")
        let package = try buildTransferPackage(sessionId: sessionId)
        let data = try encoder.encode(package)
        try data.write(to: zipURL, options: [.atomic])
        return zipURL
    }

    public func importTransferPackage(_ package: SessionTransferPackage, intoPhoneStore phoneRoot: URL) throws {
        try SessionIdValidator.validate(package.manifest.sessionId)
        let phoneStore = SessionFileStore(rootURL: phoneRoot, fileManager: fileManager)
        _ = try phoneStore.createSession(manifest: package.manifest)
        for detection in package.detections {
            try phoneStore.appendDetection(detection, sessionId: package.manifest.sessionId)
        }
        try phoneStore.appendLocationSamples(package.locations, sessionId: package.manifest.sessionId)
        if let frames = package.motionFramesZlib, !frames.isEmpty {
            try phoneStore.writeMotionFrameData(frames, sessionId: package.manifest.sessionId)
        } else if !package.motion.isEmpty {
            try phoneStore.appendMotionSamples(package.motion, sessionId: package.manifest.sessionId)
        }
        try phoneStore.appendHealthSamples(package.health, sessionId: package.manifest.sessionId)
        if !package.water.isEmpty {
            try phoneStore.appendWaterTemperatureSamples(package.water, sessionId: package.manifest.sessionId)
        }
        if !package.battery.isEmpty {
            try phoneStore.appendBatterySamples(package.battery, sessionId: package.manifest.sessionId)
        }
        var imported = package.manifest
        imported.transferState = .acknowledged
        try phoneStore.writeManifest(imported)

        let sessionId = package.manifest.sessionId
        if let derived = package.derived, derived.isCurrentAnalyzer {
            try phoneStore.writeDerivedView(derived, sessionId: sessionId)
        } else {
            try phoneStore.ensureDerivedView(sessionId: sessionId)
        }
    }

    /// Phone-only import of a Share export JSON. Stamps `manifest.imported`, replaces same `sessionId`
    /// if already on disk. Does not touch HealthKit or Watch Connectivity.
    public func importExportedPackage(
        _ package: SessionTransferPackage,
        intoPhoneStore phoneRoot: URL,
        importedAt: Date = Date()
    ) throws {
        let phoneStore = SessionFileStore(rootURL: phoneRoot, fileManager: fileManager)
        let sessionId = package.manifest.sessionId
        if fileManager.fileExists(atPath: try phoneStore.sessionDirectory(for: sessionId).path) {
            try phoneStore.deleteSession(sessionId: sessionId)
        }
        var stamped = package
        stamped.manifest.imported = importedAt
        try importTransferPackage(stamped, intoPhoneStore: phoneRoot)
    }

    public func buildTransferPackage(sessionId: String) throws -> SessionTransferPackage {
        let manifest = try readManifest(sessionId: sessionId)
        let detections = try readDetections(sessionId: sessionId)
        let locations = (try? readLocationSamples(sessionId: sessionId)) ?? []
        let motionFrames = try readMotionFrameData(sessionId: sessionId)
        let motion: [MotionSample]
        if motionFrames == nil {
            motion = (try? readMotionSamples(sessionId: sessionId)) ?? []
        } else {
            motion = []
        }
        let health = (try? readJSONL(HealthMetricSample.self, from: "health-000.jsonl", sessionId: sessionId)) ?? []
        let water = (try? readWaterTemperatureSamples(sessionId: sessionId)) ?? []
        let battery = (try? readBatterySamples(sessionId: sessionId)) ?? []
        let derived = try? ensureDerivedView(sessionId: sessionId)
        return SessionTransferPackage(
            manifest: manifest,
            detections: detections,
            locations: locations,
            motion: motion,
            motionFramesZlib: motionFrames,
            health: health,
            water: water,
            battery: battery,
            derived: derived
        )
    }

    public func readMotionSamples(sessionId: String, chunkIndex: Int = 0) throws -> [MotionSample] {
        let dir = try sessionDirectory(for: sessionId)
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

    private func readLegacyAssumptionLines(from url: URL) throws -> [DetectionEvent] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SessionStoreError.ioFailure("Invalid UTF-8 in assumptions.jsonl")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var result: [DetectionEvent] = []
        for line in lines {
            guard let lineData = line.data(using: .utf8) else { continue }
            if let event = try? decoder.decode(DetectionEvent.self, from: lineData) {
                result.append(event)
                continue
            }
            // Legacy AssumptionEvent lacked detectorId — bridge via flexible decode.
            if let legacy = try? decoder.decode(LegacyAssumptionLine.self, from: lineData) {
                result.append(legacy.asDetectionEvent())
            }
        }
        return result
    }

    private func rewriteDetections(_ events: [DetectionEvent], sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let dir = try sessionDirectory(for: sessionId)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("detections.jsonl")
        var data = Data()
        for event in events {
            var line = try encoder.encode(event)
            line.append(contentsOf: "\n".utf8)
            data.append(line)
        }
        try data.write(to: url, options: [.atomic])
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to fileName: String, sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let dir = try sessionDirectory(for: sessionId)
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

    private func readJSONL<T: Decodable>(
        _ type: T.Type,
        from fileName: String,
        sessionId: String,
        limit: Int? = nil
    ) throws -> [T] {
        let url = try sessionDirectory(for: sessionId).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decodeJSONL(type, from: data, limit: limit)
    }

    private func decodeJSONL<T: Decodable>(_ type: T.Type, from data: Data, limit: Int? = nil) throws -> [T] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SessionStoreError.ioFailure("Invalid UTF-8 in JSONL")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var result: [T] = []
        let cap = limit.map { min($0, lines.count) } ?? lines.count
        result.reserveCapacity(cap)
        for (index, line) in lines.enumerated() {
            if let limit, result.count >= limit { break }
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

/// Bridge for pre-v3 `assumptions.jsonl` lines (no `detectorId`).
private struct LegacyAssumptionLine: Decodable {
    var id: String?
    var code: String
    var timestamp: Date
    var reason: String
    var speedMps: Double?
    var waterSubmersionState: String?
    var motionActivity: String?

    func asDetectionEvent() -> DetectionEvent {
        DetectionEvent(
            id: id ?? UUID().uuidString,
            code: code,
            timestamp: timestamp,
            reason: reason,
            detectorId: "legacy_assumption",
            speedMps: speedMps,
            waterSubmersionState: waterSubmersionState,
            motionActivity: motionActivity
        )
    }

    // MARK: - Package path index

    private func cachedDirectory(for sessionId: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return packageIndex?[sessionId]
    }

    private func rememberDirectory(_ url: URL, for sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        var index = packageIndex ?? [:]
        index[sessionId] = url
        packageIndex = index
    }

    private func forgetDirectory(for sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        packageIndex?[sessionId] = nil
    }

    private func invalidatePackageIndex() {
        lock.lock()
        defer { lock.unlock() }
        packageIndex = nil
    }

    @discardableResult
    private func rebuildPackageIndex() throws -> [String: URL] {
        let entries = try SessionPackageLocator.index(
            in: rootURL,
            fileManager: fileManager,
            decoder: decoder
        )
        let map = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value.directoryURL) })
        lock.lock()
        packageIndex = map
        lock.unlock()
        return map
    }

    /// Renames the package directory when the current name is still app-generated.
    private func relocatePackageIfNeeded(
        sessionId: String,
        startedAt: Date,
        cityName: String?,
        forceLegacyUUID: Bool = false
    ) throws {
        try SessionIdValidator.validate(sessionId)
        let current: URL
        if forceLegacyUUID {
            current = rootURL.appendingPathComponent(sessionId, isDirectory: true)
            guard fileManager.fileExists(atPath: current.path) else { return }
        } else if let cached = cachedDirectory(for: sessionId),
                  fileManager.fileExists(atPath: cached.path) {
            current = cached
        } else {
            let entries = try SessionPackageLocator.index(
                in: rootURL,
                fileManager: fileManager,
                decoder: decoder
            )
            guard let entry = entries[sessionId] else { return }
            current = entry.directoryURL
        }

        let currentName = current.lastPathComponent
        guard SessionPackageNaming.isAppGenerated(currentName) else { return }

        let existingNames = try SessionPackageLocator.existingFolderNames(
            in: rootURL,
            fileManager: fileManager
        ).subtracting([currentName])
        let base = SessionPackageNaming.baseFolderName(
            startedAt: startedAt,
            cityName: cityName
        )
        let desired = SessionPackageNaming.uniqueFolderName(
            base: base,
            existingNames: existingNames
        )
        guard desired != currentName else {
            rememberDirectory(current, for: sessionId)
            return
        }

        let destination = try SessionPackageNaming.packageDirectory(
            folderName: desired,
            rootURL: rootURL
        )
        try fileManager.moveItem(at: current, to: destination)
        rememberDirectory(destination, for: sessionId)
    }

}

public struct SessionTransferPackage: Codable, Equatable, Sendable {
    public var manifest: SessionManifest
    public var detections: [DetectionEvent]
    public var locations: [LocationSample]
    /// Expanded motion samples (legacy packages / tiny fixtures). Prefer `motionFramesZlib` for sessions.
    public var motion: [MotionSample]
    /// Framed zlib JSONL bytes (`motion-000.jsonl.zlib`) — keeps WC transfer small.
    public var motionFramesZlib: Data?
    public var health: [HealthMetricSample]
    /// Sparse Ultra water-temperature samples (`water-000.jsonl`). Empty on older packages.
    public var water: [WaterTemperatureSample]
    /// Sparse Watch battery samples (`battery-000.jsonl`). Empty on older packages.
    public var battery: [BatterySample]
    /// Fast view sidecar when present (Watch Stop / current analyzer).
    public var derived: DerivedSessionView?

    public init(
        manifest: SessionManifest,
        detections: [DetectionEvent] = [],
        locations: [LocationSample],
        motion: [MotionSample] = [],
        motionFramesZlib: Data? = nil,
        health: [HealthMetricSample],
        water: [WaterTemperatureSample] = [],
        battery: [BatterySample] = [],
        derived: DerivedSessionView? = nil
    ) {
        self.manifest = manifest
        self.detections = detections
        self.locations = locations
        self.motion = motion
        self.motionFramesZlib = motionFramesZlib
        self.health = health
        self.water = water
        self.battery = battery
        self.derived = derived
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try container.decode(SessionManifest.self, forKey: .manifest)
        if let detections = try container.decodeIfPresent([DetectionEvent].self, forKey: .detections) {
            self.detections = detections
        } else if let assumptions = try container.decodeIfPresent([DetectionEvent].self, forKey: .assumptions) {
            self.detections = assumptions
        } else {
            self.detections = []
        }
        // Discard legacy labels if present.
        _ = try container.decodeIfPresent([LegacyDiscardable].self, forKey: .labels)
        locations = try container.decode([LocationSample].self, forKey: .locations)
        motion = try container.decodeIfPresent([MotionSample].self, forKey: .motion) ?? []
        motionFramesZlib = try container.decodeIfPresent(Data.self, forKey: .motionFramesZlib)
        health = try container.decode([HealthMetricSample].self, forKey: .health)
        water = try container.decodeIfPresent([WaterTemperatureSample].self, forKey: .water) ?? []
        battery = try container.decodeIfPresent([BatterySample].self, forKey: .battery) ?? []
        // Soft-fail derived: stale keys / analyzer drift must not block raw import (rebuild on ensure).
        if container.contains(.derived) {
            derived = try? container.decode(DerivedSessionView.self, forKey: .derived)
        } else {
            derived = nil
        }
        try SessionIdValidator.validate(manifest.sessionId)
        try SessionImportLimits.validateArrayCount(detections, limit: SessionImportLimits.maxDetections, label: "detections")
        try SessionImportLimits.validateArrayCount(locations, limit: SessionImportLimits.maxLocations, label: "locations")
        try SessionImportLimits.validateArrayCount(motion, limit: SessionImportLimits.maxMotionSamples, label: "motion")
        try SessionImportLimits.validateArrayCount(health, limit: SessionImportLimits.maxHealthSamples, label: "health")
        try SessionImportLimits.validateArrayCount(water, limit: SessionImportLimits.maxWaterSamples, label: "water")
        try SessionImportLimits.validateArrayCount(battery, limit: SessionImportLimits.maxBatterySamples, label: "battery")
        if let motionFramesZlib, motionFramesZlib.count > SessionImportLimits.maxMotionFramesZlibBytes {
            throw SessionStoreError.importTooLarge(motionFramesZlib.count)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manifest, forKey: .manifest)
        try container.encode(detections, forKey: .detections)
        try container.encode(locations, forKey: .locations)
        if let motionFramesZlib, !motionFramesZlib.isEmpty {
            try container.encode(motionFramesZlib, forKey: .motionFramesZlib)
        } else {
            try container.encode(motion, forKey: .motion)
        }
        try container.encode(health, forKey: .health)
        if !water.isEmpty {
            try container.encode(water, forKey: .water)
        }
        if !battery.isEmpty {
            try container.encode(battery, forKey: .battery)
        }
        if let derived {
            try container.encode(derived, forKey: .derived)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case manifest, detections, assumptions, labels, locations, motion, motionFramesZlib, health, water, battery, derived
    }
}

/// Opaque decode sink for discarded legacy `labels` arrays.
private struct LegacyDiscardable: Decodable {
    private struct AnyKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        // Accept any keyed JSON object (old LabelEvent lines).
        _ = try decoder.container(keyedBy: AnyKey.self)
    }
}
