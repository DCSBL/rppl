import Foundation
import Testing
@testable import RpplCore

@Suite("CableSpeedEstimator")
struct CableSpeedEstimatorTests {
    @Test func picksMostCommonSpeedIgnoringStartsAndPeaks() {
        var speeds = [Double](repeating: 2, count: 10) // dock / stopped
        speeds += [12, 18, 24, 38, 40] // acceleration + sprints
        speeds += (0..<60).map { 28.0 + Double($0 % 3) * 0.4 } // cruise ~28.4
        let estimate = CableSpeedEstimator.estimates(speedsKmh: speeds).first
        #expect(estimate != nil)
        #expect(abs((estimate?.speedKmh ?? 0) - 28.5) < 1.0)
    }

    @Test func tooFewSamplesGivesNoEstimate() {
        #expect(CableSpeedEstimator.estimates(speedsKmh: [25, 26, 27]).isEmpty)
    }

    @Test func separatesTwoCableSpeeds() {
        let speeds = [Double](repeating: 24.5, count: 40) + [Double](repeating: 32.5, count: 25)
        let estimates = CableSpeedEstimator.estimates(speedsKmh: speeds)
        #expect(estimates.count == 2)
        #expect(abs(estimates[0].speedKmh - 24.5) < 1)
        #expect(abs(estimates[1].speedKmh - 32.5) < 1)
    }

    @Test func roundsToNearestHalf() {
        #expect(CableSpeedEstimator.roundedToHalfKmh(28.24) == 28.0)
        #expect(CableSpeedEstimator.roundedToHalfKmh(28.26) == 28.5)
        #expect(CableSpeedEstimator.roundedToHalfKmh(28.76) == 29.0)
    }

    // MARK: - Per-set fallback

    private func locations(
        speedKmh: Double,
        duration: TimeInterval,
        start: Date = Date(timeIntervalSince1970: 0)
    ) -> [LocationSample] {
        let speedMps = SpeedUnits.metersPerSecond(fromKilometersPerHour: speedKmh)
        return stride(from: 0, through: duration, by: 1).map { offset in
            LocationSample(
                timestamp: start.addingTimeInterval(offset),
                latitude: 52.0 + offset * 0.00001,
                longitude: 4.0,
                horizontalAccuracy: 5,
                speed: speedMps
            )
        }
    }

    @Test func shortSetFallsBackToSessionValueEvenWhenSpeedDiffers() {
        let start = Date(timeIntervalSince1970: 0)
        let shortSet = locations(speedKmh: 40, duration: 30, start: start)
        let value = CableSpeedEstimator.cableSpeedKmh(
            setWindow: (start: start, end: start.addingTimeInterval(30)),
            sessionSpeedKmh: 24.5,
            locations: shortSet
        )
        #expect(value == 24.5)
    }

    @Test func longSetOverridesSessionValueWhenClearlyDifferent() {
        let start = Date(timeIntervalSince1970: 0)
        // A constant 32 km/h falls in the [32, 33) bin, whose estimate is reported as its
        // midpoint (32.5) — see CableSpeedEstimator.estimates' bin-center weighting.
        let longSet = locations(speedKmh: 32, duration: 90, start: start)
        let value = CableSpeedEstimator.cableSpeedKmh(
            setWindow: (start: start, end: start.addingTimeInterval(90)),
            sessionSpeedKmh: 24.5,
            locations: longSet
        )
        #expect(value == 32.5)
    }

    @Test func longSetKeepsSessionValueWhenCloseEnough() {
        let start = Date(timeIntervalSince1970: 0)
        let longSet = locations(speedKmh: 25.5, duration: 90, start: start)
        let value = CableSpeedEstimator.cableSpeedKmh(
            setWindow: (start: start, end: start.addingTimeInterval(90)),
            sessionSpeedKmh: 24.5,
            locations: longSet
        )
        #expect(value == 24.5)
    }

    @Test func nilSessionSpeedGivesNoEstimate() {
        let start = Date(timeIntervalSince1970: 0)
        let longSet = locations(speedKmh: 25.5, duration: 90, start: start)
        let value = CableSpeedEstimator.cableSpeedKmh(
            setWindow: (start: start, end: start.addingTimeInterval(90)),
            sessionSpeedKmh: nil,
            locations: longSet
        )
        #expect(value == nil)
    }
}
