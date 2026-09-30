import Foundation
import Testing
@testable import RpplCore

/// The arrival notification UI is behind `PARK_ARRIVAL_NOTIFICATIONS`; this pure planner stays
/// compiled and tested in every configuration so it doesn't rot while the feature is dark.
struct ParkArrivalPlannerTests {
    private func park(_ id: String, lat: Double, lon: Double = 5.0) -> Park {
        Park(
            id: id,
            name: id,
            location: ParkCoordinate(lat: lat, lon: lon),
            address: "\(id) street 1"
        )
    }

    private var parks: [Park] {
        [
            park("far", lat: 53.0),
            park("near", lat: 52.01),
            park("mid", lat: 52.5),
            park("favorite", lat: 51.0)
        ]
    }

    private let here = ParkCoordinate(lat: 52.0, lon: 5.0)

    @Test func favoritesComeFirstThenNearestOthers() {
        let ids = ParkArrivalPlanner.selectMonitoredParkIDs(
            favoriteIDs: ["favorite"], allParks: parks, currentLocation: here
        )
        #expect(ids == ["favorite", "near", "mid", "far"])
    }

    @Test func limitKeepsFavoritesAndFillsWithNearest() {
        let ids = ParkArrivalPlanner.selectMonitoredParkIDs(
            favoriteIDs: ["favorite"], allParks: parks, currentLocation: here, limit: 2
        )
        #expect(ids == ["favorite", "near"])
    }

    @Test func favoritesAreTrimmedToTheLimit() {
        let ids = ParkArrivalPlanner.selectMonitoredParkIDs(
            favoriteIDs: ["favorite", "far", "mid"], allParks: parks, currentLocation: here, limit: 2
        )
        #expect(ids.count == 2)
        #expect(Set(ids).isSubset(of: ["favorite", "far", "mid"]))
    }

    @Test func withoutLocationOnlyFavoritesAreMonitored() {
        let ids = ParkArrivalPlanner.selectMonitoredParkIDs(
            favoriteIDs: ["favorite"], allParks: parks, currentLocation: nil
        )
        #expect(ids == ["favorite"])
    }

    @Test func unknownFavoriteIDsAreIgnored() {
        let ids = ParkArrivalPlanner.selectMonitoredParkIDs(
            favoriteIDs: ["deleted-park"], allParks: parks, currentLocation: nil
        )
        #expect(ids.isEmpty)
    }

    @Test func zeroLimitSelectsNothing() {
        let ids = ParkArrivalPlanner.selectMonitoredParkIDs(
            favoriteIDs: ["favorite"], allParks: parks, currentLocation: here, limit: 0
        )
        #expect(ids.isEmpty)
    }

    @Test func defaultLimitStaysWithinCoreLocationRegionCap() {
        let many = (0..<50).map { park("park-\($0)", lat: 52.0 + Double($0) * 0.01) }
        let ids = ParkArrivalPlanner.selectMonitoredParkIDs(
            favoriteIDs: [], allParks: many, currentLocation: here
        )
        #expect(ids.count == ParkArrivalPlanner.regionLimit)
        #expect(ParkArrivalPlanner.regionLimit <= 20)
    }

    @Test func neverNotifiedAlwaysNotifies() {
        #expect(ParkArrivalPlanner.shouldNotify(lastNotifiedAt: nil))
    }

    @Test func staysQuietInsideCooldown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = now.addingTimeInterval(-(ParkArrivalPlanner.renotifyCooldown - 60))
        #expect(!ParkArrivalPlanner.shouldNotify(lastNotifiedAt: recent, now: now))
    }

    @Test func notifiesAgainOnceCooldownElapsed() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let exactly = now.addingTimeInterval(-ParkArrivalPlanner.renotifyCooldown)
        #expect(ParkArrivalPlanner.shouldNotify(lastNotifiedAt: exactly, now: now))
    }
}
