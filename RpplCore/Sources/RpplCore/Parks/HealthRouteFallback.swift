import Foundation

/// What to draw on the Health route map when a workout recorded too few GPS fixes to show a route.
public struct HealthRouteFallback: Equatable, Sendable {
    /// `cable`: the park's saved cable outline. `park`: only the park's location.
    public enum Source: String, Sendable {
        case cable
        case park
    }

    public let source: Source
    public let coordinates: [ParkCoordinate]

    /// Fewer usable fixes than this and the real route is too thin to be a map.
    public static let minimumRealFixes = 10

    public static func needsFallback(usableFixCount: Int) -> Bool {
        usableFixCount < minimumRealFixes
    }

    /// The park's first traced cable (closed when it is a loop), else the park location.
    public static func make(for park: Park) -> HealthRouteFallback {
        for cable in park.cables ?? [] {
            var points = (cable.points ?? []).map(\.coordinate)
            guard points.count >= 2 else { continue }
            if cable.direction?.isLoop == true, let first = points.first { points.append(first) }
            return HealthRouteFallback(source: .cable, coordinates: points)
        }
        // Two points: a lone fix gives Health nothing to draw.
        return HealthRouteFallback(source: .park, coordinates: [park.location, park.location])
    }

    /// One timestamp per coordinate, evenly spread from `start` to `end`.
    public func timestamps(from start: Date, to end: Date) -> [Date] {
        guard coordinates.count > 1 else { return [start] }
        let step = max(end.timeIntervalSince(start), 0) / Double(coordinates.count - 1)
        return coordinates.indices.map { start.addingTimeInterval(step * Double($0)) }
    }
}
