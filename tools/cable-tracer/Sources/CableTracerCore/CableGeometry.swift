import Foundation
import RpplCore

/// What the traced shape says a cable is, independent of the `direction` label.
public enum CableKind: String, Codable, Sendable, CaseIterable {
    /// Full-size system: a closed loop (5 or 6 towers in reality, traced as 4-5 bends).
    case loop
    /// "2.0" / training cable: back and forth on one straight line, traced as 2 points.
    case straight
    case unknown

    public init(direction: ParkCableDirection?) {
        if direction == .twoPointZero { self = .straight } else if direction?.isLoop == true { self = .loop } else { self = .unknown }
    }
}

/// Principal axes of the traced points: the oriented box the cable fits in.
public struct PrincipalAxes: Codable, Equatable, Sendable {
    /// Centroid of the vertices, metres from the park location.
    public var center: SIMD2<Double>
    /// Heading of the long axis, 0..<180 (a line has no front or back).
    public var headingDegrees: Double
    /// Extent along the long axis, metres.
    public var lengthM: Double
    /// Extent across it, metres.
    public var widthM: Double
}

/// Shape statistics of one cable in a park's local frame. Everything the plausibility checks,
/// the priors learned from existing parks and the training-set export need.
public struct CableGeometry: Codable, Equatable, Sendable {
    public var kind: CableKind
    public var isClosed: Bool
    /// Vertices in travel order, metres east/north of the park location.
    public var pointsXY: [SIMD2<Double>]
    public var segmentLengthsM: [Double]
    /// Length along the traced path; includes the closing segment for loops.
    public var pathLengthM: Double
    /// Heading change at each vertex where two segments meet (0 = straight on, 180 = full reversal).
    public var turnAnglesDeg: [Double]
    public var axes: PrincipalAxes
    public var distanceToParkM: Double

    public init(cable: ParkCable, parkLocation: ParkCoordinate) {
        let projection = LocalProjection(origin: parkLocation)
        let points = (cable.points ?? []).map { projection.xy($0.coordinate) }
        let kind = CableKind(direction: cable.direction)
        self.init(pointsXY: points, kind: kind)
    }

    public init(pointsXY points: [SIMD2<Double>], kind: CableKind) {
        self.kind = kind
        self.isClosed = kind == .loop && points.count >= 3
        self.pointsXY = points

        var segments: [Double] = []
        if points.count >= 2 {
            for index in 1..<points.count { segments.append((points[index] - points[index - 1]).length) }
            if isClosed, let first = points.first, let last = points.last { segments.append((first - last).length) }
        }
        self.segmentLengthsM = segments
        self.pathLengthM = segments.reduce(0, +)

        var turns: [Double] = []
        if points.count >= 3 {
            let range: [Int] = isClosed ? Array(points.indices) : Array(points.indices.dropFirst().dropLast())
            for index in range {
                let previous = points[(index - 1 + points.count) % points.count]
                let next = points[(index + 1) % points.count]
                let incoming = points[index] - previous
                let outgoing = next - points[index]
                guard incoming.length > 0.01, outgoing.length > 0.01 else { continue }
                let scalar: Double = incoming.x * outgoing.x + incoming.y * outgoing.y
                let norm: Double = incoming.length * outgoing.length
                let dot: Double = scalar / norm
                turns.append(acos(max(-1, min(1, dot))) * 180 / .pi)
            }
        }
        self.turnAnglesDeg = turns
        self.axes = Self.principalAxes(points)
        self.distanceToParkM = axes.center.length
    }

    /// PCA on the vertices: long-axis heading plus the extents along and across it.
    static func principalAxes(_ points: [SIMD2<Double>]) -> PrincipalAxes {
        guard !points.isEmpty else { return PrincipalAxes(center: .zero, headingDegrees: 0, lengthM: 0, widthM: 0) }
        let count = Double(points.count)
        let center = points.reduce(SIMD2<Double>.zero, +) / count
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for point in points {
            let delta = point - center
            sxx += delta.x * delta.x
            syy += delta.y * delta.y
            sxy += delta.x * delta.y
        }
        // Eigenvector of the larger eigenvalue of [[sxx, sxy], [sxy, syy]].
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        let axis = SIMD2(cos(theta), sin(theta))
        let across = SIMD2(-axis.y, axis.x)
        var minAlong = Double.infinity, maxAlong = -Double.infinity
        var minAcross = Double.infinity, maxAcross = -Double.infinity
        for point in points {
            let delta = point - center
            let along = delta.x * axis.x + delta.y * axis.y
            let side = delta.x * across.x + delta.y * across.y
            minAlong = min(minAlong, along); maxAlong = max(maxAlong, along)
            minAcross = min(minAcross, side); maxAcross = max(maxAcross, side)
        }
        var heading = axis.headingDegrees
        if heading >= 180 { heading -= 180 }
        return PrincipalAxes(
            center: center,
            headingDegrees: heading,
            lengthM: maxAlong - minAlong,
            widthM: maxAcross - minAcross
        )
    }

    /// Whether every bend turns the same way. Towers stand outside the loop and pull the cable,
    /// so a traced full-size loop is a convex polygon; a bend the other way means a point is
    /// out of order or a tower was drawn "pushing" from the inside.
    public var isConvex: Bool {
        guard isClosed, pointsXY.count >= 3 else { return true }
        var sign = 0.0
        let count = pointsXY.count
        for index in 0..<count {
            let previous = pointsXY[(index - 1 + count) % count], current = pointsXY[index], next = pointsXY[(index + 1) % count]
            let cross = (current.x - previous.x) * (next.y - current.y) - (current.y - previous.y) * (next.x - current.x)
            guard abs(cross) > 1 else { continue }  // collinear within a square metre
            if sign == 0 { sign = cross.sign == .minus ? -1 : 1 } else if (cross < 0) != (sign < 0) { return false }
        }
        return true
    }

    /// Signed travel direction of a closed loop as seen from above: `.counterClockwise`, `.clockwise`, or nil for a line.
    public var windingDirection: ParkCableDirection? {
        guard isClosed, pointsXY.count >= 3 else { return nil }
        var area = 0.0
        for index in pointsXY.indices {
            let a = pointsXY[index], b = pointsXY[(index + 1) % pointsXY.count]
            area += a.x * b.y - b.x * a.y
        }
        if abs(area) < 1 { return nil }
        return area > 0 ? .counterClockwise : .clockwise
    }

    /// Whether the closed outline crosses itself (a loop traced in the wrong vertex order).
    public var isSelfIntersecting: Bool {
        guard isClosed, pointsXY.count >= 4 else { return false }
        let count = pointsXY.count
        for first in 0..<count {
            let a1 = pointsXY[first], a2 = pointsXY[(first + 1) % count]
            for second in stride(from: first + 2, to: count, by: 1) where !(first == 0 && second == count - 1) {
                let b1 = pointsXY[second], b2 = pointsXY[(second + 1) % count]
                if Self.segmentsIntersect(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    static func segmentsIntersect(_ p1: SIMD2<Double>, _ p2: SIMD2<Double>, _ p3: SIMD2<Double>, _ p4: SIMD2<Double>) -> Bool {
        func orientation(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let d1 = orientation(p3, p4, p1), d2 = orientation(p3, p4, p2)
        let d3 = orientation(p1, p2, p3), d4 = orientation(p1, p2, p4)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }
}
