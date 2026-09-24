import Foundation

/// Fast on-disk view for list / detail first paint (`derived/view.json`).
///
/// `cityName` is phone-optional and outside Watch↔phone match.
public struct DerivedSessionView: Codable, Equatable, Sendable {
    public var analyzerVersion: Int
    public var stats: SessionStats
    /// Device-agnostic map framing; phone computes camera for its view size.
    public var mapFrame: MapTrackFrame?
    /// Distilled heatmap polylines for session map; synced to Watch.
    public var mapTracks: SessionMapTrackData?
    /// Location label shown in lists/detail: the linked park's name, else the phone-only
    /// reverse-geocoded city. Written by the phone; pushed to Watch.
    public var cityName: String?

    public init(
        analyzerVersion: Int = SessionAnalyzer.version,
        stats: SessionStats,
        mapFrame: MapTrackFrame? = nil,
        mapTracks: SessionMapTrackData? = nil,
        cityName: String? = nil
    ) {
        self.analyzerVersion = analyzerVersion
        self.stats = stats
        self.mapFrame = mapFrame
        self.mapTracks = mapTracks
        self.cityName = cityName
    }

    public var isCurrentAnalyzer: Bool {
        analyzerVersion == SessionAnalyzer.version
    }
}
