import Foundation
import Testing
@testable import RpplCore

@Suite("MapTrackFit")
struct MapTrackFitTests {
    @Test func verticalLoopRotatesNearNinety() {
        // Tall N–S cable loop (~400 m × ~80 m).
        let locations = verticalLoopPoints()
        let fit = MapTrackFitter.fit(
            locations: locations,
            viewWidth: 390,
            viewHeight: 300
        )
        #expect(fit != nil)
        guard let fit else { return }
        #expect(abs(fit.headingDegrees) >= 70)
        #expect(abs(fit.headingDegrees) <= MapTrackFitter.maxHeadingDegrees)
    }

    @Test func horizontalTrackKeepsNearZeroHeading() {
        let locations: [(Double, Double)] = (0..<20).map { i in
            let t = Double(i) / 19
            return (52.0, 5.0 + t * 0.004)
        }
        let fit = MapTrackFitter.fit(
            locations: locations,
            viewWidth: 390,
            viewHeight: 300
        )
        #expect(fit != nil)
        guard let fit else { return }
        #expect(abs(fit.headingDegrees) <= 20)
    }

    @Test func headingClampStaysWithinPlusMinusNinety() {
        #expect(MapTrackFitter.clampedHeadingDegrees(0) == 0)
        #expect(MapTrackFitter.clampedHeadingDegrees(90) == 90)
        #expect(MapTrackFitter.clampedHeadingDegrees(-90) == -90)
        #expect(MapTrackFitter.clampedHeadingDegrees(135) == -45)
        #expect(MapTrackFitter.clampedHeadingDegrees(-135) == 45)
        #expect(MapTrackFitter.clampedHeadingDegrees(180) == 0)
    }

    @Test func fitNeedsAtLeastTwoPoints() {
        let one = MapTrackFitter.fit(
            locations: [(52.0, 5.0)],
            viewWidth: 200,
            viewHeight: 200
        )
        #expect(one == nil)
    }

    @Test func paddingIncreasesCameraDistance() {
        let locations = verticalLoopPoints()
        let tight = MapTrackFitter.fit(
            locations: locations,
            viewWidth: 390,
            viewHeight: 300,
            paddingFactor: 1.05
        )
        let loose = MapTrackFitter.fit(
            locations: locations,
            viewWidth: 390,
            viewHeight: 300,
            paddingFactor: 1.4
        )
        #expect(tight != nil && loose != nil)
        guard let tight, let loose else { return }
        #expect(loose.cameraDistanceMeters > tight.cameraDistanceMeters)
    }

    private func verticalLoopPoints() -> [(latitude: Double, longitude: Double)] {
        // Ellipse: major axis N–S, minor E–W.
        (0..<36).map { i in
            let angle = Double(i) / 36 * 2 * .pi
            let dLat = 0.0018 * sin(angle)
            let dLon = 0.00035 * cos(angle)
            return (latitude: 52.1 + dLat, longitude: 5.1 + dLon)
        }
    }
}
