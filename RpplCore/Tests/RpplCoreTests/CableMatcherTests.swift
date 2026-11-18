import Foundation
import Testing
@testable import RpplCore

struct CableMatcherTests {
    private let origin = ParkCoordinate(lat: 52.0, lon: 5.0)

    /// A coordinate `east` / `north` meters from the origin.
    private func at(east: Double, north: Double) -> ParkCoordinate {
        ParkCoordinate(lat: origin.lat + north / 110_574, lon: origin.lon + east / (111_320 * cos(origin.lat * .pi / 180)))
    }

    private func point(_ coordinate: ParkCoordinate) -> ParkCablePoint {
        ParkCablePoint(lat: coordinate.lat, lon: coordinate.lon)
    }

    /// A 600 x 200 m loop and a 2.0 line inside the park, 300 m south of the loop.
    private var cables: [ParkCable] {
        [
            ParkCable(direction: .counterClockwise, points: [
                point(at(east: 0, north: 0)), point(at(east: 600, north: 0)),
                point(at(east: 600, north: 200)), point(at(east: 0, north: 200)),
            ]),
            ParkCable(direction: .twoPointZero, points: [
                point(at(east: 0, north: -300)), point(at(east: 150, north: -300)),
            ]),
            ParkCable(direction: .clockwise),
        ]
    }

    private func track(from a: ParkCoordinate, to b: ParkCoordinate, offsetNorth: Double = 0, points: Int = 20) -> [ParkCoordinate] {
        (0..<points).map { step in
            let t = Double(step) / Double(points - 1)
            return ParkCoordinate(lat: a.lat + (b.lat - a.lat) * t + offsetNorth / 110_574, lon: a.lon + (b.lon - a.lon) * t)
        }
    }

    @Test func trackAlongTheLoopMatchesTheLoop() {
        let ride = track(from: at(east: 0, north: 0), to: at(east: 600, north: 0), offsetNorth: 4)
        #expect(CableMatcher.cableIndex(track: ride, cables: cables) == 0)
    }

    @Test func trackAlongTheClosingSegmentMatchesALoop() {
        let ride = track(from: at(east: 0, north: 200), to: at(east: 0, north: 0), offsetNorth: 0)
        #expect(CableMatcher.cableIndex(track: ride, cables: cables) == 0)
    }

    @Test func trackOnTheTwoPointZeroLineMatchesIt() {
        let ride = track(from: at(east: 0, north: -300), to: at(east: 150, north: -300), offsetNorth: -3)
        #expect(CableMatcher.cableIndex(track: ride, cables: cables) == 1)
    }

    @Test func farAwayOrShortTracksMatchNothing() {
        let far = track(from: at(east: 0, north: -100), to: at(east: 100, north: -100))
        #expect(CableMatcher.cableIndex(track: far, cables: cables) == nil)
        let short = Array(track(from: at(east: 0, north: 0), to: at(east: 600, north: 0)).prefix(4))
        #expect(CableMatcher.cableIndex(track: short, cables: cables) == nil)
    }

    @Test func cablesWithoutATraceAreNeverMatched() {
        let ride = track(from: at(east: 0, north: 0), to: at(east: 600, north: 0))
        #expect(CableMatcher.cableIndex(track: ride, cables: [ParkCable(direction: .clockwise)]) == nil)
        // Traced later: the same track now matches, without any stored result to refresh.
        let traced = [ParkCable(direction: .clockwise, points: [
            point(at(east: 0, north: 0)), point(at(east: 600, north: 0)), point(at(east: 300, north: 200)),
        ])]
        #expect(CableMatcher.cableIndex(track: ride, cables: traced) == 0)
    }

    @Test func manualSessionsUseTheirTallies() {
        let manual = ManualEntry(tallies: [ManualEntry.Tally(sets: 2), ManualEntry.Tally(), ManualEntry.Tally(laps: 1)])
        #expect(CableMatcher.riddenCableIndices(manual: manual, tracks: [], cables: cables) == [0, 2])
    }

    @Test func trackedSessionsUnionTheirMatches() {
        let tracks = [
            track(from: at(east: 0, north: 0), to: at(east: 600, north: 0)),
            track(from: at(east: 0, north: -300), to: at(east: 150, north: -300)),
            track(from: at(east: 0, north: -100), to: at(east: 100, north: -100)),
        ]
        #expect(CableMatcher.riddenCableIndices(manual: nil, tracks: tracks, cables: cables) == [0, 1])
    }

    @Test func riddenCablesCountOncePerYearAndDirection() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ year: Int) -> Date { calendar.date(from: DateComponents(year: year, month: 6, day: 1))! }
        let park = Park(id: "a", name: "a", location: origin, cables: cables)
        let rides: [(date: Date, parkId: String, cableIndices: Set<Int>)] = [
            (date(2026), "a", [0]), (date(2026), "a", [0, 1]), (date(2025), "a", [2]), (date(2026), "gone", [0]),
        ]
        let all = RiddenCables(rides: rides, parks: [park], calendar: calendar)
        #expect(all.count == 3)
        #expect(all.counterClockwise == 1 && all.twoPointZero == 1 && all.clockwise == 1)
        #expect(all.parks == [RiddenCables.Entry(parkId: "a", cableIndices: [0, 1, 2])])
        let year = RiddenCables(rides: rides, parks: [park], year: 2026, calendar: calendar)
        #expect(year.count == 2)
        #expect(year.clockwise == 0)
    }
}
