import Foundation

/// A session typed in by hand: no sensor streams, so these counts are the source of truth for its
/// derived stats (`SessionStatsBuilder`). Tracked sessions leave `SessionManifest.manual` nil.
public struct ManualEntry: Codable, Equatable, Sendable {
    public struct Tally: Codable, Equatable, Sendable {
        public var sets: Int
        public var laps: Int

        public init(sets: Int = 0, laps: Int = 0) {
            self.sets = sets
            self.laps = laps
        }
    }

    /// One per cable of the park (index = cable position); a single entry for an own or no location.
    public var tallies: [Tally]
    /// Estimated distance (laps x lap length); nil when a ridden cable has no known length.
    public var distanceM: Double?
    /// Park pin or picked spot. Centers the derived map frame, so park matching and visits work.
    public var location: ParkCoordinate?

    public init(tallies: [Tally] = [Tally()], distanceM: Double? = nil, location: ParkCoordinate? = nil) {
        self.tallies = tallies
        self.distanceM = distanceM
        self.location = location
    }

    public var setCount: Int { tallies.reduce(0) { $0 + $1.sets } }
    public var lapCount: Int { tallies.reduce(0) { $0 + $1.laps } }

    /// `laps x lap length` per ridden cable, tallies matched to cables by index. Nil when a ridden
    /// cable has no known length, or nothing was ridden.
    public static func distanceM(tallies: [Tally], cables: [ParkCable]) -> Double? {
        var total = 0.0
        for (index, tally) in tallies.enumerated() where tally.laps > 0 {
            guard cables.indices.contains(index), let lap = cables[index].lapLengthM else { return nil }
            total += Double(tally.laps) * lap
        }
        return total > 0 ? total : nil
    }
}

extension ParkCable {
    /// Distance of one lap: a loop cable is its length, a 2D cable is ridden there and back.
    public var lapLengthM: Double? {
        effectiveLengthM.map { direction == ParkCableDirection.twoD ? $0 * 2 : $0 }
    }
}
