import Foundation
import Testing
@testable import RpplCore

@Suite("SensorSamplingMode")
struct SensorSamplingModeTests {
    @Test func denseWhileRidingOrUnsure() {
        #expect(SensorSamplingMode.isDense(currentCode: DetectionCodes.riding))
        #expect(SensorSamplingMode.isDense(currentCode: DetectionCodes.unsure))
        #expect(!SensorSamplingMode.isDense(currentCode: DetectionCodes.inactive))
    }
}

@Suite("LiveSetTrackerBackfill")
struct LiveSetTrackerBackfillTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func location(at offset: TimeInterval, lat: Double, lon: Double) -> LocationSample {
        LocationSample(
            timestamp: t0.addingTimeInterval(offset),
            latitude: lat,
            longitude: lon,
            horizontalAccuracy: 10,
            speed: SpeedUnits.metersPerSecond(fromKilometersPerHour: 22)
        )
    }

    private func detection(code: String, at offset: TimeInterval) -> DetectionEvent {
        DetectionEvent(
            code: code,
            timestamp: t0.addingTimeInterval(offset),
            reason: "test",
            detectorId: "test"
        )
    }

    @Test func replayLocationsAfterBackdatedEnter() {
        var tracker = LiveSetTracker()
        let holdStart = t0
        let enterEvent = detection(code: DetectionCodes.riding, at: 0)
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [enterEvent]
        )
        let buffered = [
            location(at: 0, lat: 52.0, lon: 5.0),
            location(at: 1, lat: 52.0001, lon: 5.0001),
            location(at: 2, lat: 52.0002, lon: 5.0002),
        ]
        tracker.replayLocationsForSetEnter(buffered, from: holdStart)
        #expect(tracker.currentSetMeters > 0)
    }
}
