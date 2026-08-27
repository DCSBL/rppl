import Foundation
import Testing
@testable import RpplCore

@Suite("DerivedSessionView")
struct DerivedSessionViewTests {
    @Test func ensureCreatesSidecarFromLegacyFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DerivedEnsure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = SessionManifest(
            schemaVersion: 4,
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch7,1",
            systemVersion: "26.0",
            startedAt: start
        )
        _ = try store.createSession(manifest: manifest)
        try store.appendDetection(
            DetectionEvent(
                code: DetectionCodes.inactive,
                timestamp: start,
                reason: "session_start",
                detectorId: "session_start"
            ),
            sessionId: manifest.sessionId
        )
        try store.appendLocationSamples([
            LocationSample(
                timestamp: start.addingTimeInterval(1),
                latitude: 52.1,
                longitude: 5.1,
                horizontalAccuracy: 5,
                speed: 0
            ),
            LocationSample(
                timestamp: start.addingTimeInterval(2),
                latitude: 52.101,
                longitude: 5.1,
                horizontalAccuracy: 5,
                speed: 4
            ),
        ], sessionId: manifest.sessionId)

        #expect(try store.readDerivedView(sessionId: manifest.sessionId) == nil)

        let view = try store.ensureDerivedView(sessionId: manifest.sessionId)
        #expect(view.analyzerVersion == SessionAnalyzer.version)
        #expect(view.mapFrame != nil)
        #expect(try store.readDerivedView(sessionId: manifest.sessionId) != nil)
        #expect(try store.readManifest(sessionId: manifest.sessionId).schemaVersion == SessionSchema.currentVersion)
    }

    @Test func staleAnalyzerVersionRebuilds() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DerivedStale-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch7,1",
            systemVersion: "26.0"
        )
        _ = try store.createSession(manifest: manifest)
        try store.appendDetection(
            DetectionEvent(
                code: DetectionCodes.inactive,
                reason: "session_start",
                detectorId: "session_start"
            ),
            sessionId: manifest.sessionId
        )

        let stats = SessionStatsBuilder.build(
            manifest: manifest,
            detections: try store.readDetections(sessionId: manifest.sessionId),
            locations: [],
            health: [],
            water: []
        )
        try store.writeDerivedView(
            DerivedSessionView(
                analyzerVersion: SessionAnalyzer.version - 1,
                stats: stats,
                mapFrame: nil,
                cityName: "Utrecht"
            ),
            sessionId: manifest.sessionId
        )

        let ensured = try store.ensureDerivedView(sessionId: manifest.sessionId)
        #expect(ensured.analyzerVersion == SessionAnalyzer.version)
        #expect(ensured.cityName == "Utrecht")
    }

    @Test func loadSummaryMatchesFullStatsWithoutRequiringMotion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DerivedSummary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch7,1",
            systemVersion: "26.0",
            startedAt: start,
            endedAt: start.addingTimeInterval(120)
        )
        _ = try store.createSession(manifest: manifest)
        try store.appendDetection(
            DetectionEvent(
                code: DetectionCodes.inactive,
                timestamp: start,
                reason: "session_start",
                detectorId: "session_start"
            ),
            sessionId: manifest.sessionId
        )
        try store.appendDetection(
            DetectionEvent(
                code: DetectionCodes.riding,
                timestamp: start.addingTimeInterval(10),
                reason: "15.0",
                detectorId: "ride_enter",
                speedMps: 4.2
            ),
            sessionId: manifest.sessionId
        )
        try store.appendDetection(
            DetectionEvent(
                code: DetectionCodes.inactive,
                timestamp: start.addingTimeInterval(70),
                reason: "4.0",
                detectorId: "ride_exit",
                speedMps: 1.0
            ),
            sessionId: manifest.sessionId
        )

        let summary = try SessionLoader.loadSummary(store: store, sessionId: manifest.sessionId)
        let full = try SessionLoader.load(store: store, sessionId: manifest.sessionId)
        #expect(summary.stats.rideCount == full.stats.rideCount)
        #expect(summary.stats.rideCount == 1)
        #expect(summary.derived.isCurrentAnalyzer)
    }

    @Test func derivedViewCodableRoundTrip() throws {
        let stats = SessionStats(
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            totalDuration: 1,
            totalDistanceMeters: 0,
            activeEnergyKilocalories: nil,
            rideCount: 0,
            ridingDuration: 0,
            inactiveDuration: 1,
            ridingInactiveRatio: 0,
            rides: []
        )
        let view = DerivedSessionView(
            stats: stats,
            mapFrame: MapTrackFrame(
                centerLatitude: 52,
                centerLongitude: 5,
                headingDegrees: 10,
                spanWidthMeters: 100,
                spanHeightMeters: 200
            ),
            cityName: "Almere"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(view)
        let decoded = try decoder.decode(DerivedSessionView.self, from: data)
        #expect(decoded == view)
    }

    @Test func rideSegmentStatsForwardMigratesLapCount() throws {
        let json = """
        {
          "index": 0,
          "startedAt": "2024-01-01T00:00:00Z",
          "endedAt": "2024-01-01T00:10:00Z",
          "duration": 600,
          "distanceMeters": 1200,
          "lapCount": 3,
          "highlights": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ride = try decoder.decode(RideSegmentStats.self, from: Data(json.utf8))
        #expect(ride.setCount == 3)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(ride)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["setCount"] as? Int == 3)
        #expect(object?["lapCount"] == nil)
    }

    @Test func ensureRebuildsLegacyLapCountSidecar() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DerivedLapMigrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let start = Date(timeIntervalSince1970: 1_700_000_200)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch7,1",
            systemVersion: "26.0",
            startedAt: start,
            endedAt: start.addingTimeInterval(120)
        )
        _ = try store.createSession(manifest: manifest)
        try store.appendDetection(
            DetectionEvent(
                code: DetectionCodes.inactive,
                timestamp: start,
                reason: "session_start",
                detectorId: "session_start"
            ),
            sessionId: manifest.sessionId
        )

        // Analyzer v1 sidecar still keyed `lapCount` (pre-slang rename).
        let legacyJSON = """
        {
          "analyzerVersion": 1,
          "stats": {
            "startedAt": "2023-11-14T22:16:40Z",
            "endedAt": "2023-11-14T22:18:40Z",
            "totalDuration": 120,
            "totalDistanceMeters": 0,
            "rideCount": 1,
            "ridingDuration": 60,
            "inactiveDuration": 60,
            "ridingInactiveRatio": 0.5,
            "waterTemperatureAvailable": false,
            "rides": [
              {
                "index": 0,
                "startedAt": "2023-11-14T22:16:50Z",
                "endedAt": "2023-11-14T22:17:50Z",
                "duration": 60,
                "distanceMeters": 400,
                "lapCount": 2,
                "highlights": []
              }
            ]
          },
          "cityName": "Almere"
        }
        """
        let derivedDir = store.sessionDirectory(for: manifest.sessionId)
            .appendingPathComponent("derived", isDirectory: true)
        try FileManager.default.createDirectory(at: derivedDir, withIntermediateDirectories: true)
        try Data(legacyJSON.utf8).write(to: store.derivedViewURL(sessionId: manifest.sessionId))

        let read = try store.readDerivedView(sessionId: manifest.sessionId)
        #expect(read?.stats.rides.first?.setCount == 2)
        #expect(read?.cityName == "Almere")
        #expect(read?.isCurrentAnalyzer == false)

        let ensured = try store.ensureDerivedView(sessionId: manifest.sessionId)
        #expect(ensured.analyzerVersion == SessionAnalyzer.version)
        #expect(ensured.cityName == "Almere")
        let rewritten = try store.readDerivedView(sessionId: manifest.sessionId)
        let data = try Data(contentsOf: store.derivedViewURL(sessionId: manifest.sessionId))
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("setCount"))
        #expect(!text.contains("lapCount"))
        #expect(rewritten?.isCurrentAnalyzer == true)
    }

    @Test func unreadableDerivedViewTreatedAsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DerivedCorrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch7,1",
            systemVersion: "26.0"
        )
        _ = try store.createSession(manifest: manifest)
        try store.appendDetection(
            DetectionEvent(
                code: DetectionCodes.inactive,
                reason: "session_start",
                detectorId: "session_start"
            ),
            sessionId: manifest.sessionId
        )
        let derivedDir = store.sessionDirectory(for: manifest.sessionId)
            .appendingPathComponent("derived", isDirectory: true)
        try FileManager.default.createDirectory(at: derivedDir, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: store.derivedViewURL(sessionId: manifest.sessionId))

        #expect(try store.readDerivedView(sessionId: manifest.sessionId) == nil)
        let ensured = try store.ensureDerivedView(sessionId: manifest.sessionId)
        #expect(ensured.analyzerVersion == SessionAnalyzer.version)
    }
}
