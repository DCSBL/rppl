import Foundation

public struct SessionLoadBundle: Sendable {
    public let manifest: SessionManifest
    public let detections: [DetectionEvent]
    public let locations: [LocationSample]
    public let health: [HealthMetricSample]
    public let water: [WaterTemperatureSample]
    public let stats: SessionStats
    public let byteSize: Int64
    public let mapFrame: MapTrackFrame?
    public let cityName: String?

    public init(
        manifest: SessionManifest,
        detections: [DetectionEvent],
        locations: [LocationSample],
        health: [HealthMetricSample],
        water: [WaterTemperatureSample],
        stats: SessionStats,
        byteSize: Int64,
        mapFrame: MapTrackFrame? = nil,
        cityName: String? = nil
    ) {
        self.manifest = manifest
        self.detections = detections
        self.locations = locations
        self.health = health
        self.water = water
        self.stats = stats
        self.byteSize = byteSize
        self.mapFrame = mapFrame
        self.cityName = cityName
    }
}

/// List / detail first-paint without loading location streams.
public struct SessionSummaryBundle: Sendable {
    public let manifest: SessionManifest
    public let derived: DerivedSessionView
    public let byteSize: Int64

    public init(manifest: SessionManifest, derived: DerivedSessionView, byteSize: Int64) {
        self.manifest = manifest
        self.derived = derived
        self.byteSize = byteSize
    }

    public var stats: SessionStats { derived.stats }
    public var mapFrame: MapTrackFrame? { derived.mapFrame }
    public var cityName: String? { derived.cityName }
}

public enum SessionLoader {
    public static func load(store: SessionFileStore, sessionId: String) throws -> SessionLoadBundle {
        let manifest = try store.readManifest(sessionId: sessionId)
        let detections = try store.readDetections(sessionId: sessionId)
        let locations = try store.readLocationSamples(sessionId: sessionId)
        let health = try store.readHealthSamples(sessionId: sessionId)
        let water = try store.readWaterTemperatureSamples(sessionId: sessionId)
        let byteSize = try store.sessionByteSize(sessionId: sessionId)
        let stats = SessionStatsBuilder.build(
            manifest: manifest,
            detections: detections,
            locations: locations,
            health: health,
            water: water
        )
        let coords = locations.map { (latitude: $0.latitude, longitude: $0.longitude) }
        let mapFrame = MapTrackFitter.frame(locations: coords)
        let existing = try store.readDerivedView(sessionId: sessionId)
        let cityName = existing?.cityName
        if existing == nil || existing?.isCurrentAnalyzer != true {
            try store.writeDerivedView(
                DerivedSessionView(
                    analyzerVersion: SessionAnalyzer.version,
                    stats: stats,
                    mapFrame: mapFrame,
                    cityName: cityName
                ),
                sessionId: sessionId
            )
            if manifest.schemaVersion < SessionSchema.currentVersion {
                var updated = manifest
                updated.schemaVersion = SessionSchema.currentVersion
                try store.writeManifest(updated)
            }
        }
        return SessionLoadBundle(
            manifest: manifest,
            detections: detections,
            locations: locations,
            health: health,
            water: water,
            stats: stats,
            byteSize: byteSize,
            mapFrame: mapFrame,
            cityName: cityName
        )
    }

    /// Manifest + derived stats/frame only (ensures sidecar). No location/health parse when fresh.
    public static func loadSummary(store: SessionFileStore, sessionId: String) throws -> SessionSummaryBundle {
        let manifest = try store.readManifest(sessionId: sessionId)
        let derived = try store.ensureDerivedView(sessionId: sessionId)
        let byteSize = try store.sessionByteSize(sessionId: sessionId)
        return SessionSummaryBundle(manifest: manifest, derived: derived, byteSize: byteSize)
    }

    /// Read-only manifest + derived for distilled Watch logbook (never rebuilds from raw).
    public static func loadStoredSummary(store: SessionFileStore, sessionId: String) throws -> SessionSummaryBundle {
        let manifest = try store.readManifest(sessionId: sessionId)
        guard let derived = try store.readDerivedView(sessionId: sessionId) else {
            throw SessionStoreError.ioFailure("Missing derived view for \(sessionId)")
        }
        return SessionSummaryBundle(manifest: manifest, derived: derived, byteSize: 0)
    }

    /// In-memory load from a Share export / WC package (no disk write).
    public static func load(package: SessionTransferPackage) -> SessionLoadBundle {
        makeBundle(
            manifest: package.manifest,
            detections: package.detections,
            locations: package.locations,
            health: package.health,
            water: package.water,
            byteSize: 0,
            mapFrame: nil,
            cityName: nil
        )
    }

    public static func load(packageURL: URL) throws -> SessionLoadBundle {
        let data = try Data(contentsOf: packageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(SessionTransferPackage.self, from: data)
        return load(package: package)
    }

    /// Bundled empty-state example: shift timeline so `endedAt` is `now` (relative gaps kept).
    public static func loadExample(packageURL: URL, now: Date = Date()) throws -> SessionLoadBundle {
        let data = try Data(contentsOf: packageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(SessionTransferPackage.self, from: data)
        return load(package: SessionTimelineRebase.package(package, soEndedAt: now))
    }

    private static func makeBundle(
        manifest: SessionManifest,
        detections: [DetectionEvent],
        locations: [LocationSample],
        health: [HealthMetricSample],
        water: [WaterTemperatureSample],
        byteSize: Int64,
        mapFrame: MapTrackFrame?,
        cityName: String?
    ) -> SessionLoadBundle {
        let stats = SessionStatsBuilder.build(
            manifest: manifest,
            detections: detections,
            locations: locations,
            health: health,
            water: water
        )
        return SessionLoadBundle(
            manifest: manifest,
            detections: detections,
            locations: locations,
            health: health,
            water: water,
            stats: stats,
            byteSize: byteSize,
            mapFrame: mapFrame,
            cityName: cityName
        )
    }
}
