import Foundation

/// A single ambient water-temperature reading resolved for a park's `ParkWaterTemperatureSource`.
/// Always an estimate: it comes from the nearest official monitoring station for that water body,
/// not a sensor at the park itself. Distinct from the Watch Ultra's in-session submersion-sensor
/// water temperature (`CMWaterSubmersionManager`) — this one is a network estimate shown on the
/// park screen, unrelated to what happens during a recording.
public struct ParkWaterTemperature: Codable, Equatable, Sendable {
    public var celsius: Double
    public var observedAt: Date
    /// Human-readable station name for attribution, e.g. "Hoek van Holland".
    public var stationName: String
    /// Human-readable source name for attribution, e.g. "Rijkswaterstaat".
    public var providerName: String

    public init(celsius: Double, observedAt: Date, stationName: String, providerName: String) {
        self.celsius = celsius
        self.observedAt = observedAt
        self.stationName = stationName
        self.providerName = providerName
    }

    /// A reading older than this is stale (some stations report infrequently or have stopped).
    public static let maxReadingAge: TimeInterval = 48 * 60 * 60

    public func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(observedAt) <= Self.maxReadingAge
    }
}

/// Water temperature shown on the Watch: real submersion-sensor readings win; the park-station
/// estimate only stands in until the Watch has measured something (or when it never can).
public struct WaterTemperatureDisplay: Equatable, Sendable {
    public var celsius: Double
    public var isEstimate: Bool

    public static func resolve(measuredAverage: Double?, estimate: ParkWaterTemperature?) -> WaterTemperatureDisplay? {
        if let measuredAverage { return WaterTemperatureDisplay(celsius: measuredAverage, isEstimate: false) }
        if let estimate { return WaterTemperatureDisplay(celsius: estimate.celsius, isEstimate: true) }
        return nil
    }
}

/// Fetches the latest reading for a `ParkWaterTemperatureSource`. One concrete type per
/// `provider` string, implemented in the app layer (network access isn't pure) — Core only
/// defines the shape, so callers can stay generic over providers/countries without knowing about
/// URLSession or any specific API.
public protocol ParkWaterTemperatureFetching: Sendable {
    func fetch(_ source: ParkWaterTemperatureSource) async -> ParkWaterTemperature?
}
