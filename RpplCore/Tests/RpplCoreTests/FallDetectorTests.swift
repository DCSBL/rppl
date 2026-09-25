import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func location(
    at offset: TimeInterval,
    lat: Double = 52.0,
    lon: Double = 5.0,
    accuracy: Double = 10,
    speedKmh: Double?
) -> LocationSample {
    LocationSample(
        timestamp: t0.addingTimeInterval(offset),
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: accuracy,
        speed: speedKmh.map { SpeedUnits.metersPerSecond(fromKilometersPerHour: $0) }
    )
}

@Suite("FallDetector")
struct FallDetectorTests {
    @Test func flagsSpeedCliffFromCableSpeed() {
        let samples = [
            location(at: 0, speedKmh: 30),
            location(at: 1, speedKmh: 31),
            location(at: 2, speedKmh: 30),
            // Fall: cable speed collapses to a near-stop within 2 s.
            location(at: 3, speedKmh: 22),
            location(at: 4, speedKmh: 7),
            location(at: 5, speedKmh: 1),
        ]
        #expect(FallDetector.detectsFall(in: samples))
    }

    @Test func doesNotFlagGradualCoastToStop() {
        // Same total drop (30 -> 0) but spread over 10 s — a controlled glide, not a cliff.
        let samples = (0...10).map { i in
            location(at: Double(i), speedKmh: max(0, 30 - Double(i) * 3))
        }
        #expect(!FallDetector.detectsFall(in: samples))
    }

    @Test func ignoresDropsThatNeverReachCableSpeed() {
        // Walking pace dropping to a stop should not read as a fall.
        let samples = [
            location(at: 0, speedKmh: 8),
            location(at: 1, speedKmh: 6),
            location(at: 2, speedKmh: 0),
        ]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    @Test func ignoresLowAccuracySamples() {
        let samples = [
            location(at: 0, accuracy: 10, speedKmh: 30),
            location(at: 1, accuracy: 200, speedKmh: 30),
            // Bad-accuracy sample reads implausible speed; filter must reject it, not the drop.
            location(at: 2, accuracy: 200, speedKmh: 1),
            location(at: 3, accuracy: 10, speedKmh: 29),
        ]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    @Test func tooFewSamplesNeverFlags() {
        #expect(!FallDetector.detectsFall(in: [location(at: 0, speedKmh: 30)]))
        #expect(!FallDetector.detectsFall(in: []))
    }
}
