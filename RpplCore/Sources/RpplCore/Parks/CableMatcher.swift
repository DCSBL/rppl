import Foundation

/// Which cable of a park a track follows, from the traced cable lines. A session stores its park but not
/// its cable, so the cable is worked out again from the track whenever it is needed: a park traced or
/// retraced later is matched without touching the sessions.
public enum CableMatcher {
    /// Fewer points than this say too little about which cable it was.
    public static let minimumTrackPoints = 5
    /// A track follows a cable when half of its points lie within this distance of the cable line.
    public static let maxMedianDistanceM = 15.0

    /// Index into `cables` of the closest traced cable, nil when the track is too short or no cable is close
    /// enough. Cables without a trace (fewer than two points) are never matched. On a tie the lower index wins.
    public static func cableIndex(track: [ParkCoordinate], cables: [ParkCable]) -> Int? {
        guard track.count >= minimumTrackPoints, let origin = track.first else { return nil }
        let project = Projection(origin: origin)
        let points = track.map(project.xy)
        var best: (index: Int, median: Double)?
        for (index, cable) in cables.enumerated() {
            guard let line = cable.points, line.count >= 2 else { continue }
            var path = line.map { project.xy($0.coordinate) }
            if cable.direction?.isLoop == true, path.count >= 3 { path.append(path[0]) }
            let distances = points.map { distance(from: $0, to: path) }.sorted()
            let median = distances[distances.count / 2]
            if median <= maxMedianDistanceM, median < (best?.median ?? .infinity) {
                best = (index, median)
            }
        }
        return best?.index
    }

    /// The cables a session rode: typed-in sessions by their per-cable tallies (index = cable position),
    /// tracked sessions by matching each riding track.
    public static func riddenCableIndices(
        manual: ManualEntry?, tracks: [[ParkCoordinate]], cables: [ParkCable]
    ) -> Set<Int> {
        if let manual {
            return Set(manual.tallies.indices.filter { index in
                cables.indices.contains(index) && ((manual.tallies[index].sets ?? 0) > 0 || (manual.tallies[index].laps ?? 0) > 0)
            })
        }
        return Set(tracks.compactMap { cableIndex(track: $0, cables: cables) })
    }

    private struct Projection {
        let origin: ParkCoordinate
        private let metersPerDegreeLon: Double

        init(origin: ParkCoordinate) {
            self.origin = origin
            metersPerDegreeLon = 111_320 * cos(origin.lat * .pi / 180)
        }

        func xy(_ coordinate: ParkCoordinate) -> (x: Double, y: Double) {
            ((coordinate.lon - origin.lon) * metersPerDegreeLon, (coordinate.lat - origin.lat) * 110_574)
        }
    }

    private static func distance(from point: (x: Double, y: Double), to path: [(x: Double, y: Double)]) -> Double {
        var best = Double.greatestFiniteMagnitude
        for index in 1..<path.count {
            let a = path[index - 1]
            let b = path[index]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared)) : 0
            best = min(best, hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy)))
        }
        return best
    }
}

/// Cables ridden over a set of sessions, grouped per park and counted per direction.
public struct RiddenCables: Equatable, Sendable {
    /// A session with the cables it rode.
    public struct Ride: Equatable, Sendable {
        public var date: Date
        public var parkId: String
        public var cableIndices: Set<Int>

        public init(date: Date, parkId: String, cableIndices: Set<Int>) {
            self.date = date
            self.parkId = parkId
            self.cableIndices = cableIndices
        }
    }

    public struct Entry: Equatable, Sendable {
        public var parkId: String
        /// Indices into the park's `cables`, ascending.
        public var cableIndices: [Int]
    }

    /// Parks sorted by id.
    public var parks: [Entry] = []
    public var counterClockwise = 0
    public var clockwise = 0
    public var twoPointZero = 0

    public var count: Int { parks.reduce(0) { $0 + $1.cableIndices.count } }

    public init() {}

    /// `rides`: one entry per session, with the cable indices it rode. A cable counts once however often it
    /// was ridden; a cable index the park no longer has is skipped. `year` nil = all time.
    public init(
        rides: [Ride],
        parks: [Park],
        year: Int? = nil,
        calendar: Calendar = .current
    ) {
        var byPark: [String: Set<Int>] = [:]
        for ride in rides {
            if let year, calendar.component(.year, from: ride.date) != year { continue }
            byPark[ride.parkId, default: []].formUnion(ride.cableIndices)
        }
        let catalog = Dictionary(parks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (parkId, indices) in byPark.sorted(by: { $0.key < $1.key }) {
            guard let cables = catalog[parkId]?.cables else { continue }
            let valid = indices.filter { cables.indices.contains($0) }.sorted()
            guard !valid.isEmpty else { continue }
            self.parks.append(Entry(parkId: parkId, cableIndices: valid))
            for index in valid {
                switch cables[index].direction {
                case .some(.counterClockwise): counterClockwise += 1
                case .some(.clockwise): clockwise += 1
                case .some(.twoPointZero): twoPointZero += 1
                default: break
                }
            }
        }
    }
}
