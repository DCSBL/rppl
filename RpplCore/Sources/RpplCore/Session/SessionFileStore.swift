import Foundation

public enum SessionStoreError: Error, Equatable, Sendable, LocalizedError {
    case sessionNotFound(String)
    case invalidManifest
    case invalidSessionId(String)
    case importTooLarge(Int)
    case importLimitExceeded(String)
    case ioFailure(String)
    case notTransferable(String)

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
        case .notTransferable(let reason):
            return "Session not transferable: \(reason)"
        }
    }
}

/// File layout for one session package:
/// ```
/// <root>/<YYYY-MM-DD HH-mm - City>/   # display name; identity is manifest.sessionId
///   manifest.json
///   detections.jsonl
///   location-000.jsonl
///   motion-000.jsonl.zlib (framed zlib JSONL)
///   health-000.jsonl
///   water-000.jsonl (optional; Ultra submerged water temperature)
///   battery-000.jsonl (optional; Watch battery level + state)
///   derived/view.json (optional; SessionStats + MapTrackFrame)
/// ```
public final class SessionFileStore: @unchecked Sendable {
    public let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    /// Pretty-printed for `manifest.json` only — humans open this file directly; JSONL streams
    /// must stay one line per record, so they keep using `encoder`.
    private let manifestEncoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSRecursiveLock()
    /// `sessionId` → package directory. Rebuilt by scanning `manifest.json` files.
    private var packageIndex: [String: URL]?

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        self.manifestEncoder = JSONEncoder()
        self.manifestEncoder.dateEncodingStrategy = .iso8601
        self.manifestEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func ensureRootExists() throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    /// Resolves the on-disk package directory for `sessionId` (folder name may differ).
    public func sessionDirectory(for sessionId: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        try SessionIdValidator.validate(sessionId)
        if let cached = cachedDirectory(for: sessionId),
           fileManager.fileExists(atPath: cached.path) {
            return cached
        }
        let map = try rebuildPackageIndex()
        guard let url = map[sessionId] else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }
        return url
    }

    public func createSession(manifest: SessionManifest) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        try SessionIdValidator.validate(manifest.sessionId)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

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
        lock.lock()
        defer { lock.unlock() }

        let url = try sessionDirectory(for: manifest.sessionId).appendingPathComponent("manifest.json")
        let data = try manifestEncoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    public func readManifest(sessionId: String) throws -> SessionManifest {
        lock.lock()
        defer { lock.unlock() }

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
        lock.lock()
        defer { lock.unlock() }

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
        lock.lock()
        defer { lock.unlock() }

        let dir = try sessionDirectory(for: sessionId).appendingPathComponent("derived", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(view)
        try data.write(to: try derivedViewURL(sessionId: sessionId), options: [.atomic])
    }

    /// Phone-only city write-back; does not change stats / mapFrame.
    /// Phone-only city write-back; renames package folder when still app-generated.
    public func updateDerivedCityName(_ cityName: String, sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

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

    /// Links the session to a park and syncs the derived location label (`cityName`) to the park name.
    ///
    /// Manual links are kept as-is (including manual "no park"). Otherwise a stored `parkId` wins;
    /// unlinked sessions are matched on `center` and stored as `auto`.
    /// - Returns: The linked park, or nil when unlinked (label left to city geocoding).
    @discardableResult
    public func linkPark(sessionId: String, center: ParkCoordinate?, parks: [Park]) throws -> Park? {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        let park: Park?
        if manifest.parkIdSource == SessionParkSource.manual || manifest.parkId != nil {
            park = parks.first { $0.id == manifest.parkId }
        } else if let center, let match = ParkListing.nearest(to: center, in: parks) {
            manifest.parkId = match.id
            manifest.parkIdSource = SessionParkSource.auto
            try writeManifest(manifest)
            park = match
        } else {
            park = nil
        }
        if let park { try syncParkLabel(park.name, sessionId: sessionId, startedAt: manifest.startedAt) }
        return park
    }

    /// Manual park pick from session detail. Nil = explicitly no park; clears the park label
    /// so city geocoding refills it.
    public func setManualPark(_ park: Park?, sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        manifest.parkId = park?.id
        manifest.parkIdSource = SessionParkSource.manual
        try writeManifest(manifest)
        if let park {
            try syncParkLabel(park.name, sessionId: sessionId, startedAt: manifest.startedAt)
        } else if var view = try readDerivedView(sessionId: sessionId), view.cityName != nil {
            view.cityName = nil
            try writeDerivedView(view, sessionId: sessionId)
        }
    }

    private func syncParkLabel(_ name: String, sessionId: String, startedAt: Date) throws {
        guard var view = try readDerivedView(sessionId: sessionId), view.cityName != name else { return }
        view.cityName = name
        try writeDerivedView(view, sessionId: sessionId)
        try relocatePackageIfNeeded(sessionId: sessionId, startedAt: startedAt, cityName: name)
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
        lock.lock()
        defer { lock.unlock() }

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
        lock.lock()
        defer { lock.unlock() }

        let previousCity = try readDerivedView(sessionId: sessionId)?.cityName
        let rebuilt = try buildDerivedView(sessionId: sessionId, cityName: previousCity)
        try writeDerivedView(rebuilt, sessionId: sessionId)
        return rebuilt
    }

    public func buildDerivedView(
        sessionId: String,
        cityName: String? = nil
    ) throws -> DerivedSessionView {
        try migrateIfNeeded(sessionId: sessionId)
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
        return DerivedSessionView(
            analyzerVersion: SessionAnalyzer.version,
            stats: stats,
            mapFrame: mapFrame,
            mapTracks: mapTracks,
            cityName: cityName
        )
    }

    public func appendDetection(_ event: DetectionEvent, sessionId: String) throws {
        // Appends never re-read the file: that is O(N) per write and one bad line would block all
        // later writes.
        try appendJSONLine(event, to: "detections.jsonl", sessionId: sessionId)
    }

    public func appendLocationSamples(_ samples: [LocationSample], sessionId: String, chunkIndex: Int = 0) throws {
        let name = String(format: "location-%03d.jsonl", chunkIndex)
        try appendJSONLines(samples, to: name, sessionId: sessionId)
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
        try appendJSONLines(samples, to: name, sessionId: sessionId)
    }

    public func appendWaterTemperatureSamples(
        _ samples: [WaterTemperatureSample],
        sessionId: String,
        chunkIndex: Int = 0
    ) throws {
        let name = String(format: "water-%03d.jsonl", chunkIndex)
        try appendJSONLines(samples, to: name, sessionId: sessionId)
    }

    public func appendBatterySamples(
        _ samples: [BatterySample],
        sessionId: String,
        chunkIndex: Int = 0
    ) throws {
        let name = String(format: "battery-%03d.jsonl", chunkIndex)
        try appendJSONLines(samples, to: name, sessionId: sessionId)
    }

    public func writeMotionFrameData(_ data: Data, sessionId: String, chunkIndex: Int = 0) throws {
        lock.lock()
        defer { lock.unlock() }

        guard data.count <= SessionImportLimits.maxMotionFramesZlibBytes else {
            throw SessionStoreError.importTooLarge(data.count)
        }
        _ = try CompressedJSONLFrames.decodeFrames(data)
        let dir = try sessionDirectory(for: sessionId)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))
        try data.write(to: url, options: [.atomic])
    }

    /// Compressed motion bytes on disk for the session (0 when none).
    public func motionByteSize(sessionId: String, chunkIndex: Int = 0) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        let url = try sessionDirectory(for: sessionId)
            .appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    /// Delete the session's motion. Motion is the first stream to go when
    /// the Watch runs out of space; see `MotionRecordingPolicy`.
    public func deleteMotion(sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let url = try sessionDirectory(for: sessionId)
            .appendingPathComponent(Self.motionCompressedFileName(chunkIndex: 0))
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Record that motion stopped early. First reason wins.
    public func markMotionStopped(reason: String, at date: Date, sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        guard manifest.motionStoppedReason == nil else { return }
        manifest.motionStoppedAt = date
        manifest.motionStoppedReason = reason
        try writeManifest(manifest)
    }

    /// Free space on the store's volume; nil when the system cannot say. (The "important usage"
    /// resource key is unavailable on watchOS.)
    public func availableCapacityBytes() -> Int64? {
        guard let attrs = try? fileManager.attributesOfFileSystem(forPath: rootURL.path),
              let free = attrs[.systemFreeSize] as? NSNumber else { return nil }
        return free.int64Value
    }

    public func readMotionFrameData(sessionId: String, chunkIndex: Int = 0) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let url = try sessionDirectory(for: sessionId)
            .appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let raw = try Data(contentsOf: url)
        // Ship only frames the phone's strict check accepts: a partial tail from a kill or full
        // disk would otherwise fail the import for good (`truncatedFrame`).
        let intact = CompressedJSONLFrames.validPrefixLength(raw)
        if intact < raw.count {
            WakeLog.error(.store, "motion: dropped \(raw.count - intact) torn byte(s) of \(raw.count)")
        }
        return intact > 0 ? Data(raw.prefix(intact)) : nil
    }

    private static func motionCompressedFileName(chunkIndex: Int) -> String {
        String(format: "motion-%03d.jsonl.zlib", chunkIndex)
    }

    public func listSessionIDs() throws -> [String] {
        try ensureRootExists()
        return try rebuildPackageIndex().keys.sorted()
    }

    /// Permanently removes one session package directory from this store.
    public func deleteSession(sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let dir = try sessionDirectory(for: sessionId)
        guard fileManager.fileExists(atPath: dir.path) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }
        try fileManager.removeItem(at: dir)
        forgetDirectory(for: sessionId)
    }

    // MARK: - Watch distilled view (manifest + derived only)

    /// True when any raw stream file remains under the session package.
    public func hasRawStreams(sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let dir = try? sessionDirectory(for: sessionId) else { return false }
        guard fileManager.fileExists(atPath: dir.path) else { return false }
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return false }
        return names.contains { Self.isRawStreamFileName($0) }
    }

    /// Writes phone-authored manifest + derived view. Does not prune raw streams (local ack only).
    public func applyDistilledView(_ update: WatchViewUpdate) throws {
        lock.lock()
        defer { lock.unlock() }

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
        lock.lock()
        defer { lock.unlock() }

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
        if name.hasPrefix("location-") && name.hasSuffix(".jsonl") { return true }
        if name.hasPrefix("health-") && name.hasSuffix(".jsonl") { return true }
        if name.hasPrefix("water-") && name.hasSuffix(".jsonl") { return true }
        if name.hasPrefix("battery-") && name.hasSuffix(".jsonl") { return true }
        if name.hasPrefix("motion-") && name.hasSuffix(".jsonl.zlib") { return true }
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

    public func readDetections(sessionId: String) throws -> [DetectionEvent] {
        try readJSONL(DetectionEvent.self, from: "detections.jsonl", sessionId: sessionId)
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

    /// Stamps the session end and queues it for transfer. Only for stop and crash recovery, so
    /// `endedAt` is required; retry paths use `requeueForTransfer`. An acknowledged session is
    /// left untouched.
    public func markReadyToTransfer(sessionId: String, endedAt: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        guard TransferStateMachine.isAllowed(from: manifest.transferState, to: .readyToTransfer) else { return }
        manifest.endedAt = endedAt
        manifest.transferState = .readyToTransfer
        try writeManifest(manifest)
    }

    public func updateWeather(_ weather: SessionWeather, sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        manifest.weather = weather
        try writeManifest(manifest)
    }

    public func updateWaterTemperatureEstimate(_ estimate: ParkWaterTemperature, sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        manifest.waterTemperatureEstimate = estimate
        try writeManifest(manifest)
    }

    /// Back to `readyToTransfer` after a failed attempt. Unlike `markReadyToTransfer` it leaves
    /// `endedAt` alone — a retry hours later must not stretch the session.
    public func requeueForTransfer(sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        guard TransferStateMachine.isAllowed(from: manifest.transferState, to: .readyToTransfer) else { return }
        manifest.transferState = .readyToTransfer
        try writeManifest(manifest)
    }

    /// Count a queued package and schedule the earliest next attempt.
    public func recordTransferAttempt(sessionId: String, at date: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        let attempts = (manifest.transferAttempts ?? 0) + 1
        manifest.transferAttempts = attempts
        manifest.nextTransferAttemptAt = date.addingTimeInterval(TransferRetryPolicy.delay(afterAttempt: attempts))
        try writeManifest(manifest)
    }

    /// The phone could not import this package. Keep it (never delete before ack) and back off.
    public func recordTransferFailure(sessionId: String, reason: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        guard manifest.transferState != .acknowledged else { return }
        manifest.lastTransferError = reason
        manifest.transferState = .readyToTransfer
        try writeManifest(manifest)
    }

    public func markTransferring(sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = try readManifest(sessionId: sessionId)
        guard TransferStateMachine.isAllowed(from: manifest.transferState, to: .transferring) else { return }
        manifest.transferState = .transferring
        try writeManifest(manifest)
    }

    /// Marks the session acknowledged after phone import.
    /// - Returns: `true` when this call newly transitioned to `.acknowledged`;
    ///   `false` when it was already acknowledged (idempotent re-ack / heal).
    @discardableResult
    public func markAcknowledged(sessionId: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }

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

    /// Reads the streams under the store lock, then encodes and writes without it: encoding a
    /// long session takes seconds, and recording writes on the same store must not wait on it.
    public func zipSessionForTransfer(sessionId: String, to destinationURL: URL) throws -> URL {
        let dir = try sessionDirectory(for: sessionId)
        guard fileManager.fileExists(atPath: dir.path) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }

        // A pruned or acknowledged session must never be re-sent: the phone replaces its full copy
        // with whatever arrives, so an empty package would wipe the raw streams everywhere.
        let manifest = try readManifest(sessionId: sessionId)
        guard manifest.transferState != .acknowledged else {
            throw SessionStoreError.notTransferable("already acknowledged")
        }
        guard hasRawStreams(sessionId: sessionId) else {
            throw SessionStoreError.notTransferable("raw streams pruned")
        }

        let zipURL = destinationURL.appendingPathComponent("\(sessionId).json")
        let package = try buildTransferPackage(sessionId: sessionId)
        let data = try encoder.encode(package)
        try data.write(to: zipURL, options: [.atomic])
        return zipURL
    }

    public func importTransferPackage(_ package: SessionTransferPackage, intoPhoneStore phoneRoot: URL) throws {
        try SessionIdValidator.validate(package.manifest.sessionId)
        try SessionImportLimits.validateArrayCount(package.detections, limit: SessionImportLimits.maxDetections, label: "detections")
        try SessionImportLimits.validateArrayCount(package.locations, limit: SessionImportLimits.maxLocations, label: "locations")
        try SessionImportLimits.validateArrayCount(package.motion, limit: SessionImportLimits.maxMotionSamples, label: "motion")
        try SessionImportLimits.validateArrayCount(package.health, limit: SessionImportLimits.maxHealthSamples, label: "health")
        try SessionImportLimits.validateArrayCount(package.water, limit: SessionImportLimits.maxWaterSamples, label: "water")
        try SessionImportLimits.validateArrayCount(package.battery, limit: SessionImportLimits.maxBatterySamples, label: "battery")

        let phoneStore = SessionFileStore(rootURL: phoneRoot, fileManager: fileManager)
        // Watch Connectivity retries a transfer whose ack got lost; appending the same streams
        // again doubled every sample on the phone (field session 2026-09-30). Replace instead.
        // `try?`: a session the phone has never seen throws sessionNotFound, and that is the
        // normal first import.
        if let existing = try? phoneStore.sessionDirectory(for: package.manifest.sessionId),
           fileManager.fileExists(atPath: existing.path) {
            // Defense in depth: never replace a copy that has data with a package that has none
            // (a pruned Watch session re-sent by mistake). Keep the copy; the caller still acks.
            let incomingEmpty = package.detections.isEmpty && package.locations.isEmpty
                && package.health.isEmpty && package.motion.isEmpty && package.water.isEmpty
                && package.battery.isEmpty && (package.motionFramesZlib?.isEmpty ?? true)
            if incomingEmpty {
                let hasData = ((try? phoneStore.readDetections(sessionId: package.manifest.sessionId))?.isEmpty == false)
                    || ((try? phoneStore.readLocationSamples(sessionId: package.manifest.sessionId))?.isEmpty == false)
                if hasData { return }
            }
            try phoneStore.deleteSession(sessionId: package.manifest.sessionId)
        }
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

    /// Phone-only import of a Share export JSON. Stamps `manifest.imported`; like every import it
    /// replaces the same `sessionId` if already on disk. Does not touch HealthKit or Watch Connectivity.
    public func importExportedPackage(
        _ package: SessionTransferPackage,
        intoPhoneStore phoneRoot: URL,
        importedAt: Date = Date()
    ) throws {
        var stamped = package
        stamped.manifest.imported = importedAt
        try importTransferPackage(stamped, intoPhoneStore: phoneRoot)
    }

    public func buildTransferPackage(sessionId: String) throws -> SessionTransferPackage {
        lock.lock()
        defer { lock.unlock() }

        let manifest = try readManifest(sessionId: sessionId)
        let detections = try readDetections(sessionId: sessionId)
        // A raw stream that cannot be read must fail the transfer, not ship empty: the phone acks
        // whatever arrives and the Watch then prunes. A stream that was never written reads as [].
        let locations = try readLocationSamples(sessionId: sessionId)
        let motionFrames = try readMotionFrameData(sessionId: sessionId)
        let health = try readHealthSamples(sessionId: sessionId)
        let water = try readWaterTemperatureSamples(sessionId: sessionId)
        let battery = try readBatterySamples(sessionId: sessionId)
        // Rebuildable from the raw streams, so a failure here costs nothing.
        let derived = try? ensureDerivedView(sessionId: sessionId)
        return SessionTransferPackage(
            manifest: manifest,
            detections: detections,
            locations: locations,
            motionFramesZlib: motionFrames,
            health: health,
            water: water,
            battery: battery,
            derived: derived
        )
    }

    public func readMotionSamples(sessionId: String, chunkIndex: Int = 0) throws -> [MotionSample] {
        let zlibURL = try sessionDirectory(for: sessionId)
            .appendingPathComponent(Self.motionCompressedFileName(chunkIndex: chunkIndex))
        guard fileManager.fileExists(atPath: zlibURL.path) else { return [] }
        let framed = try Data(contentsOf: zlibURL)
        let intact = CompressedJSONLFrames.validPrefixLength(framed)
        let utf8 = try CompressedJSONLFrames.decodeFrames(Data(framed.prefix(intact)))
        return try decodeJSONL(MotionSample.self, from: utf8)
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to fileName: String, sessionId: String) throws {
        try appendJSONLines([value], to: fileName, sessionId: sessionId)
    }

    /// One open/seek/write for a whole batch — a flush used to reopen the file per sample, and a
    /// phone import did that thousands of times.
    private func appendJSONLines<T: Encodable>(_ values: [T], to fileName: String, sessionId: String) throws {
        guard !values.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let dir = try sessionDirectory(for: sessionId)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        var data = Data()
        for value in values {
            data.append(try encoder.encode(value))
            data.append(contentsOf: "\n".utf8)
        }
        // Read-write: the torn-tail check below reads the last byte, which fails with EBADF
        // ("The file couldn't be opened") on a write-only handle.
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            // Heal a torn tail so the next record is not glued onto the broken line.
            try handle.seek(toOffset: end - 1)
            let last = try handle.read(upToCount: 1)
            if last != Data([0x0A]) {
                try handle.seekToEnd()
                data.insert(0x0A, at: 0)
            } else {
                try handle.seekToEnd()
            }
        }
        try handle.write(contentsOf: data)
    }

    private func readJSONL<T: Decodable>(
        _ type: T.Type,
        from fileName: String,
        sessionId: String,
        limit: Int? = nil
    ) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }

        let url = try sessionDirectory(for: sessionId).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decodeJSONL(type, from: data, limit: limit)
    }

    /// Tolerant reader: a torn or garbage line (crash, disk full, jetsam) costs only that line.
    /// Splits raw bytes so one invalid UTF-8 byte cannot drop the whole file.
    private func decodeJSONL<T: Decodable>(_ type: T.Type, from data: Data, limit: Int? = nil) throws -> [T] {
        var result: [T] = []
        var skipped = 0
        var lineIndex = 0
        for lineData in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let limit, result.count >= limit { break }
            if lineIndex.isMultiple(of: 256), Task.isCancelled {
                throw CancellationError()
            }
            lineIndex += 1
            if let value = try? decoder.decode(T.self, from: Data(lineData)) {
                result.append(value)
            } else {
                skipped += 1
            }
        }
        if skipped > 0 {
            WakeLog.error(.store, "skipped \(skipped) bad JSONL line(s) reading \(String(describing: T.self))")
        }
        return result
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
        cityName: String?
    ) throws {
        try SessionIdValidator.validate(sessionId)
        let current: URL
        if let cached = cachedDirectory(for: sessionId),
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
    /// Expanded motion samples (tiny sessions / fixtures). Prefer `motionFramesZlib` for sessions.
    public var motion: [MotionSample]
    /// Framed zlib JSONL bytes (`motion-000.jsonl.zlib`) — keeps WC transfer small.
    public var motionFramesZlib: Data?
    public var health: [HealthMetricSample]
    /// Sparse Ultra water-temperature samples (`water-000.jsonl`). Empty when the Watch has none.
    public var water: [WaterTemperatureSample]
    /// Sparse Watch battery samples (`battery-000.jsonl`). Empty when none were logged.
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
        detections = try container.decodeIfPresent([DetectionEvent].self, forKey: .detections) ?? []
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
        case manifest, detections, locations, motion, motionFramesZlib, health, water, battery, derived
    }
}
