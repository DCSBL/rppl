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
    public var mapTracks: SessionMapTrackData? { derived.mapTracks }
    public var cityName: String? { derived.cityName }
}

public enum SessionLoader {
    public static func load(store: SessionFileStore, sessionId: String) throws -> SessionLoadBundle {
        try store.migrateIfNeeded(sessionId: sessionId)
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
            let mapTracks = SessionMapTrackBuilder.build(locations: locations, sets: stats.sets)
            try store.writeDerivedView(
                DerivedSessionView(
                    analyzerVersion: SessionAnalyzer.version,
                    stats: stats,
                    mapFrame: mapFrame,
                    mapTracks: mapTracks,
                    cityName: cityName
                ),
                sessionId: sessionId
            )
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
    public static func load(package: SessionTransferPackage) throws -> SessionLoadBundle {
        try SessionImportLimits.validateArrayCount(package.detections, limit: SessionImportLimits.maxDetections, label: "detections")
        try SessionImportLimits.validateArrayCount(package.locations, limit: SessionImportLimits.maxLocations, label: "locations")
        try SessionImportLimits.validateArrayCount(package.motion, limit: SessionImportLimits.maxMotionSamples, label: "motion")
        try SessionImportLimits.validateArrayCount(package.health, limit: SessionImportLimits.maxHealthSamples, label: "health")
        try SessionImportLimits.validateArrayCount(package.water, limit: SessionImportLimits.maxWaterSamples, label: "water")
        try SessionImportLimits.validateArrayCount(package.battery, limit: SessionImportLimits.maxBatterySamples, label: "battery")
        try SessionImportLimits.validateArrayCount(package.altitude, limit: SessionImportLimits.maxAltitudeSamples, label: "altitude")

        return makeBundle(
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
        let data = try SessionImportLimits.readBoundedFile(at: packageURL)
        let package = try SessionImportLimits.decodeTransferPackage(from: data)
        return try load(package: package)
    }

    /// Bundled empty-state example: shift timeline so `endedAt` is `now` (relative gaps kept).
    public static func loadExample(packageURL: URL, now: Date = Date()) throws -> SessionLoadBundle {
        let data = try SessionImportLimits.readBoundedFile(at: packageURL)
        let package = try SessionImportLimits.decodeTransferPackage(from: data)
        return try loadExample(package: package, now: now)
    }

    /// Same, from an already decoded package (see `ExampleSessionPreload`).
    ///
    /// A compiled package (`ExampleSessionCompiler`) carries current-analyzer stats in `derived`
    /// and is used as is; anything else is analyzed from its raw streams.
    public static func loadExample(package: SessionTransferPackage, now: Date = Date()) throws -> SessionLoadBundle {
        let shifted = SessionTimelineRebase.package(package, soEndedAt: now)
        guard let derived = shifted.derived, derived.isCurrentAnalyzer else {
            return try load(package: shifted)
        }
        return SessionLoadBundle(
            manifest: shifted.manifest,
            detections: shifted.detections,
            locations: shifted.locations,
            health: shifted.health,
            water: shifted.water,
            stats: derived.stats,
            byteSize: 0,
            mapFrame: derived.mapFrame,
            cityName: derived.cityName
        )
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
