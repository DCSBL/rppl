import Foundation
import RpplCore

/// Plausibility rules for a traced cable. The thresholds come from the 44 traced cables in the
/// repo (2026-11): full-size loops are 4-5 bends and 480-1000 m, 2.0 cables are one straight
/// line of 110-220 m, and every vertex lies within a few hundred metres of the park location.
public struct CableLintFinding: Equatable, Sendable, Identifiable {
    public enum Severity: String, Sendable { case warning, error }

    public var id: String { "\(cableIndex)-\(pointIndex.map(String.init) ?? "-")-\(message)" }
    public var severity: Severity
    public var cableIndex: Int
    public var pointIndex: Int?
    public var message: String
}

public enum CableLint {
    public struct Thresholds: Sendable {
        public var loopLengthWarning: ClosedRange<Double> = 350...1300
        public var loopLengthError: ClosedRange<Double> = 150...2500
        public var loopWidthMinimum = 15.0
        public var straightLengthWarning: ClosedRange<Double> = 60...300
        public var minimumSegmentM = 20.0
        public var sharpTurnDeg = 150.0
        public var distanceWarningM = 1000.0
        public var distanceErrorM = 3000.0
        public var declaredLengthTolerance = 0.25
        public init() {}
    }

    public static func check(_ park: Park, thresholds: Thresholds = Thresholds()) -> [CableLintFinding] {
        var findings: [CableLintFinding] = []
        for (index, cable) in (park.cables ?? []).enumerated() {
            findings += check(cable, index: index, parkLocation: park.location, thresholds: thresholds)
        }
        return findings
    }

    public static func check(_ cable: ParkCable, index: Int, parkLocation: ParkCoordinate, thresholds: Thresholds = Thresholds()) -> [CableLintFinding] {
        var findings: [CableLintFinding] = []
        func add(_ severity: CableLintFinding.Severity, _ message: String, point: Int? = nil) {
            findings.append(CableLintFinding(severity: severity, cableIndex: index, pointIndex: point, message: message))
        }

        guard let points = cable.points, !points.isEmpty else { return [] }  // untraced: nothing to judge
        let geometry = CableGeometry(cable: cable, parkLocation: parkLocation)
        if cable.direction == nil { add(.warning, "No direction (cw, ccw or 2.0); the shape cannot be judged") }
        if points.count < 2 { add(.error, "Fewer than 2 points"); return findings }

        for (pointIndex, point) in points.enumerated() {
            let distance = point.coordinate.meters(to: parkLocation)
            if distance > thresholds.distanceErrorM {
                add(.error, "Point is \(Int(distance)) m from the park location", point: pointIndex)
            } else if distance > thresholds.distanceWarningM {
                add(.warning, "Point is \(Int(distance)) m from the park location", point: pointIndex)
            }
        }
        for (segmentIndex, length) in geometry.segmentLengthsM.enumerated() {
            if length < 1 {
                add(.error, "Duplicate point", point: (segmentIndex + 1) % points.count)
            } else if length < thresholds.minimumSegmentM {
                add(.warning, "Segment of only \(Int(length)) m", point: (segmentIndex + 1) % points.count)
            }
        }
        for turn in geometry.turnAnglesDeg where turn > thresholds.sharpTurnDeg {
            add(.warning, "Sharp turn of \(Int(turn))°: the route doubles back on itself")
        }

        switch geometry.kind {
        case .loop:
            if points.count < 4 { add(.warning, "Loop traced with \(points.count) points; full-size cables have 4-5 bends") }
            if points.count > 6 { add(.warning, "Loop traced with \(points.count) points; expected 4-5 bends") }
            if !thresholds.loopLengthError.contains(geometry.pathLengthM) {
                add(.error, "Loop length \(Int(geometry.pathLengthM)) m is not a cable-park size")
            } else if !thresholds.loopLengthWarning.contains(geometry.pathLengthM) {
                add(.warning, "Loop length \(Int(geometry.pathLengthM)) m is unusual (most are 480-1000 m)")
            }
            if geometry.axes.widthM < thresholds.loopWidthMinimum {
                add(.warning, "Loop is only \(Int(geometry.axes.widthM)) m wide; looks like a straight line, is this a 2.0?")
            }
            if geometry.isSelfIntersecting { add(.error, "Loop crosses itself; points are not in travel order") }
        case .straight:
            if points.count != 2 { add(.warning, "2.0 cable traced with \(points.count) points; expected a start and an end") }
            if !thresholds.straightLengthWarning.contains(geometry.pathLengthM) {
                add(.warning, "2.0 length \(Int(geometry.pathLengthM)) m is unusual (most are 110-220 m)")
            }
            if points.count > 2, geometry.axes.widthM > thresholds.loopWidthMinimum {
                add(.warning, "2.0 cable is \(Int(geometry.axes.widthM)) m wide; a 2.0 runs on one line, is this a loop?")
            }
        case .unknown:
            break
        }

        if let declared = cable.lengthM, geometry.pathLengthM > 0 {
            let ratio = abs(declared - geometry.pathLengthM) / declared
            if ratio > thresholds.declaredLengthTolerance {
                add(.warning, "Traced \(Int(geometry.pathLengthM)) m but length_m says \(Int(declared)) m")
            }
        }
        if points.filter({ $0.start == true }).count > 1, geometry.kind == .straight {
            add(.warning, "2.0 cable with more than one start")
        }
        return findings
    }
}
