import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func event(_ code: String, at offset: TimeInterval) -> DetectionEvent {
    DetectionEvent(code: code, timestamp: t0.addingTimeInterval(offset), reason: code, detectorId: "test")
}

private func fix(at offset: TimeInterval, speedKmh: Double, accuracy: Double = 5) -> LocationSample {
    LocationSample(
        timestamp: t0.addingTimeInterval(offset),
        latitude: 52 + offset * 0.00001,
        longitude: 5,
        horizontalAccuracy: accuracy,
        speed: SpeedUnits.metersPerSecond(fromKilometersPerHour: speedKmh)
    )
}

/// Inactive Watch UI shows the cable speed, not the rider's live GPS speed at the dock.
@Suite("LiveCableSpeed")
struct LiveCableSpeedTests {
    @Test func cableSpeedAppearsAfterFirstSetAndIgnoresDockSpeed() {
        var tracker = LiveSetTracker()
        tracker.update(currentCode: DetectionCodes.riding, lastConfident: DetectionCodes.riding, events: [
            event(DetectionCodes.riding, at: 0),
        ])
        for second in 1...60 {
            // Mostly 31 km/h with a few sprints and slow corners.
            let speed: Double = second % 10 == 0 ? 38 : (second % 7 == 0 ? 25 : 31)
            tracker.addLocation(fix(at: TimeInterval(second), speedKmh: speed))
        }
        #expect(tracker.cableSpeedKmh == nil)

        tracker.update(currentCode: DetectionCodes.inactive, lastConfident: DetectionCodes.inactive, events: [
            event(DetectionCodes.inactive, at: 61),
        ])
        #expect(tracker.cableSpeedKmh == 31)

        // Walking back on the dock does not move it.
        tracker.addLocation(fix(at: 70, speedKmh: 5))
        tracker.addLocation(fix(at: 71, speedKmh: 45, accuracy: 200))
        #expect(tracker.cableSpeedKmh == 31)
    }

    @Test func tooFewSamplesGiveNoEstimate() {
        var tracker = LiveSetTracker()
        tracker.update(currentCode: DetectionCodes.riding, lastConfident: DetectionCodes.riding, events: [
            event(DetectionCodes.riding, at: 0),
        ])
        for second in 1...5 {
            tracker.addLocation(fix(at: TimeInterval(second), speedKmh: 31))
        }
        tracker.update(currentCode: DetectionCodes.inactive, lastConfident: DetectionCodes.inactive, events: [
            event(DetectionCodes.inactive, at: 6),
        ])
        #expect(tracker.cableSpeedKmh == nil)
    }

    @Test func resetClearsCableSpeed() {
        var tracker = LiveSetTracker()
        tracker.update(currentCode: DetectionCodes.riding, lastConfident: DetectionCodes.riding, events: [
            event(DetectionCodes.riding, at: 0),
        ])
        for second in 1...30 {
            tracker.addLocation(fix(at: TimeInterval(second), speedKmh: 31))
        }
        tracker.closeOpenSet(at: t0.addingTimeInterval(31))
        #expect(tracker.cableSpeedKmh == 31)
        tracker.reset()
        #expect(tracker.cableSpeedKmh == nil)
    }
}
