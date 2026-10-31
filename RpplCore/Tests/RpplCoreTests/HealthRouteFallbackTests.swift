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

    @Test func tracedCableIsUsed() {
        let points = [ParkCoordinate(lat: 1, lon: 1), ParkCoordinate(lat: 2, lon: 2)]
        let cable = ParkCable(points: points.map { ParkCablePoint(lat: $0.lat, lon: $0.lon) })
        let fallback = HealthRouteFallback.make(for: park(cables: [cable]))
        #expect(fallback.source == .cable)
        #expect(fallback.coordinates == points)
    }

    @Test func timestampsSpanTheWorkout() {
        let fallback = HealthRouteFallback(source: .park, coordinates: [location, location, location])
        let start = Date(timeIntervalSince1970: 1_000)
        let stamps = fallback.timestamps(from: start, to: start.addingTimeInterval(100))
        #expect(stamps == [start, start.addingTimeInterval(50), start.addingTimeInterval(100)])
    }
}
