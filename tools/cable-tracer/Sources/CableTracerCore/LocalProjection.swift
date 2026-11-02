import Foundation
import RpplCore

/// Flat east/north metres around an origin; accurate to well under a metre at cable-park scale (< 3 km).
public struct LocalProjection: Sendable {
    public static let earthRadiusM = 6_371_000.0

    public let origin: ParkCoordinate
    private let cosLat: Double

    public init(origin: ParkCoordinate) {
        self.origin = origin
        self.cosLat = cos(origin.lat * .pi / 180)
    }

    /// x = east, y = north, in metres.
    public func xy(_ coordinate: ParkCoordinate) -> SIMD2<Double> {
        let dLat = (coordinate.lat - origin.lat) * .pi / 180
        let dLon = (coordinate.lon - origin.lon) * .pi / 180
        return SIMD2(dLon * cosLat * Self.earthRadiusM, dLat * Self.earthRadiusM)
    }

    public func coordinate(_ xy: SIMD2<Double>) -> ParkCoordinate {
        let lat = origin.lat + (xy.y / Self.earthRadiusM) * 180 / .pi
        let lon = origin.lon + (xy.x / (Self.earthRadiusM * cosLat)) * 180 / .pi
        return ParkCoordinate(lat: lat, lon: lon)
    }
}

extension SIMD2 where Scalar == Double {
    var length: Double { (x * x + y * y).squareRoot() }

    /// Compass heading of this vector: 0 = north, 90 = east.
    var headingDegrees: Double {
        let degrees = atan2(x, y) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    static func unit(headingDegrees: Double) -> SIMD2<Double> {
        let radians = headingDegrees * .pi / 180
        return SIMD2(sin(radians), cos(radians))
    }
}
