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
}
