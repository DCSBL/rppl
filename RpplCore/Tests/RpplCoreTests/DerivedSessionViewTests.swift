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

    /// Answers "will existing sessions be retrofitted?": a session recorded and analyzed before
    /// `FallDetector` shipped has a sidecar stamped with the old `analyzerVersion` and no
    /// `fallDetected` data (the pre-v7 shape). Bumping `SessionAnalyzer.version` in that commit is
    /// what makes `ensureDerivedView` treat it as stale and rebuild from the still-on-disk raw
    /// detections/locations — the same lazy path `staleAnalyzerVersionRebuilds` exercises, just
    /// with a real fall in the raw data to prove the rebuilt stats pick it up.
    @Test func preFallDetectorSidecarIsRetrofittedOnNextEnsure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DerivedRetrofit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let start = Date(timeIntervalSince1970: 1_700_000_300)
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
            DetectionEvent(code: DetectionCodes.inactive, timestamp: start, reason: "session_start", detectorId: "session_start"),
            sessionId: manifest.sessionId
        )
        try store.appendDetection(
            DetectionEvent(
                code: DetectionCodes.riding,
                timestamp: start.addingTimeInterval(10),
                reason: "ride_enter",
                detectorId: "ride_enter"
            ),
            sessionId: manifest.sessionId
        )
        try store.appendDetection(
            DetectionEvent(
                code: DetectionCodes.inactive,
                timestamp: start.addingTimeInterval(100),
                reason: "ride_exit",
                detectorId: "ride_exit"
            ),
            sessionId: manifest.sessionId
        )
        // A real fall in the raw GPS: cable speed collapsing to a near-stop within 1 s.
        try store.appendLocationSamples([
            LocationSample(
                timestamp: start.addingTimeInterval(90),
                latitude: 52.0,
                longitude: 5.0,
                horizontalAccuracy: 5,
                speed: 8.3
            ),
            LocationSample(
                timestamp: start.addingTimeInterval(91),
                latitude: 52.0001,
                longitude: 5.0,
                horizontalAccuracy: 5,
                speed: 1.4
            ),
        ], sessionId: manifest.sessionId)

        // Simulate a sidecar written by the pre-FallDetector app: correct math for its time, but
        // `fallDetected` defaults to `false` because that field did not exist yet.
        let staleStats = SessionStatsBuilder.build(
            manifest: manifest,
            detections: try store.readDetections(sessionId: manifest.sessionId),
            locations: try store.readLocationSamples(sessionId: manifest.sessionId),
            health: []
        )
        #expect(staleStats.sets.first?.fallDetected == true) // sanity: today's builder does see it
        var preShipStats = staleStats
        preShipStats.sets = staleStats.sets.map { set in
            var copy = set
            copy.fallDetected = false // what the pre-v7 builder would have written
            return copy
        }
        try store.writeDerivedView(
            DerivedSessionView(analyzerVersion: SessionAnalyzer.version - 1, stats: preShipStats),
            sessionId: manifest.sessionId
        )

        let stale = try store.readDerivedView(sessionId: manifest.sessionId)
        #expect(stale?.isCurrentAnalyzer == false)
        #expect(stale?.stats.sets.first?.fallDetected == false)

        let retrofitted = try store.ensureDerivedView(sessionId: manifest.sessionId)
        #expect(retrofitted.isCurrentAnalyzer)
        #expect(retrofitted.stats.sets.first?.fallDetected == true)
        #expect(retrofitted.stats.fallCount == 1)
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
        #expect(summary.stats.setCount == full.stats.setCount)
        #expect(summary.stats.setCount == 1)
        #expect(summary.derived.isCurrentAnalyzer)
    }

    @Test func derivedViewCodableRoundTrip() throws {
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

    @Test func setSegmentStatsForwardMigratesSetCountToLapCount() throws {
        let json = """
        {
          "index": 0,
          "startedAt": "2024-01-01T00:00:00Z",
          "endedAt": "2024-01-01T00:10:00Z",
          "duration": 600,
          "distanceMeters": 1200,
          "setCount": 3,
          "highlights": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let set = try decoder.decode(SetSegmentStats.self, from: Data(json.utf8))
        #expect(set.lapCount == 3)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(set)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["lapCount"] as? Int == 3)
        #expect(object?["setCount"] == nil)
    }

    @Test func setSegmentStatsDefaultsFallDetectedFalseWhenMissing() throws {
        // Pre-FallDetector derived JSON never wrote this key — must decode as false, not crash.
        let json = """
        {
          "index": 0,
          "startedAt": "2024-01-01T00:00:00Z",
          "endedAt": "2024-01-01T00:10:00Z",
          "duration": 600,
          "distanceMeters": 1200,
          "lapCount": 0,
          "highlights": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let set = try decoder.decode(SetSegmentStats.self, from: Data(json.utf8))
        #expect(!set.fallDetected)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(set)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["fallDetected"] as? Bool == false)
    }

    @Test func setSegmentStatsRoundTripsFallDetectedTrue() throws {
        let set = SetSegmentStats(
            index: 1,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60),
            duration: 60,
            distanceMeters: 300,
            fallDetected: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(set)
        let decoded = try decoder.decode(SetSegmentStats.self, from: data)
        #expect(decoded == set)
        #expect(decoded.fallDetected)
    }

    @Test func sessionStatsForwardMigratesRideCountAndRides() throws {
        let json = """
        {
          "startedAt": "2024-01-01T00:00:00Z",
          "endedAt": "2024-01-01T00:30:00Z",
          "totalDuration": 1800,
          "totalDistanceMeters": 500,
          "rideCount": 2,
          "ridingDuration": 900,
          "inactiveDuration": 900,
          "ridingInactiveRatio": 0.5,
          "waterTemperatureAvailable": false,
          "rides": [
            {
              "index": 1,
              "startedAt": "2024-01-01T00:05:00Z",
              "endedAt": "2024-01-01T00:10:00Z",
              "duration": 300,
              "distanceMeters": 250,
              "lapCount": 1,
              "highlights": []
            }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stats = try decoder.decode(SessionStats.self, from: Data(json.utf8))
        #expect(stats.setCount == 2)
        #expect(stats.sets.count == 1)
        #expect(stats.sets[0].lapCount == 1)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(stats)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["setCount"] as? Int == 2)
        #expect(object?["rideCount"] == nil)
        #expect(object?["rides"] == nil)
        #expect((object?["sets"] as? [[String: Any]])?.first?["lapCount"] as? Int == 1)
    }

    @Test func ensureRebuildsLegacySetCountSidecar() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DerivedSetMigrate-\(UUID().uuidString)", isDirectory: true)
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

        // Intermediate slang sidecar keyed `setCount` (mis-rename of circuit crossings).
        let legacyJSON = """
        {
          "analyzerVersion": 2,
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
                "setCount": 2,
                "highlights": []
              }
            ]
          },
          "cityName": "Almere"
        }
        """
        let derivedDir = try store.sessionDirectory(for: manifest.sessionId)
            .appendingPathComponent("derived", isDirectory: true)
        try FileManager.default.createDirectory(at: derivedDir, withIntermediateDirectories: true)
        try Data(legacyJSON.utf8).write(to: try store.derivedViewURL(sessionId: manifest.sessionId))

        let read = try store.readDerivedView(sessionId: manifest.sessionId)
        #expect(read?.stats.sets.first?.lapCount == 2)
        #expect(read?.cityName == "Almere")
        #expect(read?.isCurrentAnalyzer == false)

        let ensured = try store.ensureDerivedView(sessionId: manifest.sessionId)
        #expect(ensured.analyzerVersion == SessionAnalyzer.version)
        #expect(ensured.cityName == "Almere")
        let rewritten = try store.readDerivedView(sessionId: manifest.sessionId)
        let data = try Data(contentsOf: try store.derivedViewURL(sessionId: manifest.sessionId))
        let text = String(data: data, encoding: .utf8) ?? ""
        // Rebuild from raw (inactive-only) may drop sets; never re-emit segment mis-key `setCount` for laps.
        #expect(!text.contains("\"setCount\": 2"))
        #expect(!text.contains("rideCount"))
        #expect(!text.contains("\"rides\""))
        if let set = rewritten?.stats.sets.first {
            #expect(text.contains("lapCount"))
            #expect(set.lapCount >= 0)
        }
        if let rewritten {
            #expect(rewritten.stats.setCount >= 0)
        }
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
        let derivedDir = try store.sessionDirectory(for: manifest.sessionId)
            .appendingPathComponent("derived", isDirectory: true)
        try FileManager.default.createDirectory(at: derivedDir, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: try store.derivedViewURL(sessionId: manifest.sessionId))

        #expect(try store.readDerivedView(sessionId: manifest.sessionId) == nil)
        let ensured = try store.ensureDerivedView(sessionId: manifest.sessionId)
        #expect(ensured.analyzerVersion == SessionAnalyzer.version)
    }
}
