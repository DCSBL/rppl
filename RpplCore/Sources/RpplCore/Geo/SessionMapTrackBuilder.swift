import Foundation

/// Build distilled session map polylines for `derived/view.json`.
public enum SessionMapTrackBuilder {
    public static let heatmapPointsPerSet = 32
    public static let maxHeatmapSets = 24

    public static func build(
        locations: [LocationSample],
        sets: [SetSegmentStats]
    ) -> SessionMapTrackData? {
        let setTracks = SetLocationFilter.tracks(from: locations, sets: sets)
            .filter { $0.count >= 2 }
        guard !setTracks.isEmpty else { return nil }
        guard let start = commonStart(from: setTracks) else { return nil }

        let heatmapTracks = setTracks.prefix(maxHeatmapSets).map { track in
            LocationSampleDownsampler.downsample(track, maxCount: heatmapPointsPerSet)
                .map(MapCoordinate.init)
        }

        return SessionMapTrackData(start: start, heatmapTracks: heatmapTracks)
    }

    static func commonStart(from tracks: [[LocationSample]]) -> MapCoordinate? {
        let starts = tracks.compactMap(\.first).map(MapCoordinate.init)
        guard !starts.isEmpty else { return nil }
        let latitudes = starts.map(\.latitude).sorted()
        let longitudes = starts.map(\.longitude).sorted()
        let mid = starts.count / 2
        return MapCoordinate(latitude: latitudes[mid], longitude: longitudes[mid])
    }
}
