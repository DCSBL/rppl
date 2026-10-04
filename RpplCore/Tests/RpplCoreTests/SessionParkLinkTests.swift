import Foundation
import Testing
@testable import RpplCore

@Suite("Session park link", .serialized)
struct SessionParkLinkTests {
    private let park = Park(id: "a", name: "Park A", location: ParkCoordinate(lat: 52.0, lon: 4.0))
    private let other = Park(id: "b", name: "Park B", location: ParkCoordinate(lat: 53.0, lon: 5.0))

    private struct Fixture {
        let store: SessionFileStore
        let id: String
        let root: URL
    }

    private func makeStore() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "Watch7,1", systemVersion: "26.0"
        )
        _ = try store.createSession(manifest: manifest)
        let stats = SessionStats(
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            totalDuration: 1,
            totalDistanceMeters: 0,
            activeEnergyKilocalories: nil,
            setCount: 0,
            ridingDuration: 0,
            inactiveDuration: 1,
            ridingInactiveRatio: 0,
            sets: []
        )
        try store.writeDerivedView(DerivedSessionView(stats: stats, cityName: "Almere"), sessionId: manifest.sessionId)
        return Fixture(store: store, id: manifest.sessionId, root: root)
    }

    @Test func newManifestHasNoParkFields() throws {
        let manifest = SessionManifest(
            testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "W", systemVersion: "26"
        )
        #expect(manifest.parkId == nil && manifest.parkIdSource == nil)
    }

    @Test func autoLinksNearestParkAndSetsLabel() throws {
        let fixture = try makeStore()
        let (store, id, root) = (fixture.store, fixture.id, fixture.root)
        defer { try? FileManager.default.removeItem(at: root) }

        let linked = try store.linkPark(sessionId: id, center: ParkCoordinate(lat: 52.001, lon: 4.0), parks: [park, other])
        #expect(linked?.id == "a")
        let manifest = try store.readManifest(sessionId: id)
        #expect(manifest.parkId == "a" && manifest.parkIdSource == SessionParkSource.auto)
        #expect(try store.readDerivedView(sessionId: id)?.cityName == "Park A")
    }

    @Test func noParkNearbyKeepsCity() throws {
        let fixture = try makeStore()
        let (store, id, root) = (fixture.store, fixture.id, fixture.root)
        defer { try? FileManager.default.removeItem(at: root) }

        let linked = try store.linkPark(sessionId: id, center: ParkCoordinate(lat: 10, lon: 10), parks: [park])
        #expect(linked == nil)
        #expect(try store.readManifest(sessionId: id).parkId == nil)
        #expect(try store.readDerivedView(sessionId: id)?.cityName == "Almere")
    }

    @Test func storedLinkIsKeptOverNearest() throws {
        let fixture = try makeStore()
        let (store, id, root) = (fixture.store, fixture.id, fixture.root)
        defer { try? FileManager.default.removeItem(at: root) }

        try store.linkPark(sessionId: id, center: park.location, parks: [park, other])
        let linked = try store.linkPark(sessionId: id, center: other.location, parks: [park, other])
        #expect(linked?.id == "a")
    }

    @Test func manualNoParkSticksAndClearsLabel() throws {
        let fixture = try makeStore()
        let (store, id, root) = (fixture.store, fixture.id, fixture.root)
        defer { try? FileManager.default.removeItem(at: root) }

        try store.linkPark(sessionId: id, center: park.location, parks: [park])
        try store.setManualPark(nil, sessionId: id)
        let linked = try store.linkPark(sessionId: id, center: park.location, parks: [park])
        #expect(linked == nil)
        let manifest = try store.readManifest(sessionId: id)
        #expect(manifest.parkId == nil && manifest.parkIdSource == SessionParkSource.manual)
        #expect(try store.readDerivedView(sessionId: id)?.cityName == nil)
    }

    @Test func manualParkWins() throws {
        let fixture = try makeStore()
        let (store, id, root) = (fixture.store, fixture.id, fixture.root)
        defer { try? FileManager.default.removeItem(at: root) }

        try store.setManualPark(other, sessionId: id)
        let linked = try store.linkPark(sessionId: id, center: park.location, parks: [park, other])
        #expect(linked?.id == "b")
        #expect(try store.readDerivedView(sessionId: id)?.cityName == "Park B")
    }
}
