import Foundation
import Testing
@testable import RpplCore

@Suite("GeoRecenter")
struct GeoRecenterTests {
    typealias Coordinate = (latitude: Double, longitude: Double)

    /// Park-sized areas on both hemispheres, across the antimeridian and next to a pole.
    static let centers: [Coordinate] = [
        (52.3702, 4.8952),
        (-27.9, 153.4),
        (-17.0, -179.99),
        (78.2, 15.6),
        (89.99, 10.0),
        (0.0, 0.0),
    ]

    /// 5 × 5 points about 2 km across, longitude wrapped at the antimeridian.
    private static func grid(around center: Coordinate) -> [Coordinate] {
        var points: [Coordinate] = []
        for row in -2...2 {
            for column in -2...2 {
                var longitude = center.longitude + Double(column) * 0.01
                if longitude > 180 { longitude -= 360 }
                if longitude < -180 { longitude += 360 }
                points.append((latitude: center.latitude + Double(row) * 0.005, longitude: longitude))
            }
        }
        return points
    }

    private static func maxDistanceChange(_ before: [Coordinate], _ after: [Coordinate]) -> Double {
        var worst = 0.0
        for first in before.indices {
            for second in before.indices where second > first {
                let original = GeoDistance.meters(
                    fromLat: before[first].latitude,
                    fromLon: before[first].longitude,
                    toLat: before[second].latitude,
                    toLon: before[second].longitude
                )
                let moved = GeoDistance.meters(
                    fromLat: after[first].latitude,
                    fromLon: after[first].longitude,
                    toLat: after[second].latitude,
                    toLon: after[second].longitude
                )
                worst = max(worst, abs(original - moved))
            }
        }
        return worst
    }

    @Test func anchorLandsOnOrigin() {
        let recenter = GeoRecenter(anchorLatitude: 52.3702, anchorLongitude: 4.8952)
        let moved = recenter.apply(latitude: 52.3702, longitude: 4.8952)
        #expect(abs(moved.latitude) < 1e-12)
        #expect(abs(moved.longitude) < 1e-12)
    }

    @Test func poleAnchorLandsOnOrigin() {
        let moved = GeoRecenter(anchorLatitude: 90, anchorLongitude: 0).apply(latitude: 90, longitude: 0)
        #expect(abs(moved.latitude) < 1e-9)
        #expect(abs(moved.longitude) < 1e-9)
    }

    @Test func emptyInputHasNoRecenter() {
        #expect(GeoRecenter(centeringOn: []) == nil)
    }

    @Test(arguments: GeoRecenterTests.centers.indices)
    func centreOfTheSessionLandsOnOrigin(index: Int) throws {
        let points = Self.grid(around: Self.centers[index])
        let recenter = try #require(GeoRecenter(centeringOn: points))
        let moved = points.map { recenter.apply(latitude: $0.latitude, longitude: $0.longitude) }
        let meanLatitude = moved.map(\.latitude).reduce(0, +) / Double(moved.count)
        let meanLongitude = moved.map(\.longitude).reduce(0, +) / Double(moved.count)
        #expect(abs(meanLatitude) < 1e-6, "center \(index): mean latitude \(meanLatitude)")
        #expect(abs(meanLongitude) < 1e-6, "center \(index): mean longitude \(meanLongitude)")
    }

    /// The point of rotating instead of subtracting degrees: nothing inside the session is warped.
    @Test(arguments: GeoRecenterTests.centers.indices)
    func distancesBetweenPointsStayTheSame(index: Int) throws {
        let points = Self.grid(around: Self.centers[index])
        let recenter = try #require(GeoRecenter(centeringOn: points))
        let moved = points.map { recenter.apply(latitude: $0.latitude, longitude: $0.longitude) }
        #expect(Self.maxDistanceChange(points, moved) < 1e-6, "center \(index)")
    }

    /// Why a plain degree offset is not good enough: at 52°N it stretches the track by over a kilometre.
    @Test func subtractingDegreesWouldWarpTheTrack() {
        let points = Self.grid(around: Self.centers[0])
        let meanLatitude = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let meanLongitude = points.map(\.longitude).reduce(0, +) / Double(points.count)
        let shifted = points.map {
            (latitude: $0.latitude - meanLatitude, longitude: $0.longitude - meanLongitude)
        }
        #expect(Self.maxDistanceChange(points, shifted) > 100)
    }

    @Test func northStaysNorthAtTheAnchor() {
        let recenter = GeoRecenter(anchorLatitude: 52.3702, anchorLongitude: 4.8952)
        let north = recenter.apply(latitude: 52.3712, longitude: 4.8952)
        let east = recenter.apply(latitude: 52.3702, longitude: 4.8962)
        #expect(north.latitude > 0)
        #expect(abs(north.longitude) < 1e-12)
        #expect(east.longitude > 0)
        #expect(abs(east.latitude) < 1e-6)
    }

    @Test func resultStaysInRange() throws {
        // Two opposite points: their directions cancel out, so there is no centre to anchor on.
        let recenter = try #require(GeoRecenter(centeringOn: [(latitude: 10, longitude: 20), (latitude: -10, longitude: -160)]))
        for latitude in stride(from: -90.0, through: 90.0, by: 30) {
            for longitude in stride(from: -180.0, through: 180.0, by: 45) {
                let moved = recenter.apply(latitude: latitude, longitude: longitude)
                #expect(moved.latitude.isFinite && abs(moved.latitude) <= 90 + 1e-9)
                #expect(moved.longitude.isFinite && abs(moved.longitude) <= 180 + 1e-9)
            }
        }
    }
}
