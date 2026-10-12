import Foundation
import Testing
@testable import RpplCore

struct ParkWidgetSnapshotTests {
    private func park(_ id: String, _ name: String) -> Park {
        Park(id: id, name: name, location: ParkCoordinate(lat: 52, lon: 4))
    }

    private var parks: [Park] { [park("a", "Alpha"), park("b", "Bravo"), park("c", "Charlie"), park("d", "Delta")] }

    @Test func mostVisitedPicksHighestCount() {
        let snapshot = ParkWidgetSnapshot(visits: ["a": 1, "c": 5, "d": 5])
        #expect(snapshot.mostVisited(in: parks)?.id == "c")
    }

    @Test func mostVisitedIsNilWithoutVisits() {
        #expect(ParkWidgetSnapshot(favoriteIDs: ["a"]).mostVisited(in: parks) == nil)
    }

    @Test func topFavoritesSortsByVisitsThenName() {
        let snapshot = ParkWidgetSnapshot(favoriteIDs: ["d", "a", "b", "c"], visits: ["c": 4, "b": 2, "a": 2])
        #expect(snapshot.topFavorites(in: parks, limit: 3).map(\.id) == ["c", "a", "b"])
    }

    @Test func topFavoritesIgnoresUnstarredAndMissingParks() {
        let snapshot = ParkWidgetSnapshot(favoriteIDs: ["gone", "b"], visits: ["a": 9])
        #expect(snapshot.topFavorites(in: parks, limit: 6).map(\.id) == ["b"])
    }

    @Test func storeRoundTripsAndReportsChange() throws {
        let suite = "ParkWidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ParkWidgetSnapshotStore.load(from: defaults) == ParkWidgetSnapshot())
        #expect(ParkWidgetSnapshotStore.update(in: defaults) { $0.favoriteIDs = ["a"] })
        #expect(!ParkWidgetSnapshotStore.update(in: defaults) { $0.favoriteIDs = ["a"] })
        #expect(ParkWidgetSnapshotStore.load(from: defaults).favoriteIDs == ["a"])
    }

    @Test func unreadableStoreFallsBackToEmpty() throws {
        let suite = "ParkWidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("nope".utf8), forKey: ParkWidgetSnapshotStore.key)
        #expect(ParkWidgetSnapshotStore.load(from: defaults) == ParkWidgetSnapshot())
    }
}
