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

    @Test func fitSinglePointUsesStartFrame() {
        let fit = MapTrackFitter.fit(
            locations: [(52.0, 5.0)],
            viewWidth: 200,
            viewHeight: 200
        )
        #expect(fit != nil)
        guard let fit else { return }
        #expect(fit.centerLatitude == 52.0)
        #expect(fit.centerLongitude == 5.0)
        #expect(fit.headingDegrees == 0)
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

    @Test func frameFitsDifferentViewSizes() {
        let locations = verticalLoopPoints()
        let frame = MapTrackFitter.frame(locations: locations)
        #expect(frame != nil)
        guard let frame else { return }
        let phone = MapTrackFitter.fit(frame: frame, viewWidth: 390, viewHeight: 300)
        let tall = MapTrackFitter.fit(frame: frame, viewWidth: 200, viewHeight: 400)
        #expect(phone != nil && tall != nil)
        guard let phone, let tall else { return }
        #expect(phone.centerLatitude == frame.centerLatitude)
        #expect(tall.headingDegrees == frame.headingDegrees)
        #expect(phone.cameraDistanceMeters != tall.cameraDistanceMeters)
    }

    @Test func insetsFrameTheUncoveredPart() {
        let frame = MapTrackFrame(
            centerLatitude: 52.1, centerLongitude: 5.1, headingDegrees: 0,
            spanWidthMeters: 400, spanHeightMeters: 200
        )
        // A 300 pt sidebar over the left of a 700 pt map leaves 400 pt: as wide as a 400 pt map.
        let covered = MapTrackFitter.fit(
            frame: frame, viewWidth: 700, viewHeight: 300,
            insets: MapViewInsets(top: 0, left: 300, bottom: 0, right: 0)
        )
        let narrow = MapTrackFitter.fit(frame: frame, viewWidth: 400, viewHeight: 300)
        #expect(covered != nil && narrow != nil)
        guard let covered, let narrow else { return }
        #expect(abs(covered.cameraDistanceMeters - narrow.cameraDistanceMeters) < 0.001)
        // The camera moves west, so the track shows right of the middle, beside the sidebar.
        #expect(covered.centerLongitude < frame.centerLongitude)
        #expect(abs(covered.centerLatitude - frame.centerLatitude) < 1e-9)
    }

    @Test func insetsFollowTheHeading() {
        // Map top points east: the left of the screen is north, so a left inset moves the camera north.
        let shifted = MapTrackFitter.center(
            latitude: 52.1, longitude: 5.1, headingDegrees: 90, cameraDistanceMeters: 1_000,
            viewHeight: 600, insets: MapViewInsets(top: 0, left: 200, bottom: 0, right: 0)
        )
        #expect(shifted.latitude > 52.1)
        #expect(abs(shifted.longitude - 5.1) < 1e-9)
        // A taller top bar than bottom bar moves the camera north at heading 0.
        let below = MapTrackFitter.center(
            latitude: 52.1, longitude: 5.1, headingDegrees: 0, cameraDistanceMeters: 1_000,
            viewHeight: 600, insets: MapViewInsets(top: 100, left: 0, bottom: 20, right: 0)
        )
        #expect(below.latitude > 52.1)
    }

    @Test func noInsetsKeepTheCenter() {
        let center = MapTrackFitter.center(
            latitude: 52.1, longitude: 5.1, headingDegrees: 30, cameraDistanceMeters: 1_000,
            viewHeight: 600, insets: .zero
        )
        #expect(center.latitude == 52.1 && center.longitude == 5.1)
    }

    @Test func startFrameFromSingleLocation() {
        let frame = MapTrackFitter.frame(locations: [(latitude: 52.1, longitude: 5.1)])
        #expect(frame != nil)
        #expect(frame?.centerLatitude == 52.1)
        #expect(frame?.centerLongitude == 5.1)
        #expect(frame?.headingDegrees == 0)
        #expect(frame?.spanWidthMeters == 800)
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
