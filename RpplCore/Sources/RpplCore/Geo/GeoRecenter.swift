import Foundation

/// Rigid rotation of the globe that carries one anchor point to (0°, 0°).
///
/// Every point of a session goes through the same rotation, so the session moves as one piece and
/// nothing inside it is warped: the great-circle distance between any two points stays identical
/// (what `GeoDistance` measures), so set distance, laps and speeds come out the same afterwards.
///
/// Subtracting the anchor's degrees does not do that. A degree of longitude shrinks towards the
/// poles but not at the equator, so a track shifted that way is stretched east-west by
/// 1 / cos(latitude), about 1.6× at 52°N.
///
/// North stays north at the anchor. Across a few km the bearing between two points drifts by
/// far less than 0.1°, well below GPS course noise, so recorded `course` values stay valid.
/// Points near the antimeridian or a pole need no special case: the math runs on unit vectors,
/// not on degrees.
public struct GeoRecenter: Equatable, Sendable {
    /// Point on the unit sphere (x towards 0°N 0°E, y towards 0°N 90°E, z towards the north pole).
    private struct Direction: Equatable, Sendable {
        var x: Double
        var y: Double
        var z: Double

        init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }

        init(latitude: Double, longitude: Double) {
            let lat = latitude * .pi / 180
            let lon = longitude * .pi / 180
            self.init(x: cos(lat) * cos(lon), y: cos(lat) * sin(lon), z: sin(lat))
        }

        func dot(_ other: Direction) -> Double {
            x * other.x + y * other.y + z * other.z
        }
    }

    // Local frame at the anchor. After the rotation these are the axes x, y and z.
    private let up: Direction
    private let east: Direction
    private let north: Direction

    /// Rotation that moves the point at `anchorLatitude` / `anchorLongitude` (degrees) to (0°, 0°).
    public init(anchorLatitude: Double, anchorLongitude: Double) {
        let lat = anchorLatitude * .pi / 180
        let lon = anchorLongitude * .pi / 180
        up = Direction(x: cos(lat) * cos(lon), y: cos(lat) * sin(lon), z: sin(lat))
        east = Direction(x: -sin(lon), y: cos(lon), z: 0)
        north = Direction(x: -sin(lat) * cos(lon), y: -sin(lat) * sin(lon), z: cos(lat))
    }

    /// Anchors on the centre of `coordinates` (mean of their unit vectors), so the whole set
    /// ends up around (0°, 0°). Nil when `coordinates` is empty.
    public init?(centeringOn coordinates: [(latitude: Double, longitude: Double)]) {
        guard let first = coordinates.first else { return nil }
        var sumX = 0.0
        var sumY = 0.0
        var sumZ = 0.0
        for coordinate in coordinates {
            let point = Direction(latitude: coordinate.latitude, longitude: coordinate.longitude)
            sumX += point.x
            sumY += point.y
            sumZ += point.z
        }
        let length = (sumX * sumX + sumY * sumY + sumZ * sumZ).squareRoot()
        // Points spread over the whole globe cancel out; any anchor will do then.
        guard length > 1e-9 else {
            self.init(anchorLatitude: first.latitude, anchorLongitude: first.longitude)
            return
        }
        self.init(
            anchorLatitude: Self.degrees(asin(Self.clampedUnit(sumZ / length))),
            anchorLongitude: Self.degrees(atan2(sumY, sumX))
        )
    }

    /// The rotated position of a point, in degrees: latitude in `[-90, 90]`, longitude in `[-180, 180]`.
    public func apply(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
        let point = Direction(latitude: latitude, longitude: longitude)
        let rotatedX = point.dot(up)
        let rotatedY = point.dot(east)
        let rotatedZ = point.dot(north)
        return (
            latitude: Self.degrees(asin(Self.clampedUnit(rotatedZ))),
            longitude: Self.degrees(atan2(rotatedY, rotatedX))
        )
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    /// Rounding can push a dot product a hair past ±1, where `asin` returns NaN.
    private static func clampedUnit(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}
