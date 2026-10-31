import Foundation
import Testing
@testable import RpplCore

struct HealthRouteFallbackTests {
    private let location = ParkCoordinate(lat: 52, lon: 5)

    private func park(cables: [ParkCable]?) -> Park {
        Park(id: "p", name: "P", location: location, cables: cables)
    }

    @Test func thinRoutesNeedTheFallback() {
        #expect(HealthRouteFallback.needsFallback(usableFixCount: 0))
        #expect(HealthRouteFallback.needsFallback(usableFixCount: HealthRouteFallback.minimumRealFixes - 1))
        #expect(!HealthRouteFallback.needsFallback(usableFixCount: HealthRouteFallback.minimumRealFixes))
    }

    @Test func parkWithoutCableFallsBackToTheLocation() {
        let fallback = HealthRouteFallback.make(for: park(cables: nil))
        #expect(fallback.source == .park)
        #expect(fallback.coordinates == [location, location])
    }

    @Test func cableStartIsThePin() {
        let points = [
            ParkCablePoint(lat: 1, lon: 1),
            ParkCablePoint(lat: 2, lon: 2, start: true),
            ParkCablePoint(lat: 3, lon: 3)
        ]
        let fallback = HealthRouteFallback.make(for: park(cables: [ParkCable(points: points)]))
        let start = ParkCoordinate(lat: 2, lon: 2)
        #expect(fallback.source == .cableStart)
        #expect(fallback.coordinates == [start, start])
    }

    @Test func cableWithoutPointsFallsBackToThePark() {
        let fallback = HealthRouteFallback.make(for: park(cables: [ParkCable(name: "empty")]))
        #expect(fallback.source == .park)
    }

    @Test func timestampsSpanTheWorkout() {
        let fallback = HealthRouteFallback(source: .park, coordinates: [location, location, location])
        let start = Date(timeIntervalSince1970: 1_000)
        let stamps = fallback.timestamps(from: start, to: start.addingTimeInterval(100))
        #expect(stamps == [start, start.addingTimeInterval(50), start.addingTimeInterval(100)])
    }
}
