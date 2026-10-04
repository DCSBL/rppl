import Foundation
import Testing
@testable import RpplCore

@Suite("DerivedSessionView")
struct DerivedSessionViewTests {
    @Test func ensureCreatesSidecarWhenMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DerivedEnsure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = SessionManifest(
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
