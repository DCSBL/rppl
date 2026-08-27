import Foundation

/// Compact WGS84 point for distilled map polylines (`derived/view.json`).
public struct MapCoordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(_ sample: LocationSample) {
        latitude = sample.latitude
        longitude = sample.longitude
    }
}

/// Session overview map display mode (averaged cable loop vs lap heatmap).
public enum SessionMapTrackStyle: String, Codable, Sendable, CaseIterable {
    case averaged
    case heatmap
}

/// Distilled session polylines for phone + Watch logbook maps.
public struct SessionMapTrackData: Codable, Equatable, Sendable {
    public var start: MapCoordinate
    public var averagedTrack: [MapCoordinate]
    public var heatmapTracks: [[MapCoordinate]]
    /// Parallel to `averagedTrack`; km/h when speed was usable at resample index.
    public var averagedSpeedKmh: [Double]?

    public init(
        start: MapCoordinate,
        averagedTrack: [MapCoordinate],
        heatmapTracks: [[MapCoordinate]],
        averagedSpeedKmh: [Double]? = nil
    ) {
        self.start = start
        self.averagedTrack = averagedTrack
        self.heatmapTracks = heatmapTracks
        self.averagedSpeedKmh = averagedSpeedKmh
    }

    public var hasRenderableTrack: Bool {
        averagedTrack.count >= 2 || heatmapTracks.contains { $0.count >= 2 }
    }

    /// All polylines for camera framing — union keeps zoom stable when toggling display mode.
    public var allFitCoordinates: [MapCoordinate] {
        var coords = averagedTrack
        for track in heatmapTracks where track.count >= 2 {
            coords.append(contentsOf: track)
        }
        if coords.isEmpty, averagedTrack.count == 1 {
            coords = [start]
        }
        return coords
    }
}
