import Foundation

/// A single ambient water-temperature reading resolved for a park's `ParkWaterTemperatureSource`.
/// Always an estimate: it comes from the nearest official monitoring station for that water body,
/// not a sensor at the park itself. Distinct from the Watch Ultra's in-session submersion-sensor
/// water temperature (`CMWaterSubmersionManager`) — this one is a network estimate shown on the
/// park screen and in the arrival notification, unrelated to what happens during a recording.
public struct ParkWaterTemperature: Equatable, Sendable {
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
}

/// Fetches the latest reading for a `ParkWaterTemperatureSource`. One concrete type per
/// `provider` string, implemented in the app layer (network access isn't pure) — Core only
/// defines the shape, so callers can stay generic over providers/countries without knowing about
/// URLSession or any specific API.
public protocol ParkWaterTemperatureFetching: Sendable {
    func fetch(_ source: ParkWaterTemperatureSource) async -> ParkWaterTemperature?
}
