import Foundation

public struct SessionLoadBundle: Sendable {
    public let manifest: SessionManifest
    public let detections: [DetectionEvent]
    public let locations: [LocationSample]
    public let health: [HealthMetricSample]
    public let water: [WaterTemperatureSample]
    public let stats: SessionStats
    public let byteSize: Int64

    public init(
        manifest: SessionManifest,
        detections: [DetectionEvent],
        locations: [LocationSample],
        health: [HealthMetricSample],
        water: [WaterTemperatureSample],
        stats: SessionStats,
        byteSize: Int64
    ) {
        self.manifest = manifest
        self.detections = detections
        self.locations = locations
        self.health = health
        self.water = water
        self.stats = stats
        self.byteSize = byteSize
    }
}

public enum SessionLoader {
    public static func load(store: SessionFileStore, sessionId: String) throws -> SessionLoadBundle {
        let manifest = try store.readManifest(sessionId: sessionId)
        let detections = try store.readDetections(sessionId: sessionId)
        let locations = try store.readLocationSamples(sessionId: sessionId)
        let health = try store.readHealthSamples(sessionId: sessionId)
        let water = try store.readWaterTemperatureSamples(sessionId: sessionId)
        let stats = SessionStatsBuilder.build(
            manifest: manifest,
            detections: detections,
            locations: locations,
            health: health,
            water: water
        )
        let byteSize = try store.sessionByteSize(sessionId: sessionId)
        return SessionLoadBundle(
            manifest: manifest,
            detections: detections,
            locations: locations,
            health: health,
            water: water,
            stats: stats,
            byteSize: byteSize
        )
    }
}
