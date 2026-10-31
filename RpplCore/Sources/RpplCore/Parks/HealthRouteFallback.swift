import Foundation

/// The single spot Health gets as a route when a workout recorded too few GPS fixes: a pin, not a line.
public struct HealthRouteFallback: Equatable, Sendable {
    /// `cableStart`: the start point saved for the park's cable. `park`: the park's location.
    public enum Source: String, Sendable {
        case cableStart = "cable_start"
        case park
    }

    public let source: Source
    public let coordinates: [ParkCoordinate]

    /// Fewer usable fixes than this and the real route is too thin to be a map.
    public static let minimumRealFixes = 10

    public static func needsFallback(usableFixCount: Int) -> Bool {
        usableFixCount < minimumRealFixes
    }

    /// The start point of the park's first traced cable, else the park location.
    public static func make(for park: Park) -> HealthRouteFallback {
        // Two identical points: a lone fix gives Health nothing to draw.
        if let start = (park.cables ?? []).lazy.compactMap({ $0.startPoints.first }).first?.coordinate {
            return HealthRouteFallback(source: .cableStart, coordinates: [start, start])
        }
        return HealthRouteFallback(source: .park, coordinates: [park.location, park.location])
    }

    /// One timestamp per coordinate, evenly spread from `start` to `end`.
    public func timestamps(from start: Date, to end: Date) -> [Date] {
        guard coordinates.count > 1 else { return [start] }
        let step = max(end.timeIntervalSince(start), 0) / Double(coordinates.count - 1)
        return coordinates.indices.map { start.addingTimeInterval(step * Double($0)) }
    }
}
