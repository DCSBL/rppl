import Foundation
import Testing
@testable import RpplCore

@Suite("SessionAnonymizer")
struct SessionAnonymizerTests {
    private static let started = Date(timeIntervalSince1970: 1_790_000_000)

    private static func locations() -> [LocationSample] {
        (0..<20).map { index in
            LocationSample(
                timestamp: started.addingTimeInterval(Double(index)),
                latitude: 52.3702 + Double(index) * 0.0001,
                longitude: 4.8952 + Double(index) * 0.00015,
                altitude: 1.5,
                horizontalAccuracy: 5,
                verticalAccuracy: 8,
                speed: 7.5,
                course: 90
            )
        }
    }

    private static func package() -> SessionTransferPackage {
        let manifest = SessionManifest(
            sessionId: "original-session-id",
            testerId: "tester-6F2A",
            appVersion: "1.2",
            buildNumber: "34",
            watchModel: "Watch7,12",
            systemVersion: "26.0",
            startedAt: started,
            endedAt: started.addingTimeInterval(600),
            transferState: .acknowledged,
            waterTemperatureAvailable: true,
            activityCode: "wakeboard",
            wristLocation: "left",
            crownOrientation: "right",
            weather: SessionWeather(temperatureCelsius: 17, humidityPercent: 60),
            waterTemperatureEstimate: ParkWaterTemperature(
                celsius: 15.5,
                observedAt: started,
                stationName: "Hoek van Holland",
                providerName: "Rijkswaterstaat"
            ),
            parkId: "dutch-water-dreams",
            parkIdSource: SessionParkSource.auto,
            lastTransferError: "/var/mobile/Containers/Data/Application/AB12/Documents/Duco"
        )
        let places = locations()
        let derived = DerivedSessionView(
            stats: SessionStatsBuilder.build(manifest: manifest, detections: [], locations: places, health: []),
            mapFrame: MapTrackFitter.frame(locations: places.map { (latitude: $0.latitude, longitude: $0.longitude) }),
            mapTracks: SessionMapTrackData(
                start: MapCoordinate(latitude: 52.3702, longitude: 4.8952),
                heatmapTracks: []
            ),
            cityName: "Amsterdam"
        )
        return SessionTransferPackage(
            manifest: manifest,
            detections: [Samples.detection("riding", second: 3)],
            locations: places,
            health: [HealthMetricSample(timestamp: started, heartRateBPM: 130)],
            battery: [BatterySample(timestamp: started, level: 0.8, state: BatteryStateCodes.unplugged)],
            derived: derived
        )
    }

    @Test func redactsPersonalStrings() {
        let manifest = SessionAnonymizer.anonymized(Self.package()).manifest
        #expect(manifest.testerId == "REDACTEDREDACTEDREDACTED")
        #expect(manifest.waterTemperatureEstimate?.stationName == SessionAnonymizer.redacted)
        #expect(manifest.waterTemperatureEstimate?.providerName == SessionAnonymizer.redacted)
        #expect(manifest.lastTransferError == SessionAnonymizer.redacted)
        #expect(manifest.waterTemperatureEstimate?.celsius == 15.5)
    }

    @Test func leavesAbsentOptionalStringsAbsent() {
        var package = Self.package()
        package.manifest.waterTemperatureEstimate = nil
        package.manifest.lastTransferError = nil
        let manifest = SessionAnonymizer.anonymized(package).manifest
        #expect(manifest.waterTemperatureEstimate == nil)
        #expect(manifest.lastTransferError == nil)
    }

    @Test func unlinksThePark() {
        let manifest = SessionAnonymizer.anonymized(Self.package()).manifest
        #expect(manifest.parkId == nil)
        #expect(manifest.parkIdSource == nil)
    }

    @Test func keepsWhatAnalysisNeeds() {
        let original = Self.package()
        let copy = SessionAnonymizer.anonymized(original)
        #expect(copy.manifest.startedAt == original.manifest.startedAt)
        #expect(copy.manifest.endedAt == original.manifest.endedAt)
        #expect(copy.manifest.watchModel == original.manifest.watchModel)
        #expect(copy.manifest.systemVersion == original.manifest.systemVersion)
        #expect(copy.manifest.weather == original.manifest.weather)
        #expect(copy.manifest.wristLocation == original.manifest.wristLocation)
        #expect(copy.detections == original.detections)
        #expect(copy.health == original.health)
        #expect(copy.battery == original.battery)
    }

    @Test func givesTheCopyItsOwnSessionId() {
        let original = Self.package()
        let first = SessionAnonymizer.anonymized(original)
        let second = SessionAnonymizer.anonymized(original)
        #expect(first.manifest.sessionId != original.manifest.sessionId)
        #expect(first.manifest.sessionId != second.manifest.sessionId)
        #expect(SessionIdValidator.isValid(first.manifest.sessionId))
        #expect(SessionAnonymizer.anonymized(original, sessionId: "fixed").manifest.sessionId == "fixed")
    }

    /// The sidecar holds the real map frame, track and city. The importer rebuilds it from raw.
    @Test func dropsTheDerivedView() {
        #expect(Self.package().derived != nil)
        #expect(SessionAnonymizer.anonymized(Self.package()).derived == nil)
    }

    @Test func movesTheSessionToTheOriginAndKeepsTheRestOfEachFix() throws {
        let original = Self.package().locations
        let moved = SessionAnonymizer.anonymized(Self.package()).locations
        #expect(moved.count == original.count)

        let meanLatitude = moved.map(\.latitude).reduce(0, +) / Double(moved.count)
        let meanLongitude = moved.map(\.longitude).reduce(0, +) / Double(moved.count)
        #expect(abs(meanLatitude) < 1e-6)
        #expect(abs(meanLongitude) < 1e-6)

        for (before, after) in zip(original, moved) {
            #expect(abs(after.latitude) < 0.01)
            #expect(abs(after.longitude) < 0.01)
            #expect(after.timestamp == before.timestamp)
            #expect(after.altitude == before.altitude)
            #expect(after.horizontalAccuracy == before.horizontalAccuracy)
            #expect(after.verticalAccuracy == before.verticalAccuracy)
            #expect(after.speed == before.speed)
            #expect(after.course == before.course)
        }
    }

    @Test func noFixesStillAnonymizes() {
        var package = Self.package()
        package.locations = []
        let copy = SessionAnonymizer.anonymized(package)
        #expect(copy.locations.isEmpty)
        #expect(copy.derived == nil)
        #expect(copy.manifest.testerId == SessionAnonymizer.redacted)
    }

    @Test func sharedFileCarriesNoPersonalDataAndOpens() throws {
        let data = try SessionShareExport.encode(SessionAnonymizer.anonymized(Self.package(), sessionId: "shared-copy"))
        let text = try #require(String(data: data, encoding: .utf8))

        for leak in [
            "tester-6F2A", "original-session-id", "Hoek van Holland", "Rijkswaterstaat",
            "dutch-water-dreams", "Amsterdam", "Duco", "52.37",
        ] {
            #expect(!text.contains(leak), "file still contains \(leak)")
        }
        #expect(text.contains(SessionAnonymizer.redacted))

        // The importer's own decoder opens it, and no coordinate is anywhere near the real park.
        let opened = try SessionImportLimits.decodeTransferPackage(from: data)
        #expect(opened.manifest.sessionId == "shared-copy")
        #expect(opened.locations.count == Self.locations().count)
        for sample in opened.locations {
            #expect(abs(sample.latitude) < 1)
            #expect(abs(sample.longitude) < 1)
        }
        let bundle = try SessionLoader.load(package: opened)
        #expect(bundle.locations.count == opened.locations.count)
    }

    /// The whole point of moving by rotation: a real park day reads the same after the move.
    @Test(arguments: SessionFixture.names)
    func statsOfARealSessionDoNotChange(name: String) throws {
        let fixture = try SessionFixture.load(name)
        let before = fixture.timeOrderedStats()
        let moved = SessionAnonymizer.recentered(fixture.locations)
        let after = SessionStatsBuilder.build(
            manifest: fixture.manifest,
            detections: DetectionEngine.replay(locations: moved),
            locations: moved,
            health: []
        )

        #expect(!before.sets.isEmpty)
        #expect(after.setCount == before.setCount)
        #expect(after.sets.map(\.lapCount) == before.sets.map(\.lapCount))
        #expect(after.sets.map(\.startedAt) == before.sets.map(\.startedAt))
        #expect(after.sets.map(\.endedAt) == before.sets.map(\.endedAt))
        #expect(abs(after.totalDistanceMeters - before.totalDistanceMeters) < 0.01)
        for (setBefore, setAfter) in zip(before.sets, after.sets) {
            #expect(abs(setAfter.distanceMeters - setBefore.distanceMeters) < 0.01)
        }
    }
}
