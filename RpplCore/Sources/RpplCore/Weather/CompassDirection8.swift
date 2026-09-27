import Foundation

/// Simple 8-point compass direction (N, NE, E, …) derived from a meteorological "wind from"
/// bearing in degrees (0° = north, clockwise). Coarser than WeatherKit's own 16-point
/// `Wind.CompassDirection` — the product wants plain cardinal/intercardinal names, not
/// NNE/ENE-style detail.
public enum CompassDirection8: Int, CaseIterable, Equatable, Sendable {
    case north, northeast, east, southeast, south, southwest, west, northwest

    public init(degrees: Double) {
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        let index = Int((positive / 45).rounded()) % 8
        self = CompassDirection8(rawValue: index) ?? .north
    }

    public var name: String {
        switch self {
        case .north: String(localized: "North", bundle: .module)
        case .northeast: String(localized: "Northeast", bundle: .module)
        case .east: String(localized: "East", bundle: .module)
        case .southeast: String(localized: "Southeast", bundle: .module)
        case .south: String(localized: "South", bundle: .module)
        case .southwest: String(localized: "Southwest", bundle: .module)
        case .west: String(localized: "West", bundle: .module)
        case .northwest: String(localized: "Northwest", bundle: .module)
        }
    }

    public var abbreviation: String {
        switch self {
        case .north: String(localized: "N", bundle: .module, comment: "Compass abbreviation: north")
        case .northeast: String(localized: "NE", bundle: .module, comment: "Compass abbreviation: northeast")
        case .east: String(localized: "E", bundle: .module, comment: "Compass abbreviation: east")
        case .southeast: String(localized: "SE", bundle: .module, comment: "Compass abbreviation: southeast")
        case .south: String(localized: "S", bundle: .module, comment: "Compass abbreviation: south")
        case .southwest: String(localized: "SW", bundle: .module, comment: "Compass abbreviation: southwest")
        case .west: String(localized: "W", bundle: .module, comment: "Compass abbreviation: west")
        case .northwest: String(localized: "NW", bundle: .module, comment: "Compass abbreviation: northwest")
        }
    }
}
