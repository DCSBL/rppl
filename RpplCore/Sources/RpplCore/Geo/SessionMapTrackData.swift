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

/// Distilled session heatmap polylines for phone + Watch logbook maps.
public struct SessionMapTrackData: Codable, Equatable, Sendable {
    public var start: MapCoordinate
    public var heatmapTracks: [[MapCoordinate]]

    public init(start: MapCoordinate, heatmapTracks: [[MapCoordinate]]) {
        self.start = start
        self.heatmapTracks = heatmapTracks
    }

    public var hasRenderableTrack: Bool {
        heatmapTracks.contains { $0.count >= 2 }
    }

    public var allFitCoordinates: [MapCoordinate] {
        var coords: [MapCoordinate] = []
        for track in heatmapTracks where track.count >= 2 {
            coords.append(contentsOf: track)
        }
        if coords.isEmpty {
            coords = [start]
        }
        return coords
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case heatmapTracks
        case averagedTrack
        case averagedSpeedKmh
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(MapCoordinate.self, forKey: .start)
        heatmapTracks = try container.decodeIfPresent([[MapCoordinate]].self, forKey: .heatmapTracks) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(heatmapTracks, forKey: .heatmapTracks)
    }
}
