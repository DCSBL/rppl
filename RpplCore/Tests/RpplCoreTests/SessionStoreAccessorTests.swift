import Foundation
import Testing
@testable import RpplCore

@Suite("SessionFileStore accessors", .serialized)
struct SessionStoreAccessorTests {
    @Test func peekReturnsOnlyTheFirstSamples() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        try session.store.appendLocationSamples((0..<100).map { Samples.location($0) }, sessionId: session.sessionId)

        let peeked = try session.store.peekLocationSamples(sessionId: session.sessionId, limit: 5)

        #expect(peeked.map(\.timestamp) == (0..<5).map { Samples.time($0) })
    }

    @Test func peekingASessionWithoutLocationsIsEmptyNotAnError() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        #expect(try session.store.peekLocationSamples(sessionId: session.sessionId).isEmpty)
    }

    @Test func reanalyzingRebuildsTheDerivedViewFromRawAndKeepsTheCity() throws {
        let session = try TempSession.make(endedAt: Samples.time(120), state: .readyToTransfer)
        defer { session.cleanup() }
        let id = session.sessionId
        try session.store.appendDetection(Samples.detection(DetectionCodes.inactive, second: 0), sessionId: id)
        try session.store.appendLocationSamples((0..<120).map { Samples.location($0) }, sessionId: id)
        let first = try session.store.ensureDerivedView(sessionId: id)
        try session.store.updateDerivedCityName("Rotterdam", sessionId: id)

        let rebuilt = try session.store.reanalyzeSession(sessionId: id)

        #expect(rebuilt.stats.startedAt == first.stats.startedAt)
        #expect(rebuilt.cityName == "Rotterdam")
        #expect(try session.store.readDerivedView(sessionId: id)?.cityName == "Rotterdam")
    }

    @Test func theWaterTemperatureEstimateIsPersistedInTheManifest() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let estimate = ParkWaterTemperature(
            celsius: 18.8, observedAt: Samples.t0, stationName: "Krimpen aan de IJssel", providerName: "Rijkswaterstaat"
        )

        try session.store.updateWaterTemperatureEstimate(estimate, sessionId: session.sessionId)

        #expect(try session.store.readManifest(sessionId: session.sessionId).waterTemperatureEstimate == estimate)
    }

    @Test func locatingAPackageByIdFindsItOrSaysItIsMissing() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }

        let found = try SessionPackageLocator.directory(for: session.sessionId, in: session.root)
        let expected = try session.directory
        // The temp dir is a symlink on macOS (/var → /private/var); compare resolved paths.
        #expect(found.resolvingSymlinksInPath().path == expected.resolvingSymlinksInPath().path)
        #expect(throws: SessionStoreError.sessionNotFound("11111111-2222-3333-4444-555555555555")) {
            try SessionPackageLocator.directory(for: "11111111-2222-3333-4444-555555555555", in: session.root)
        }
    }

    @Test func locatingRejectsIdsThatCouldEscapeTheRoot() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        #expect(throws: SessionStoreError.self) {
            try SessionPackageLocator.directory(for: "../outside", in: session.root)
        }
    }
}

@Suite("GeoCentroid")
struct GeoCentroidTests {
    private func sample(_ lat: Double, _ lon: Double, accuracy: Double) -> LocationSample {
        LocationSample(timestamp: Samples.t0, latitude: lat, longitude: lon, horizontalAccuracy: accuracy)
    }

    @Test func noLocationsHasNoCentroid() {
        #expect(GeoCentroid.representative(from: []) == nil)
    }

    @Test func averagesThePoints() throws {
        let centroid = try #require(GeoCentroid.representative(from: [
            sample(50, 4, accuracy: 5), sample(52, 6, accuracy: 5)
        ]))
        #expect(centroid.latitude == 51)
        #expect(centroid.longitude == 5)
    }

    @Test func poorFixesDoNotPullTheCentroidAway() throws {
        let centroid = try #require(GeoCentroid.representative(from: [
            sample(52, 4, accuracy: 10), sample(52, 4, accuracy: 20), sample(10, 40, accuracy: 3_000)
        ]))
        #expect(centroid.latitude == 52)
        #expect(centroid.longitude == 4)
    }

    @Test func fallsBackToEveryPointWhenNoneIsUsable() throws {
        let centroid = try #require(GeoCentroid.representative(from: [
            sample(50, 4, accuracy: 800), sample(52, 6, accuracy: -1)
        ]))
        #expect(centroid.latitude == 51)
    }
}
