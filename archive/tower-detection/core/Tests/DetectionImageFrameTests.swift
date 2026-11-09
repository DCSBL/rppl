import Foundation
import Testing
@testable import RpplCore

struct DetectionImageFrameTests {
    private let origin = ParkCoordinate(lat: 52.18, lon: 6.84)

    @Test func localMetresHaveTheSameScaleNorthAndEast() {
        // Web Mercator imagery has as many pixels per metre north as east, so one degree of
        // latitude must be as long as one degree of longitude divided by cos(latitude).
        let north = DetectionImage.localXY(of: ParkCoordinate(lat: origin.lat + 0.001, lon: origin.lon), origin: origin)
        let east = DetectionImage.localXY(of: ParkCoordinate(lat: origin.lat, lon: origin.lon + 0.001), origin: origin)
        #expect(abs(north.y - east.x / cos(origin.lat * .pi / 180)) < 1e-9)
        let back = DetectionImage.coordinate(fromLocal: SIMD2(120, -80), origin: origin)
        let xy = DetectionImage.localXY(of: back, origin: origin)
        #expect(abs(xy.x - 120) < 1e-6 && abs(xy.y + 80) < 1e-6)
    }
}
