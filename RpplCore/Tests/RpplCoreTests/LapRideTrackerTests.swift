import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

/// ~1.11 m per 0.00001° latitude.
private func location(
    at offset: TimeInterval,
    lat: Double,
    lon: Double,
    accuracy: Double = 10,
    speedMps: Double? = nil
) -> LocationSample {
    LocationSample(
        timestamp: t0.addingTimeInterval(offset),
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: accuracy,
        speed: speedMps
    )
}

/// Walk a polyline with small steps so GeoDistance.acceptsStep stays happy.
private func pathSamples(
    startOffset: TimeInterval,
    points: [(lat: Double, lon: Double)],
    stepMeters: Double = 12,
    stepSeconds: TimeInterval = 1
) -> [LocationSample] {
    var samples: [LocationSample] = []
    var t = startOffset
    guard let first = points.first else { return [] }
    samples.append(location(at: t, lat: first.lat, lon: first.lon))
    for i in 1..<points.count {
        let from = points[i - 1]
        let to = points[i]
        let dist = GeoDistance.meters(
            fromLat: from.lat, fromLon: from.lon,
            toLat: to.lat, toLon: to.lon
        )
        let steps = max(1, Int(ceil(dist / stepMeters)))
        for s in 1...steps {
            let frac = Double(s) / Double(steps)
            let lat = from.lat + (to.lat - from.lat) * frac
            let lon = from.lon + (to.lon - from.lon) * frac
            t += stepSeconds
            samples.append(location(at: t, lat: lat, lon: lon))
        }
    }
    return samples
}

@Suite("LapRideTracker")
struct LapRideTrackerTests {
    private let tight = LapThresholds(
        startSafeRadiusM: 30,
        exitRadiusM: 40,
        minPathBeforeCrossingM: 80,
        maxHorizontalAccuracyM: 25
    )

    @Test func leaveWithoutReturnIsZero() {
        var tracker = LapRideTracker(thresholds: tight)
        tracker.notePaused()
        tracker.beginRide()
        let samples = pathSamples(
            startOffset: 0,
            points: [
                (52.0, 5.0),
                (52.001, 5.0),
                (52.002, 5.0),
            ]
        )
        for sample in samples {
            tracker.addLocation(sample)
        }
        tracker.endRide()
        #expect(tracker.lapCount == 0)
    }

    @Test func oneFullCrossingCountsOne() {
        var tracker = LapRideTracker(thresholds: tight)
        tracker.notePaused()
        tracker.beginRide()
        // Rectangle ~111m x ~111m → path ~444m > 80m min; return to start.
        let samples = pathSamples(
            startOffset: 0,
            points: [
                (52.0, 5.0),
                (52.001, 5.0),
                (52.001, 5.001),
                (52.0, 5.001),
                (52.0, 5.0),
            ]
        )
        for sample in samples {
            tracker.addLocation(sample)
        }
        #expect(tracker.lapCount == 1)
        tracker.endRide()
        #expect(tracker.lapCount == 1)
    }

    @Test func twoCrossingsCountTwo() {
        var tracker = LapRideTracker(thresholds: tight)
        tracker.notePaused()
        tracker.beginRide()
        let loop: [(Double, Double)] = [
            (52.0, 5.0),
            (52.001, 5.0),
            (52.001, 5.001),
            (52.0, 5.001),
            (52.0, 5.0),
        ]
        var samples = pathSamples(startOffset: 0, points: loop)
        let second = pathSamples(startOffset: 200, points: loop)
        samples.append(contentsOf: second)
        for sample in samples {
            tracker.addLocation(sample)
        }
        #expect(tracker.lapCount == 2)
    }

    @Test func nearStartWobbleDoesNotCount() {
        var tracker = LapRideTracker(thresholds: tight)
        tracker.notePaused()
        tracker.beginRide()
        // Leave slightly then return without enough path.
        let samples = pathSamples(
            startOffset: 0,
            points: [
                (52.0, 5.0),
                (52.0005, 5.0), // ~55m — past exit 40m
                (52.0, 5.0),
            ]
        )
        for sample in samples {
            tracker.addLocation(sample)
        }
        #expect(tracker.lapCount == 0)
    }

    @Test func midRideStartIgnoredUntilPause() {
        var tracker = LapRideTracker(thresholds: tight)
        // No notePaused — first ride ignored.
        tracker.beginRide()
        let loop = pathSamples(
            startOffset: 0,
            points: [
                (52.0, 5.0),
                (52.001, 5.0),
                (52.001, 5.001),
                (52.0, 5.001),
                (52.0, 5.0),
            ]
        )
        for sample in loop {
            tracker.addLocation(sample)
        }
        #expect(tracker.lapCount == 0)
        tracker.endRide()

        // After endRide, pause is implied — second ride scores.
        tracker.beginRide()
        for sample in pathSamples(startOffset: 300, points: [
            (52.0, 5.0),
            (52.001, 5.0),
            (52.001, 5.001),
            (52.0, 5.001),
            (52.0, 5.0),
        ]) {
            tracker.addLocation(sample)
        }
        #expect(tracker.lapCount == 1)
    }

    @Test func badAccuracyDoesNotTeleportLap() {
        var tracker = LapRideTracker(thresholds: tight)
        tracker.notePaused()
        tracker.beginRide()
        tracker.addLocation(location(at: 0, lat: 52.0, lon: 5.0))
        // Leave with good GPS.
        for sample in pathSamples(startOffset: 1, points: [
            (52.0, 5.0),
            (52.001, 5.0),
            (52.002, 5.0),
        ]) {
            tracker.addLocation(sample)
        }
        // Flaky fix at start — ignored by accuracy gate.
        tracker.addLocation(location(at: 50, lat: 52.0, lon: 5.0, accuracy: 80))
        #expect(tracker.lapCount == 0)
        // Teleport jump to start with good accuracy but huge step — rejected.
        tracker.addLocation(location(at: 51, lat: 52.0, lon: 5.0, accuracy: 10))
        #expect(tracker.lapCount == 0)
    }

    @Test func pauseFreezesFurtherCrossings() {
        var tracker = LapRideTracker(thresholds: tight)
        tracker.notePaused()
        tracker.beginRide()
        for sample in pathSamples(startOffset: 0, points: [
            (52.0, 5.0),
            (52.001, 5.0),
            (52.001, 5.001),
            (52.0, 5.001),
            (52.0, 5.0),
        ]) {
            tracker.addLocation(sample)
        }
        #expect(tracker.lapCount == 1)
        tracker.endRide()
        #expect(tracker.lapCount == 1)
        // GPS near start after pause must not add laps.
        for sample in pathSamples(startOffset: 100, points: [
            (52.0, 5.0),
            (52.001, 5.0),
            (52.001, 5.001),
            (52.0, 5.001),
            (52.0, 5.0),
        ]) {
            tracker.addLocation(sample)
        }
        #expect(tracker.lapCount == 1)
    }
}

@Suite("LapRideTracker session stats")
struct LapSessionStatsTests {
    @Test func builderAttachesLapCount() {
        let detections = [
            DetectionEvent(
                id: "s",
                code: DetectionCodes.paused,
                timestamp: t0,
                reason: "start",
                detectorId: "test"
            ),
            DetectionEvent(
                id: "r",
                code: DetectionCodes.riding,
                timestamp: t0.addingTimeInterval(10),
                reason: "enter",
                detectorId: "test"
            ),
            DetectionEvent(
                id: "p",
                code: DetectionCodes.paused,
                timestamp: t0.addingTimeInterval(500),
                reason: "exit",
                detectorId: "test"
            ),
        ]
        let locations = pathSamples(
            startOffset: 10,
            points: [
                (52.0, 5.0),
                (52.001, 5.0),
                (52.001, 5.001),
                (52.0, 5.001),
                (52.0, 5.0),
            ]
        )
        let stats = SessionStatsBuilder.build(
            manifest: SessionManifest(
                sessionId: "s",
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "W",
                systemVersion: "26",
                startedAt: t0,
                endedAt: t0.addingTimeInterval(600),
                transferState: .acknowledged
            ),
            detections: detections,
            locations: locations,
            health: [],
            lapThresholds: LapThresholds(
                startSafeRadiusM: 30,
                exitRadiusM: 40,
                minPathBeforeCrossingM: 80
            )
        )
        #expect(stats.rides.count == 1)
        #expect(stats.rides[0].lapCount == 1)
    }
}
