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

    /// A past session only accepts station readings this close before its start or after its end.
    public static let maxHistoryOffset: TimeInterval = 24 * 60 * 60

    /// Time range to ask a station for when looking up a past session's water temperature.
    public static func historyWindow(from start: Date, to end: Date) -> ClosedRange<Date> {
        start.addingTimeInterval(-maxHistoryOffset)...end.addingTimeInterval(maxHistoryOffset)
    }

    /// The latest sample, or with a `target` the one closest to it. `nil` when there are none.
    static func pick(from samples: [WaterTemperatureSample], target: Date?) -> WaterTemperatureSample? {
        guard let target else { return samples.max { $0.timestamp < $1.timestamp } }
        return samples.min { abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target)) }
    }
}

extension Date {
    func midpoint(to other: Date) -> Date { addingTimeInterval(other.timeIntervalSince(self) / 2) }
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

    /// Reading from the station closest to the middle of a past session, at most
    /// `ParkWaterTemperature.maxHistoryOffset` outside it. `nil` when the station has none.
    func fetchHistorical(_ source: ParkWaterTemperatureSource, from start: Date, to end: Date) async
        -> ParkWaterTemperature?
}

extension ParkWaterTemperatureFetching {
    public func fetchHistorical(
        _ source: ParkWaterTemperatureSource, from start: Date, to end: Date
    ) async -> ParkWaterTemperature? {
        nil
    }
}
