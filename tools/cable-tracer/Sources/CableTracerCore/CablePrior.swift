import Foundation
import RpplCore

/// What traced parks say a typical cable looks like. Used for the first proposal at a park that
/// has only a location, and as a sanity reference next to the lint thresholds.
public struct CablePrior: Codable, Equatable, Sendable {
    public struct Shape: Codable, Equatable, Sendable {
        public var sampleCount: Int
        public var pathLengthM: Double
        public var extentLengthM: Double
        public var extentWidthM: Double
        public var distanceToParkM: Double
        public var pointCount: Int
    }

    public var loop: Shape
    public var straight: Shape

    /// Fallback when no parks are loaded; the medians of the repo in 2026-11.
    public static let bundled = CablePrior(
        loop: Shape(sampleCount: 0, pathLengthM: 760, extentLengthM: 250, extentWidthM: 70, distanceToParkM: 180, pointCount: 5),
        straight: Shape(sampleCount: 0, pathLengthM: 165, extentLengthM: 165, extentWidthM: 0, distanceToParkM: 150, pointCount: 2)
    )

    public static func learn(from parks: [Park]) -> CablePrior {
        var loops: [CableGeometry] = []
        var straights: [CableGeometry] = []
        for park in parks {
            for cable in park.cables ?? [] where (cable.points?.count ?? 0) >= 2 {
                let geometry = CableGeometry(cable: cable, parkLocation: park.location)
                switch geometry.kind {
                case .loop: loops.append(geometry)
                case .straight: straights.append(geometry)
                case .unknown: break
                }
            }
        }
        return CablePrior(
            loop: shape(loops) ?? bundled.loop,
            straight: shape(straights) ?? bundled.straight
        )
    }

    static func shape(_ geometries: [CableGeometry]) -> Shape? {
        guard !geometries.isEmpty else { return nil }
        return Shape(
            sampleCount: geometries.count,
            pathLengthM: median(geometries.map(\.pathLengthM)),
            extentLengthM: median(geometries.map(\.axes.lengthM)),
            extentWidthM: median(geometries.map(\.axes.widthM)),
            distanceToParkM: median(geometries.map(\.distanceToParkM)),
            pointCount: Int(median(geometries.map { Double($0.pointsXY.count) }).rounded())
        )
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// Builds a first cable for the reviewer to drag into place.
public enum CableTemplate {
    /// Oriented rectangle of the prior's size, centred `offset` metres from the park location.
    /// The vertices run in `direction` order starting at the corner nearest the park, so the
    /// start point and bends land on the right side of the water once the reviewer rotates it.
    public static func loop(
        at parkLocation: ParkCoordinate,
        prior: CablePrior.Shape,
        headingDegrees: Double = 0,
        offset: SIMD2<Double> = .zero,
        direction: ParkCableDirection = .counterClockwise
    ) -> ParkCable {
        let projection = LocalProjection(origin: parkLocation)
        let along = SIMD2<Double>.unit(headingDegrees: headingDegrees) * (prior.extentLengthM / 2)
        let across = SIMD2<Double>.unit(headingDegrees: headingDegrees + 90) * (prior.extentWidthM / 2)
        // Counter-clockwise order (as seen from above, north up).
        var corners = [offset - along - across, offset + along - across, offset + along + across, offset - along + across]
        if direction == .clockwise { corners.reverse() }
        if let nearest = corners.indices.min(by: { corners[$0].length < corners[$1].length }) {
            corners = Array(corners[nearest...] + corners[..<nearest])
        }
        var points = corners.map { corner -> ParkCablePoint in
            let coordinate = projection.coordinate(corner)
            return ParkCablePoint(lat: coordinate.lat, lon: coordinate.lon)
        }
        points[0].start = true
        return ParkCable(name: "Cable", direction: direction, points: points)
    }

    public static func straight(
        at parkLocation: ParkCoordinate,
        prior: CablePrior.Shape,
        headingDegrees: Double = 0,
        offset: SIMD2<Double> = .zero
    ) -> ParkCable {
        let projection = LocalProjection(origin: parkLocation)
        let half = SIMD2<Double>.unit(headingDegrees: headingDegrees) * (prior.pathLengthM / 2)
        let a = projection.coordinate(offset - half), b = projection.coordinate(offset + half)
        return ParkCable(
            name: "2.0",
            direction: .twoPointZero,
            points: [ParkCablePoint(lat: a.lat, lon: a.lon, start: true), ParkCablePoint(lat: b.lat, lon: b.lon)]
        )
    }

    /// The same vertices rotated by `degrees` around their centroid.
    public static func rotated(_ cable: ParkCable, by degrees: Double, parkLocation: ParkCoordinate) -> ParkCable {
        guard let points = cable.points, !points.isEmpty else { return cable }
        let projection = LocalProjection(origin: parkLocation)
        let xy = points.map { projection.xy($0.coordinate) }
        let center = xy.reduce(SIMD2<Double>.zero, +) / Double(xy.count)
        let radians = -degrees * .pi / 180  // compass headings turn clockwise
        var result = cable
        result.points = zip(points, xy).map { point, vertex in
            let delta = vertex - center
            let turned = SIMD2(delta.x * cos(radians) - delta.y * sin(radians), delta.x * sin(radians) + delta.y * cos(radians))
            let coordinate = projection.coordinate(center + turned)
            return ParkCablePoint(lat: coordinate.lat, lon: coordinate.lon, start: point.start)
        }
        return result
    }
}
