import Foundation

/// Fast on-disk view for list / detail first paint (`derived/view.json`).
///
/// `cityName` is phone-optional and outside Watch↔phone match.
public struct DerivedSessionView: Codable, Equatable, Sendable {
    public var analyzerVersion: Int
    public var stats: SessionStats
    /// Device-agnostic map framing; phone computes camera for its view size.
    public var mapFrame: MapTrackFrame?
    /// Phone-only reverse-geocode; omitted on Watch.
    public var cityName: String?

    public init(
        analyzerVersion: Int = SessionAnalyzer.version,
        stats: SessionStats,
        mapFrame: MapTrackFrame? = nil,
        cityName: String? = nil
    ) {
        self.analyzerVersion = analyzerVersion
        self.stats = stats
        self.mapFrame = mapFrame
        self.cityName = cityName
    }

    public var isCurrentAnalyzer: Bool {
        analyzerVersion == SessionAnalyzer.version
    }
}
