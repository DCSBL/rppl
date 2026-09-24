import Foundation

public struct ParkCoordinate: Codable, Equatable, Sendable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    public func meters(to other: ParkCoordinate) -> Double {
        GeoDistance.meters(fromLat: lat, fromLon: lon, toLat: other.lat, toLon: other.lon)
    }
}

/// Opaque string so unknown values round-trip (`cw`, `ccw`, `2d`, …).
public struct ParkCableDirection: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let clockwise = ParkCableDirection(rawValue: "cw")
    public static let counterClockwise = ParkCableDirection(rawValue: "ccw")
    public static let twoD = ParkCableDirection(rawValue: "2d")

    /// Loop cables return to the start; 2D cables run back and forth on one line.
    public var isLoop: Bool { self == .clockwise || self == .counterClockwise }
}

public struct ParkCablePoint: Codable, Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public var start: Bool?

    public init(lat: Double, lon: Double, start: Bool? = nil) {
        self.lat = lat
        self.lon = lon
        self.start = start
    }

    public var coordinate: ParkCoordinate { ParkCoordinate(lat: lat, lon: lon) }
}

public struct ParkCableStart: Equatable, Sendable {
    public var point: ParkCablePoint
    /// Degrees clockwise from true north; nil when the cable has no second point.
    public var bearingDegrees: Double?
}

public struct ParkCable: Codable, Equatable, Sendable {
    public var name: String?
    public var direction: ParkCableDirection?
    public var description: String?
    /// Hardcoded length; wins over the length computed from `points`.
    public var lengthM: Double?
    /// Optional: satellite imagery is not always good enough to trace a cable.
    public var points: [ParkCablePoint]?

    enum CodingKeys: String, CodingKey {
        case name, direction, description, points
        case lengthM = "length_m"
    }

    public init(
        name: String? = nil,
        direction: ParkCableDirection? = nil,
        description: String? = nil,
        lengthM: Double? = nil,
        points: [ParkCablePoint]? = nil
    ) {
        self.name = name
        self.direction = direction
        self.description = description
        self.lengthM = lengthM
        self.points = points
    }

    /// Points flagged `start: true`; the first point when none is flagged.
    public var startPoints: [ParkCablePoint] { starts.map(\.point) }

    /// Start points with the travel bearing towards the next traced point (points are listed in travel order).
    public var starts: [ParkCableStart] {
        guard let points, !points.isEmpty else { return [] }
        var indices = points.indices.filter { points[$0].start == true }
        if indices.isEmpty { indices = [0] }
        return indices.map { index in
            let point = points[index]
            var bearing: Double?
            if points.count >= 2 {
                let next = points[(index + 1) % points.count]
                let distance = point.coordinate.meters(to: next.coordinate)
                if distance > 0.5 {
                    bearing = GeoBearing.degrees(
                        fromLat: point.lat, fromLon: point.lon, toLat: next.lat, toLon: next.lon
                    )
                }
            }
            return ParkCableStart(point: point, bearingDegrees: bearing)
        }
    }

    /// Sum of segments; loop cables (`cw` / `ccw`) include the closing segment.
    public var computedLengthM: Double? {
        guard let points, points.count >= 2 else { return nil }
        var total = 0.0
        for index in 1..<points.count {
            total += points[index - 1].coordinate.meters(to: points[index].coordinate)
        }
        if direction?.isLoop == true, points.count >= 3, let first = points.first, let last = points.last {
            total += last.coordinate.meters(to: first.coordinate)
        }
        return total
    }

    public var effectiveLengthM: Double? { lengthM ?? computedLengthM }
}

public struct ParkPrice: Codable, Equatable, Sendable {
    public var name: String
    /// Free text so currency and per-park formats stay untouched (`"€25"`).
    public var price: String
    public var note: String?

    public init(name: String, price: String, note: String? = nil) {
        self.name = name
        self.price = price
        self.note = note
    }
}

public struct ParkLink: Codable, Equatable, Sendable {
    /// Opaque label (`instagram`, `facebook`, `booking`, …).
    public var kind: String
    public var url: String

    public init(kind: String, url: String) {
        self.kind = kind
        self.url = url
    }
}

public struct ParkHistoryEntry: Codable, Equatable, Sendable {
    public var date: String
    public var description: String

    public init(date: String, description: String) {
        self.date = date
        self.description = description
    }
}

public struct Park: Codable, Equatable, Sendable, Identifiable {
    public static let currentVersion = 1

    public var version: Int
    public var id: String
    public var createdAt: String?
    public var updatedAt: String?
    public var history: [ParkHistoryEntry]?
    /// Credit for whoever wrote or last maintained this park file.
    public var author: String?
    /// On a user override of a bundled park: the bundled `updated_at` this edit was based on.
    public var basedOnUpdatedAt: String?

    public var name: String
    public var location: ParkCoordinate
    public var address: String?
    /// IANA identifier used to resolve "today" (defaults to Europe/Amsterdam).
    public var timezone: String?
    public var cables: [ParkCable]?
    public var opening: ParkOpening?
    public var phone: String?
    public var email: String?
    public var website: String?
    public var prices: [ParkPrice]?
    public var links: [ParkLink]?
    public var description: String?
    public var facilities: [String]?

    enum CodingKeys: String, CodingKey {
        case version, id, history, author, name, location, address, timezone, cables, opening
        case phone, email, website, prices, links, description, facilities
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case basedOnUpdatedAt = "based_on_updated_at"
    }

    public init(
        version: Int = Park.currentVersion,
        id: String,
        name: String,
        location: ParkCoordinate,
        address: String? = nil,
        timezone: String? = nil,
        cables: [ParkCable]? = nil,
        opening: ParkOpening? = nil,
        phone: String? = nil,
        email: String? = nil,
        website: String? = nil,
        prices: [ParkPrice]? = nil,
        links: [ParkLink]? = nil,
        description: String? = nil,
        facilities: [String]? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        history: [ParkHistoryEntry]? = nil,
        author: String? = nil,
        basedOnUpdatedAt: String? = nil
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.location = location
        self.address = address
        self.timezone = timezone
        self.cables = cables
        self.opening = opening
        self.phone = phone
        self.email = email
        self.website = website
        self.prices = prices
        self.links = links
        self.description = description
        self.facilities = facilities
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.history = history
        self.author = author
        self.basedOnUpdatedAt = basedOnUpdatedAt
    }

    public var resolvedTimeZone: TimeZone {
        timezone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Europe/Amsterdam") ?? .current
    }

    /// `updated_at` (`yyyy-MM-dd`) as a date at noon in the park's time zone.
    public var lastUpdated: Date? {
        guard let updatedAt else { return nil }
        let parts = updatedAt.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = resolvedTimeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Today's opening windows and available slots in the park's own time zone.
    public func schedule(on date: Date = Date()) -> ParkDaySchedule {
        ParkSchedule.day(for: opening, on: date, timeZone: resolvedTimeZone)
    }

    /// Whether the park is open right now (or opens later today), opens tomorrow, or is closed
    /// beyond that — accounting for the current time, not just today's date.
    public func openStatus(at date: Date = Date()) -> ParkOpenStatus {
        ParkSchedule.status(for: opening, at: date, timeZone: resolvedTimeZone)
    }
}

/// Opaque-string values for `SessionManifest.parkIdSource`.
public enum SessionParkSource {
    public static let auto = "auto"
    public static let manual = "manual"
}
