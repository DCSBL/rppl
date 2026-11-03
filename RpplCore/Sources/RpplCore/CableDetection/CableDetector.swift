import Foundation

/// A mast found by the mast detector, in local metres.
public struct DetectedMast: Sendable, Equatable {
    public var xy: SIMD2<Double>
    public var probability: Double
}

/// What the detector found on one close-up: proposals best first, plus the evidence for review.
public struct CableDetectionResult: Sendable {
    public var candidates: [CableLoopCandidate]
    public var objects: [FloatingObject]
    public var masts: [DetectedMast]
    /// Share of the image that is the park's water body.
    public var waterFraction: Double
    public var notes: [String]
    public var elapsed: TimeInterval

    public var best: CableLoopCandidate? { candidates.first }

    /// Parks are added by people; a proposal is a starting point for them, never the truth.
    public var summary: String {
        guard let best else { return notes.last ?? "No cable found" }
        var parts = ["\(best.vertices.count) masts", "\(Int(best.perimeterM.rounded())) m"]
        if best.isWeak { parts.append("weak match") }
        parts.append(contentsOf: best.notes)
        return parts.joined(separator: ", ")
    }
}

/// Finds the cable of a park on a satellite close-up: water, floating objects, masts, then a
/// convex loop that explains them. Pure Swift so it runs in tests and on every platform; the
/// image comes from a map snapshot in the app.
public enum CableDetector {
    public struct Options: Sendable {
        /// Use the bundled mast detector as extra vertex evidence (slower, better corners).
        public var useMastNet = true
        /// Weight of a mast detection as loop evidence: 2 means full vertex support on its own.
        public var mastWeight = 3.0
        public var minimumMastProbability = 0.5
        /// Cables already traced in the park, as polylines in local metres (loops closed), see
        /// `occupiedPolylines(of:in:)`. Evidence on them is theirs and the new loop stays clear of them.
        public var occupied: [[SIMD2<Double>]] = []

        public init() {}
    }

    /// The park's traced cables that fall on the image, in the image's local frame; loops are closed.
    /// Cables elsewhere (another lake of the same park) are left out.
    public static func occupiedPolylines(of cables: [ParkCable], in image: DetectionImage) -> [[SIMD2<Double>]] {
        cables.compactMap { cable -> [SIMD2<Double>]? in
            guard let points = cable.points, points.count >= 2 else { return nil }
            var line = points.map { image.localXY(of: $0.coordinate) }
            let onImage = line.contains { xy in
                let pixel = image.pixel(fromLocal: xy)
                return pixel.x >= 0 && pixel.y >= 0 && pixel.x < Double(image.width) && pixel.y < Double(image.height)
            }
            guard onImage else { return nil }
            if cable.direction?.isLoop == true, let first = line.first { line.append(first) }
            return line
        }
    }

    public static func detect(in image: DetectionImage, options: Options = Options()) -> CableDetectionResult {
        let started = Date()
        var notes: [String] = []
        let water = WaterSegmenter().segment(image)
        guard water.cellCount > 0 else {
            return CableDetectionResult(candidates: [], objects: [], masts: [], waterFraction: 0, notes: ["No water found near the park location"], elapsed: Date().timeIntervalSince(started))
        }
        let objects = BrightBlobDetector().detect(in: image, water: water)
        var masts: [DetectedMast] = []
        if options.useMastNet {
            if let net = MastNet.bundled {
                let heatmap = net.heatmap(of: image, water: water)
                masts = heatmap.peaks(probability: options.minimumMastProbability).compactMap { peak -> DetectedMast? in
                    // Masts stand on or right next to the water.
                    guard water.waterFraction(aroundColumn: Int(peak.column), row: Int(peak.row), halfSize: Int(10 / image.metersPerPixel)) >= 0.3 else { return nil }
                    return DetectedMast(xy: image.local(fromPixelColumn: peak.column, row: peak.row), probability: peak.probability)
                }
            } else {
                notes.append("Mast detector weights missing; using floating objects only")
            }
        }
        var evidence = objects.map { LoopFitter.Evidence(xy: $0.xy, weight: max(1, $0.areaM2 / 4)) }
        evidence += masts.map { LoopFitter.Evidence(xy: $0.xy, weight: options.mastWeight * $0.probability, shapesHull: false) }
        let occupied = options.occupied.filter { $0.count >= 2 }
        if !occupied.isEmpty {
            // Evidence on an already traced cable belongs to that cable, and so do the obstacles inside a traced loop.
            let taken = LoopFitter.occupiedClearanceM + 5
            let loops = occupied.filter { $0.count >= 4 && vectorLength($0[0] - $0[$0.count - 1]) < 1e-6 }.map { Array($0.dropLast()) }
            evidence.removeAll { point in
                occupied.contains { LoopFitter.distance(point.xy, toPolyline: $0) <= taken } || loops.contains { Geometry2D.contains($0, point.xy) }
            }
            notes.append("\(occupied.count) traced cable(s) kept clear")
        }
        let fitter = LoopFitter(occupied: occupied, isWater: { xy in
            let pixel = image.pixel(fromLocal: xy)
            return water.isWater(column: pixel.x, row: pixel.y)
        })
        let candidates = fitter.propose(evidence: evidence)
        if candidates.isEmpty {
            notes.append(evidence.count < 4 ? "Too few floating objects or masts to fit a loop" : "No plausible loop")
        }
        return CableDetectionResult(
            candidates: candidates,
            objects: objects,
            masts: masts,
            waterFraction: water.fraction,
            notes: notes,
            elapsed: Date().timeIntervalSince(started)
        )
    }

    /// Traced points for a proposal: the loop in the given travel direction, starting at the mast
    /// nearest the park location (the dock is usually by the entrance). Coordinates come from the
    /// image's local frame.
    public static func cable(from candidate: CableLoopCandidate, in image: DetectionImage, direction: ParkCableDirection, name: String? = nil) -> ParkCable {
        var vertices = candidate.vertices
        guard !vertices.isEmpty else { return ParkCable(name: name, direction: direction) }
        // Shoelace sign: positive is counter-clockwise in an x-east, y-north frame.
        var twice = 0.0
        for index in vertices.indices {
            let a = vertices[index], b = vertices[(index + 1) % vertices.count]
            twice += a.x * b.y - b.x * a.y
        }
        let isCounterClockwise = twice > 0
        if direction == .clockwise && isCounterClockwise || direction == .counterClockwise && !isCounterClockwise {
            vertices.reverse()
        }
        if let nearest = vertices.indices.min(by: { vectorLength(vertices[$0]) < vectorLength(vertices[$1]) }) {
            vertices = Array(vertices[nearest...] + vertices[..<nearest])
        }
        let points = vertices.map { xy -> ParkCablePoint in
            let coordinate = image.coordinate(fromLocal: xy)
            return ParkCablePoint(lat: coordinate.lat, lon: coordinate.lon)
        }
        return ParkCable(name: name, direction: direction, points: points)
    }
}
