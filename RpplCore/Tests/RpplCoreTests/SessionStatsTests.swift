import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func manifest(endedAt: Date? = nil) -> SessionManifest {
    SessionManifest(
        sessionId: "test-session",
        testerId: "tester",
        appVersion: "1.0",
        buildNumber: "1",
        watchModel: "Watch",
        systemVersion: "11.0",
        startedAt: t0,
        endedAt: endedAt,
        transferState: .acknowledged
    )
}

private func detection(
    code: String,
    at offset: TimeInterval,
    id: String = UUID().uuidString,
    supersedesId: String? = nil
) -> DetectionEvent {
    DetectionEvent(
        id: id,
        code: code,
        timestamp: t0.addingTimeInterval(offset),
        reason: code,
        detectorId: "test",
        supersedesId: supersedesId
    )
}

private func location(
    at offset: TimeInterval,
    lat: Double,
    lon: Double,
    accuracy: Double = 10,
    speedMps: Double? = 5
) -> LocationSample {
    LocationSample(
        timestamp: t0.addingTimeInterval(offset),
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: accuracy,
        speed: speedMps
    )
}

@Suite("GeoDistance")
struct GeoDistanceTests {
    @Test func haversineShortStep() {
        // ~111 m per 0.001° latitude at equator
        let meters = GeoDistance.meters(fromLat: 52.0, fromLon: 5.0, toLat: 52.001, toLon: 5.0)
        #expect(meters > 100)
        #expect(meters < 120)
    }

    @Test func rejectsBadAccuracy() {
        let from = location(at: 0, lat: 52.0, lon: 5.0, accuracy: 10)
        let to = location(at: 1, lat: 52.001, lon: 5.0, accuracy: 40)
        #expect(!GeoDistance.acceptsStep(from: from, to: to, maxHorizontalAccuracyM: 25))
    }

    @Test func rejectsTeleport() {
        let from = location(at: 0, lat: 52.0, lon: 5.0)
        let to = location(at: 1, lat: 52.1, lon: 5.0, speedMps: 5)
        #expect(!GeoDistance.acceptsStep(from: from, to: to, maxHorizontalAccuracyM: 25))
    }
}

@Suite("DistanceFormat")
struct DistanceFormatTests {
    @Test func dutchLocaleUsesGrouping() {
        let formatted = DistanceFormat.meters(1234, locale: Locale(identifier: "nl_NL"))
        #expect(formatted.contains("m"))
        #expect(formatted.contains("1") && formatted.contains("234"))
    }
}

@Suite("SessionStatsBuilder")
struct SessionStatsBuilderTests {
    @Test func emptyDetectionsZeroStats() {
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(600)),
            detections: [detection(code: DetectionCodes.paused, at: 0, id: "start")],
            locations: [],
            health: []
        )
        #expect(stats.rideCount == 0)
        #expect(stats.totalDistanceMeters == 0)
        #expect(stats.ridingDuration == 0)
        #expect(stats.pausedDuration == 600)
    }

    @Test func singleRideDistanceAndDuration() {
        let detections = [
            detection(code: DetectionCodes.paused, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.paused, at: 100, id: "p1"),
        ]
        let locations = [
            location(at: 20, lat: 52.0, lon: 5.0),
            location(at: 21, lat: 52.0001, lon: 5.0),
            location(at: 22, lat: 52.0002, lon: 5.0),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(200)),
            detections: detections,
            locations: locations,
            health: []
        )
        #expect(stats.rideCount == 1)
        #expect(stats.rides.count == 1)
        #expect(stats.rides[0].duration == 90)
        #expect(stats.rides[0].distanceMeters > 10)
        #expect(stats.ridingDuration == 90)
        #expect(stats.pausedDuration == 110)
        #expect(abs(stats.ridingPausedRatio - 90.0 / 200.0) < 0.001)
    }

    @Test func twoRidesFromPauseBetween() {
        let detections = [
            detection(code: DetectionCodes.paused, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.paused, at: 50, id: "p1"),
            detection(code: DetectionCodes.riding, at: 100, id: "r2"),
            detection(code: DetectionCodes.paused, at: 150, id: "p2"),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(200)),
            detections: detections,
            locations: [],
            health: []
        )
        #expect(stats.rideCount == 2)
        #expect(stats.rides.count == 2)
    }

    @Test func supersededUnsureMergesIntoOneRide() {
        let unsureId = "unsure-1"
        let detections = [
            detection(code: DetectionCodes.paused, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.unsure, at: 30, id: unsureId),
            detection(
                code: DetectionCodes.riding,
                at: 45,
                id: "lookback",
                supersedesId: unsureId
            ),
            detection(code: DetectionCodes.paused, at: 100, id: "p1"),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(120)),
            detections: detections,
            locations: [],
            health: []
        )
        #expect(stats.rideCount == 1)
        #expect(stats.rides[0].duration == 90)
    }

    @Test func caloriesUsesMaxCumulative() {
        let health = [
            HealthMetricSample(timestamp: t0.addingTimeInterval(10), activeEnergyKilocalories: 50),
            HealthMetricSample(timestamp: t0.addingTimeInterval(100), activeEnergyKilocalories: 180),
            HealthMetricSample(timestamp: t0.addingTimeInterval(200), activeEnergyKilocalories: 120),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(300)),
            detections: [detection(code: DetectionCodes.paused, at: 0, id: "s")],
            locations: [],
            health: health
        )
        #expect(stats.activeEnergyKilocalories == 180)
        #expect(stats.totalEnergyKilocalories == 180)
    }

    @Test func totalCaloriesSumsActiveAndBasal() {
        let health = [
            HealthMetricSample(
                timestamp: t0.addingTimeInterval(10),
                activeEnergyKilocalories: 100,
                basalEnergyKilocalories: 40
            ),
            HealthMetricSample(
                timestamp: t0.addingTimeInterval(100),
                activeEnergyKilocalories: 200,
                basalEnergyKilocalories: 80
            ),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(300)),
            detections: [detection(code: DetectionCodes.paused, at: 0, id: "s")],
            locations: [],
            health: health
        )
        #expect(stats.activeEnergyKilocalories == 200)
        #expect(stats.totalEnergyKilocalories == 280)
    }

    @Test func openRideClosedAtSessionEnd() {
        let detections = [
            detection(code: DetectionCodes.paused, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(100)),
            detections: detections,
            locations: [],
            health: []
        )
        #expect(stats.rideCount == 1)
        #expect(stats.rides[0].endedAt == t0.addingTimeInterval(100))
    }
}

@Suite("LiveRideTracker")
struct LiveRideTrackerTests {
    @Test func rideCountOnEnter() {
        var tracker = LiveRideTracker()
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 10)]
        )
        #expect(tracker.rideCount == 1)
        #expect(tracker.isRideOngoing)
    }

    @Test func frozenLastRideMetersWhenPaused() {
        var tracker = LiveRideTracker()
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 0)]
        )
        tracker.addLocation(location(at: 1, lat: 52.0, lon: 5.0))
        tracker.addLocation(location(at: 2, lat: 52.0001, lon: 5.0))
        let meters = tracker.currentRideMeters
        #expect(meters > 0)

        tracker.update(
            currentCode: DetectionCodes.paused,
            lastConfident: DetectionCodes.paused,
            events: [detection(code: DetectionCodes.paused, at: 50)]
        )
        #expect(!tracker.isRideOngoing)
        #expect(tracker.lastRideMeters == meters)
        #expect(tracker.currentRideMeters == 0)
        #expect(tracker.currentSpeedKmh == nil)
    }

    @Test func zeroMetersBeforeFirstRide() {
        let tracker = LiveRideTracker()
        #expect(tracker.lastRideMeters == 0)
        #expect(tracker.rideCount == 0)
    }
}
