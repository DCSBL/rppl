import Foundation

/// A candidate cable loop in local metres, with the evidence behind its score.
public struct CableLoopCandidate: Sendable, Equatable {
    /// Convex polygon, travel order unknown.
    public var vertices: [SIMD2<Double>]
    public var score: Double
    public var vertexSupport: [Double]
    public var edgeSupport: Double
    public var waterFraction: Double
    public var perimeterM: Double
    public var notes: [String]

    /// Below this the proposal is a guess: in the prototype every proposal under 9 was wrong.
    public static let weakScore = 9.0
    public var isWeak: Bool { score < Self.weakScore }
}

/// Fits a convex loop of 4-6 masts to the floating objects and mast detections on the water, the
/// way the Python prototype in tools/cable-tracer/detect does. Scores combine support at the
/// vertices, obstacles along the edges, an empty interior, edges over water, a perimeter prior
/// and the corner rule (a cable turns at most ~95 degrees around one mast).
struct LoopFitter {
    static let perimeterMedianM = 700.0
    static let perimeterLogSigma = 0.28
    static let maxTurnDeg = 95.0
    static let impossibleTurnDeg = maxTurnDeg + 25

    struct Evidence {
        var xy: SIMD2<Double>
        var weight: Double
    }

    var vertexRadiusM = 14.0
    var edgeRadiusM = 18.0
    /// The cable is never far from the park location (all traced parks: centroid < 260 m).
    var maxDistanceM = 520.0
    var vertexCounts = [4, 5, 6]
    var isWater: (SIMD2<Double>) -> Bool

    /// Proposals sorted best first. `evidence` is in local metres around the park location.
    func propose(evidence rawEvidence: [Evidence]) -> [CableLoopCandidate] {
        let near = rawEvidence.filter { vectorLength($0.xy) <= maxDistanceM }
        let merged = Self.mergeClose(near, radiusM: 10)
        var candidates: [CableLoopCandidate] = []
        guard merged.count >= 4 else { return candidates }
        let points = merged.map(\.xy)
        for group in Self.cluster(points, linkM: 260).prefix(2) where group.count >= 4 {
            let cluster = group.map { points[$0] }
            for k in vertexCounts where cluster.count >= k {
                guard var start = Self.simplifyHull(cluster, target: k), start.count == k else { continue }
                // Objects sit inside the cable line; push the hull out a little before refining.
                let centroid = cluster.reduce(SIMD2<Double>(0, 0), +) / Double(cluster.count)
                start = start.map { centroid + ($0 - centroid) * 1.06 }
                var candidate = refine(start, evidence: merged)
                candidates.append(candidate)
                // A knee sharper than any mast is a vertex that should not exist: drop it and refit.
                // Coordinate descent cannot do this on its own (it moves one vertex at a time).
                for _ in 0..<2 {
                    guard candidate.vertices.count > 4, let knee = Self.sharpestVertex(candidate.vertices) else { break }
                    var fewer = candidate.vertices
                    fewer.remove(at: knee)
                    candidate = refine(fewer, evidence: merged)
                    candidates.append(candidate)
                }
            }
        }
        return candidates.sorted { $0.score > $1.score }
    }

    // MARK: Scoring

    func score(_ vertices: [SIMD2<Double>], evidence: [Evidence]) -> CableLoopCandidate {
        var notes: [String] = []
        let area = Geometry2D.area(vertices)
        guard vertices.count >= 3, area >= 1, !Geometry2D.isSelfIntersecting(vertices) else {
            return CableLoopCandidate(vertices: vertices, score: -1e9, vertexSupport: [], edgeSupport: 0, waterFraction: 0, perimeterM: 0, notes: ["degenerate"])
        }
        let convex = Geometry2D.convexHull(vertices).count == vertices.count
        let perimeter = Geometry2D.perimeter(vertices)

        // Vertex support: an object (mast platform/shadow) or mast detection close to each vertex, capped at 1.
        var support: [Double] = []
        for vertex in vertices {
            var best = 0.0
            for point in evidence {
                let d = vectorLength(point.xy - vertex)
                if d < vertexRadiusM {
                    best = max(best, min(1, point.weight / 2) * max(0, 1 - d / vertexRadiusM) )
                }
            }
            support.append(best)
        }
        // Obstacles sit along the cable; the middle of a loop is empty water.
        var edge = 0.0, interior = 0.0, outside = 0.0
        for point in evidence {
            let d = Geometry2D.distanceToRing(point.xy, vertices)
            let w = min(1, point.weight / 2)
            if d <= edgeRadiusM {
                edge += w
            } else if Geometry2D.contains(vertices, point.xy) {
                interior += w
            } else if d < 120 {
                outside += 0.25 * w  // a floating thing just outside the loop is suspicious
            }
        }
        edge = min(edge, 10)

        // Edges must run over water; sample every ~5 m.
        var samples = 0, wet = 0
        for index in vertices.indices {
            let a = vertices[index], b = vertices[(index + 1) % vertices.count]
            let n = max(2, Int(vectorLength(b - a) / 5))
            for k in 0..<n {
                samples += 1
                if isWater(a + (b - a) * (Double(k) / Double(n))) { wet += 1 }
            }
        }
        let waterFraction = Double(wet) / Double(max(1, samples))

        // Corner rule: 126 traced bends turn 36-94 degrees; a sharper knee is not a mast.
        var cornerPenalty = 0.0
        for turn in Geometry2D.turnAnglesDegrees(vertices) {
            if turn > Self.impossibleTurnDeg {
                cornerPenalty += 15
                notes.append("corner of \(Int(turn.rounded())) degrees")
            } else if turn > Self.maxTurnDeg {
                cornerPenalty += (turn - Self.maxTurnDeg) / 5
            }
        }

        let prior = -pow(log(perimeter / Self.perimeterMedianM), 2) / (2 * Self.perimeterLogSigma * Self.perimeterLogSigma)
        // Shape prior: real loops are wide (axis ratio rarely over 3.5).
        let sides = Geometry2D.minimumRectangleSides(vertices)
        let ratio = max(sides.long, 1e-6) / max(sides.short, 1e-6)
        let shape = -max(0, ratio - 3.5)
        // Most full-size systems have 5 masts; 4 and 6 happen, more is a trace with extra points.
        let complexity: Double
        switch vertices.count {
        case 4: complexity = -0.5
        case 5: complexity = 0
        case 6: complexity = -2
        default: complexity = -4
        }
        var total = 2 * support.reduce(0, +) + 0.6 * edge - outside - interior + 4 * prior + shape + complexity - cornerPenalty
        if waterFraction < 0.97 {
            total -= 400 * (0.97 - waterFraction)
            notes.append("edges over land: \(Int((100 * (1 - waterFraction)).rounded()))%")
        }
        if !convex {
            total -= 20
            notes.append("not convex")
        }
        return CableLoopCandidate(vertices: vertices, score: total, vertexSupport: support, edgeSupport: edge, waterFraction: waterFraction, perimeterM: perimeter, notes: notes)
    }

    /// Coordinate descent: move one vertex at a time on a grid, keep improvements.
    func refine(_ vertices: [SIMD2<Double>], evidence: [Evidence], stepM: Double = 6, radiusM: Double = 30, rounds: Int = 4) -> CableLoopCandidate {
        var best = score(vertices, evidence: evidence)
        var offsets: [SIMD2<Double>] = []
        var dx = -radiusM
        while dx <= radiusM + 1e-6 {
            var dy = -radiusM
            while dy <= radiusM + 1e-6 {
                offsets.append(SIMD2(dx, dy))
                dy += stepM
            }
            dx += stepM
        }
        for _ in 0..<rounds {
            var improved = false
            for index in best.vertices.indices {
                let base = best.vertices
                for offset in offsets {
                    var trial = base
                    trial[index] = base[index] + offset
                    let candidate = score(trial, evidence: evidence)
                    if candidate.score > best.score + 1e-6 {
                        best = candidate
                        improved = true
                    }
                }
            }
            if !improved { break }
        }
        return best
    }

    // MARK: Evidence helpers

    /// Single-linkage clusters (indices), largest first.
    static func cluster(_ points: [SIMD2<Double>], linkM: Double) -> [[Int]] {
        var parent = Array(points.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for a in points.indices {
            for b in (a + 1)..<points.count where vectorLength(points[a] - points[b]) <= linkM {
                let ra = find(a), rb = find(b)
                if ra != rb { parent[ra] = rb }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in points.indices { groups[find(i), default: []].append(i) }
        return groups.values.sorted { $0.count > $1.count }
    }

    /// Mast platforms and their shadows split into 2-3 objects; merge them into one weighted point.
    static func mergeClose(_ evidence: [Evidence], radiusM: Double) -> [Evidence] {
        let points = evidence.map(\.xy)
        return cluster(points, linkM: radiusM).map { group in
            var sum = SIMD2<Double>(0, 0), weight = 0.0
            for i in group { sum += evidence[i].xy * evidence[i].weight; weight += evidence[i].weight }
            return Evidence(xy: sum / weight, weight: weight)
        }
    }

    /// Convex hull reduced to `target` vertices by dropping the vertex that loses the least area.
    static func simplifyHull(_ points: [SIMD2<Double>], target: Int) -> [SIMD2<Double>]? {
        var hull = Geometry2D.convexHull(points)
        guard hull.count >= 3 else { return nil }
        while hull.count > target {
            var bestIndex = 0, bestLoss = Double.infinity
            let area = Geometry2D.area(hull)
            for index in hull.indices {
                var trial = hull
                trial.remove(at: index)
                let loss = area - Geometry2D.area(trial)
                if loss < bestLoss { bestLoss = loss; bestIndex = index }
            }
            hull.remove(at: bestIndex)
        }
        return hull
    }

    static func sharpestVertex(_ vertices: [SIMD2<Double>], limitDeg: Double = impossibleTurnDeg) -> Int? {
        var worst: Int?
        var worstTurn = limitDeg
        for (index, turn) in Geometry2D.turnAnglesDegrees(vertices).enumerated() where turn > worstTurn {
            worst = index
            worstTurn = turn
        }
        return worst
    }
}

/// Plain 2D polygon helpers on local-metre points.
enum Geometry2D {
    static func area(_ polygon: [SIMD2<Double>]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var twice = 0.0
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            twice += a.x * b.y - b.x * a.y
        }
        return abs(twice) / 2
    }

    static func perimeter(_ polygon: [SIMD2<Double>]) -> Double {
        guard polygon.count >= 2 else { return 0 }
        var total = 0.0
        for index in polygon.indices { total += vectorLength(polygon[(index + 1) % polygon.count] - polygon[index]) }
        return total
    }

    /// Turn at each vertex in degrees (0 = straight on).
    static func turnAnglesDegrees(_ polygon: [SIMD2<Double>]) -> [Double] {
        guard polygon.count >= 3 else { return [] }
        return polygon.indices.map { index in
            let incoming = polygon[index] - polygon[(index + polygon.count - 1) % polygon.count]
            let outgoing = polygon[(index + 1) % polygon.count] - polygon[index]
            let cosine = vectorDot(incoming, outgoing) / max(1e-9, vectorLength(incoming) * vectorLength(outgoing))
            return acos(min(max(cosine, -1), 1)) * 180 / .pi
        }
    }

    /// Andrew's monotone chain; collinear points are left out. Counter-clockwise order.
    static func convexHull(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count >= 3 else { return sorted }
        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Double>] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [SIMD2<Double>] = []
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    static func distance(_ p: SIMD2<Double>, toSegment a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let ab = b - a
        let lengthSquared = vectorDot(ab, ab)
        guard lengthSquared > 0 else { return vectorLength(p - a) }
        let t = min(max(vectorDot(p - a, ab) / lengthSquared, 0), 1)
        return vectorLength(p - (a + ab * t))
    }

    static func distanceToRing(_ p: SIMD2<Double>, _ polygon: [SIMD2<Double>]) -> Double {
        var best = Double.infinity
        for index in polygon.indices {
            best = min(best, distance(p, toSegment: polygon[index], polygon[(index + 1) % polygon.count]))
        }
        return best
    }

    /// Ray casting; points on the boundary count as outside.
    static func contains(_ polygon: [SIMD2<Double>], _ p: SIMD2<Double>) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    static func segmentsIntersect(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, _ d: SIMD2<Double>) -> Bool {
        func orientation(_ p: SIMD2<Double>, _ q: SIMD2<Double>, _ r: SIMD2<Double>) -> Double {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let o1 = orientation(a, b, c), o2 = orientation(a, b, d), o3 = orientation(c, d, a), o4 = orientation(c, d, b)
        return (o1 * o2 < 0) && (o3 * o4 < 0)
    }

    /// Whether two non-adjacent edges cross (a bow-tie polygon).
    static func isSelfIntersecting(_ polygon: [SIMD2<Double>]) -> Bool {
        let n = polygon.count
        guard n >= 4 else { return false }
        for i in 0..<(n - 2) {
            for j in (i + 2)..<n where !(i == 0 && j == n - 1) {
                if segmentsIntersect(polygon[i], polygon[(i + 1) % n], polygon[j], polygon[(j + 1) % n]) { return true }
            }
        }
        return false
    }

    /// Side lengths of the smallest-area rectangle around the points (rotating calipers over hull edges).
    static func minimumRectangleSides(_ points: [SIMD2<Double>]) -> (long: Double, short: Double) {
        let hull = convexHull(points)
        guard hull.count >= 2 else { return (0, 0) }
        var best: (long: Double, short: Double) = (.infinity, .infinity)
        var bestArea = Double.infinity
        for index in hull.indices {
            let edge = hull[(index + 1) % hull.count] - hull[index]
            let length = vectorLength(edge)
            guard length > 0 else { continue }
            let along = edge / length
            let across = SIMD2(-along.y, along.x)
            var minAlong = Double.infinity, maxAlong = -Double.infinity, minAcross = Double.infinity, maxAcross = -Double.infinity
            for p in hull {
                let u = vectorDot(p, along), v = vectorDot(p, across)
                minAlong = min(minAlong, u); maxAlong = max(maxAlong, u)
                minAcross = min(minAcross, v); maxAcross = max(maxAcross, v)
            }
            let a = maxAlong - minAlong, b = maxAcross - minAcross
            if a * b < bestArea {
                bestArea = a * b
                best = (max(a, b), min(a, b))
            }
        }
        return best
    }
}

// `simd_length`/`simd_dot` live in Apple's simd module, which Linux lacks.
@inline(__always) func vectorLength(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }
@inline(__always) func vectorDot(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.x + a.y * b.y }
