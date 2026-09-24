import Foundation

/// Pure validation and cable-trace helpers behind the park editor.
public enum ParkDraft {
    public enum Issue: Equatable, Sendable {
        case missingName
        case invalidLocation
        case cableTooShort(index: Int)
        case invalidCablePoint(cable: Int)
    }

    public static func validate(_ park: Park) -> [Issue] {
        var issues: [Issue] = []
        if park.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.missingName) }
        if !isValid(park.location) { issues.append(.invalidLocation) }
        for (index, cable) in (park.cables ?? []).enumerated() {
            let points = cable.points ?? []
            // A cable without traced points is allowed (imagery is not always good enough); one point is not a line.
            if points.count == 1 { issues.append(.cableTooShort(index: index)) }
            if points.contains(where: { !isValid($0.coordinate) }) { issues.append(.invalidCablePoint(cable: index)) }
        }
        return issues
    }

    public static func isValid(_ coordinate: ParkCoordinate) -> Bool {
        (-90...90).contains(coordinate.lat) && (-180...180).contains(coordinate.lon)
            && !(coordinate.lat == 0 && coordinate.lon == 0)
    }

    public static func append(_ coordinate: ParkCoordinate, to cable: inout ParkCable) {
        var points = cable.points ?? []
        points.append(ParkCablePoint(lat: coordinate.lat, lon: coordinate.lon))
        cable.points = points
    }

    public static func undo(_ cable: inout ParkCable) {
        guard var points = cable.points, !points.isEmpty else { return }
        points.removeLast()
        cable.points = points.isEmpty ? nil : points
    }

    public static func move(_ cable: inout ParkCable, index: Int, to coordinate: ParkCoordinate) {
        guard var points = cable.points, points.indices.contains(index) else { return }
        points[index].lat = coordinate.lat
        points[index].lon = coordinate.lon
        cable.points = points
    }

    public static func toggleStart(_ cable: inout ParkCable, index: Int) {
        guard var points = cable.points, points.indices.contains(index) else { return }
        points[index].start = points[index].start == true ? nil : true
        cable.points = points
    }

    /// Centroid of the traced points, for placing a new park's pin.
    public static func centroid(of cables: [ParkCable]) -> ParkCoordinate? {
        let points = cables.flatMap { $0.points ?? [] }
        guard !points.isEmpty else { return nil }
        return ParkCoordinate(
            lat: points.map(\.lat).reduce(0, +) / Double(points.count),
            lon: points.map(\.lon).reduce(0, +) / Double(points.count)
        )
    }
}
