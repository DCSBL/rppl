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

    /// A real fall can knock GPS out entirely — no two fixes ever show the cliff, only the gap
    /// does. Mirrors the real "failed start" set in `Fixtures/FallDetection`: cable speed, then a
    /// 4 s silence, then a near-stop.
    @Test func flagsCableSpeedFollowedByGpsBlackoutThenNearStop() {
        let samples = [
            location(at: 0, speedKmh: 28),
            location(at: 1, speedKmh: 29),
            location(at: 2, speedKmh: 20),
            // GPS silent for 4 s (no samples at offsets 3-5), resumes near-stopped.
            location(at: 6, speedKmh: 1),
        ]
        #expect(FallDetector.detectsFall(in: samples))
    }

    @Test func doesNotFlagAGapThatResumesAtCableSpeed() {
        // A brief GPS flake mid-ride that resumes fast is not a stop.
        let samples = [
            location(at: 0, speedKmh: 28),
            location(at: 1, speedKmh: 29),
            location(at: 5, speedKmh: 27),
        ]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    @Test func doesNotFlagAShortGapEvenIfSlowAfter() {
        // 2.9 s: past the cliff window (2.5 s) but under the blackout bar (3.0 s) — neither
        // rule should fire.
        let samples = [
            location(at: 0, speedKmh: 28),
            location(at: 2.9, speedKmh: 2),
        ]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    // MARK: - Boundaries (default thresholds: minBase=15, minDrop=15, maxWindow=2.5,
    // gpsBlackoutGap=3.0, gpsBlackoutResumeSpeedKmh=8)

    @Test func defaultThresholdsMatchCalibratedValues() {
        let thresholds = FallDetectionThresholds.default
        #expect(thresholds.minBaseSpeedKmh == 15)
        #expect(thresholds.minDropKmh == 15)
        #expect(thresholds.maxWindow == 2.5)
        #expect(thresholds.gpsBlackoutGap == 3.0)
        #expect(thresholds.gpsBlackoutResumeSpeedKmh == 8)
    }

    @Test func dropExactlyAtThresholdFlags() {
        let samples = [location(at: 0, speedKmh: 30), location(at: 1, speedKmh: 15)]
        #expect(FallDetector.detectsFall(in: samples))
    }

    @Test func dropJustBelowThresholdDoesNotFlag() {
        let samples = [location(at: 0, speedKmh: 30), location(at: 1, speedKmh: 15.1)]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    @Test func baseExactlyAtMinSpeedFlags() {
        let samples = [location(at: 0, speedKmh: 15), location(at: 1, speedKmh: 0)]
        #expect(FallDetector.detectsFall(in: samples))
    }

    @Test func baseJustBelowMinSpeedNeverFlagsRegardlessOfDropSize() {
        let samples = [location(at: 0, speedKmh: 14.9), location(at: 1, speedKmh: 0)]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    @Test func windowExactlyAtMaxWindowFlags() {
        let samples = [location(at: 0, speedKmh: 30), location(at: 2.5, speedKmh: 10)]
        #expect(FallDetector.detectsFall(in: samples))
    }

    @Test func blackoutGapExactlyAtThresholdFlags() {
        let samples = [location(at: 0, speedKmh: 30), location(at: 3.0, speedKmh: 5)]
        #expect(FallDetector.detectsFall(in: samples))
    }

    @Test func blackoutGapJustBelowThresholdDoesNotFlag() {
        let samples = [location(at: 0, speedKmh: 30), location(at: 2.9, speedKmh: 5)]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    @Test func resumeSpeedExactlyAtBlackoutThresholdFlags() {
        let samples = [location(at: 0, speedKmh: 30), location(at: 4, speedKmh: 8)]
        #expect(FallDetector.detectsFall(in: samples))
    }

    @Test func resumeSpeedJustAboveBlackoutThresholdDoesNotFlag() {
        let samples = [location(at: 0, speedKmh: 30), location(at: 4, speedKmh: 8.1)]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    // MARK: - Custom thresholds

    @Test func customThresholdsCanTightenCliffRule() {
        // A cliff that qualifies under defaults should not qualify once minDropKmh is raised
        // past it.
        let samples = [location(at: 0, speedKmh: 30), location(at: 1, speedKmh: 10)]
        #expect(FallDetector.detectsFall(in: samples))
        let strict = FallDetectionThresholds(minDropKmh: 25)
        #expect(!FallDetector.detectsFall(in: samples, thresholds: strict))
    }

    @Test func customThresholdsCanLoosenBlackoutRule() {
        // 2.7 s: past the default cliff window (2.5 s) and under the default blackout bar
        // (3.0 s), so neither rule fires by default. Lowering gpsBlackoutGap alone (leaving
        // maxWindow untouched) should flag it.
        let samples = [location(at: 0, speedKmh: 30), location(at: 2.7, speedKmh: 5)]
        #expect(!FallDetector.detectsFall(in: samples))
        let sensitive = FallDetectionThresholds(gpsBlackoutGap: 2.0)
        #expect(FallDetector.detectsFall(in: samples, thresholds: sensitive))
    }

    // MARK: - GPS noise interaction (same filter as LocationSpeedStats)

    @Test func ignoresImplausibleSpeedSpike() {
        // A single 150 km/h reading (> maxPlausibleSpeedKmh) is filtered out entirely, so it
        // cannot manufacture a cliff against the real cable-speed readings around it.
        let samples = [
            location(at: 0, speedKmh: 28),
            location(at: 1, speedKmh: 29),
            location(at: 2, speedKmh: 150),
            location(at: 3, speedKmh: 27),
        ]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    @Test func ignoresSpeedJumpGlitch() {
        // A single uncorroborated jump (>= maxSpeedJumpKmh from the last usable sample) is
        // rejected by GpsSignalFilter. Without that filter, the glitch itself (60) would become
        // a "base" and the next real reading (28) would read as a 32 km/h cliff.
        let samples = [
            location(at: 0, speedKmh: 28),
            location(at: 1, speedKmh: 29),
            location(at: 2, speedKmh: 60),
            location(at: 3, speedKmh: 28),
        ]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    // MARK: - Input shape

    @Test func unsortedInputIsSortedBeforeAnalysis() {
        let samples = [
            location(at: 1, speedKmh: 30),
            location(at: 0, speedKmh: 29),
            location(at: 2, speedKmh: 5),
        ]
        #expect(FallDetector.detectsFall(in: samples.shuffled()))
    }

    @Test func nilSpeedSamplesAreIgnoredNotTreatedAsAStop() {
        let samples = [
            location(at: 0, speedKmh: 28),
            location(at: 1, speedKmh: nil),
            location(at: 2, speedKmh: 29),
        ]
        #expect(!FallDetector.detectsFall(in: samples))
    }

    /// A dip that doesn't qualify on its own, a recovery back to cable speed, then a real fall —
    /// the scan must not give up after the first non-qualifying base and must still find the
    /// later cliff.
    @Test func detectsALaterCliffAfterANonQualifyingDip() {
        let samples = [
            location(at: 0, speedKmh: 28),
            location(at: 1, speedKmh: 20), // dip of 8 — under threshold, not a cliff
            location(at: 2, speedKmh: 27), // recovers to cable speed
            location(at: 3, speedKmh: 26),
            location(at: 4, speedKmh: 4), // the real fall
        ]
        #expect(FallDetector.detectsFall(in: samples))
    }
}
