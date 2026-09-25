import Foundation
import Yams

public enum ParkCatalogError: Error, Equatable {
    case invalidYAML(String)
}

/// Loads park YAML files: bundled seeds plus optional user files (user file wins on the same `id`).
public enum ParkCatalog {
    public static func parse(yaml: String, fallbackId: String) throws -> Park {
        do {
            var park = try YAMLDecoder().decode(Park.self, from: yaml)
            if park.id.isEmpty { park.id = fallbackId }
            return park
        } catch {
            throw ParkCatalogError.invalidYAML(error.localizedDescription)
        }
    }

    public static func encode(_ park: Park) throws -> String {
        try YAMLEncoder().encode(park)
    }

    public static func loadBundled() -> [Park] {
        let urls = (Bundle.module.urls(forResourcesWithExtension: "yaml", subdirectory: "Parks") ?? [])
            + (Bundle.module.urls(forResourcesWithExtension: "yaml", subdirectory: nil) ?? [])
        return loadFiles(urls)
    }

    public static func loadDirectory(_ directory: URL) -> [Park] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return loadFiles(urls.filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) })
    }

    public static func load(userRoot: URL?) -> [Park] {
        var byId: [String: Park] = [:]
        for park in loadBundled() { byId[park.id] = park }
        if let userRoot {
            for park in loadDirectory(userRoot) { byId[park.id] = park }
        }
        return byId.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - User parks (custom + edited overrides)

    /// Every park with where it came from. A user file wins over a bundled park with the same `id`.
    public static func loadWithOrigin(userRoot: URL?) -> [ParkEntry] {
        let bundled = Dictionary(loadBundled().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [String: ParkEntry] = bundled.mapValues { ParkEntry(park: $0, origin: .bundled) }
        if let userRoot {
            for park in loadDirectory(userRoot) {
                guard let base = bundled[park.id] else {
                    entries[park.id] = ParkEntry(park: park, origin: .custom)
                    continue
                }
                let newer = (base.updatedAt ?? "") > (park.basedOnUpdatedAt ?? "")
                entries[park.id] = ParkEntry(park: park, origin: .edited, bundledPark: base, hasNewerBundled: newer)
            }
        }
        return entries.values.sorted { $0.park.name.localizedCaseInsensitiveCompare($1.park.name) == .orderedAscending }
    }

    /// Writes `<id>.yaml` into `userRoot`, stamping `updated_at`, a history line and (for overrides) `based_on_updated_at`.
    @discardableResult
    public static func save(
        _ park: Park,
        to userRoot: URL,
        bundledBase: Park? = nil,
        now: Date = Date()
    ) throws -> Park {
        var park = park
        let day = dayString(now)
        park.updatedAt = day
        if park.createdAt == nil { park.createdAt = day }
        park.basedOnUpdatedAt = bundledBase.map { $0.updatedAt ?? "" }
        var history = park.history ?? []
        history.append(ParkHistoryEntry(date: day, description: bundledBase == nil ? "Edited in app" : "Edited in app (override)"))
        park.history = history
        try FileManager.default.createDirectory(at: userRoot, withIntermediateDirectories: true)
        try removeUserFiles(id: park.id, in: userRoot)
        try encode(park).write(to: userRoot.appendingPathComponent("\(park.id).yaml"), atomically: true, encoding: .utf8)
        return park
    }

    /// Deletes a custom park, or removes an override so the bundled park shows again.
    public static func deleteUserPark(id: String, userRoot: URL) throws {
        try removeUserFiles(id: id, in: userRoot)
    }

    /// Keeps the user's override but marks the current bundled version as seen.
    public static func keepMine(_ entry: ParkEntry, userRoot: URL) throws {
        guard let base = entry.bundledPark else { return }
        var park = entry.park
        park.basedOnUpdatedAt = base.updatedAt
        try removeUserFiles(id: park.id, in: userRoot)
        try encode(park).write(to: userRoot.appendingPathComponent("\(park.id).yaml"), atomically: true, encoding: .utf8)
    }

    /// Lowercase ASCII slug from a park name, made unique against `existing`.
    public static func slug(from name: String, existing: Set<String> = []) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        var out = ""
        var lastDash = true
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        if out.isEmpty { out = "park" }
        var candidate = out
        var n = 2
        while existing.contains(candidate) {
            candidate = "\(out)-\(n)"
            n += 1
        }
        return candidate
    }

    private static func removeUserFiles(id: String, in directory: URL) throws {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where ["yaml", "yml"].contains(url.pathExtension.lowercased()) {
            let text = try? String(contentsOf: url, encoding: .utf8)
            let fileId = text.flatMap { try? parse(yaml: $0, fallbackId: url.deletingPathExtension().lastPathComponent).id }
            if fileId == id { try FileManager.default.removeItem(at: url) }
        }
    }

    private static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    private static func loadFiles(_ urls: [URL]) -> [Park] {
        var seen = Set<String>()
        var parks: [Park] = []
        for url in urls.sorted(by: { $0.path < $1.path }) where seen.insert(url.lastPathComponent).inserted {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                parks.append(try parse(yaml: text, fallbackId: url.deletingPathExtension().lastPathComponent))
            } catch {
                WakeLog.error(.store, "park yaml \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return parks
    }
}

public enum ParkOrigin: String, Sendable {
    case bundled
    /// Only exists as a user file.
    case custom
    /// A user file overriding a bundled park.
    case edited
}

public struct ParkEntry: Equatable, Sendable, Identifiable {
    public var park: Park
    public var origin: ParkOrigin
    /// The bundled version when `origin == .edited`.
    public var bundledPark: Park?
    /// The app ships a newer version than the one the override was based on.
    public var hasNewerBundled: Bool

    public var id: String { park.id }

    public init(park: Park, origin: ParkOrigin, bundledPark: Park? = nil, hasNewerBundled: Bool = false) {
        self.park = park
        self.origin = origin
        self.bundledPark = bundledPark
        self.hasNewerBundled = hasNewerBundled
    }
}

public enum ParkListSort: String, Sendable, CaseIterable {
    case distance
    case visits
}

/// Parks list/map filters. Every field cleared (`nil` / empty / `false`) means "show everything",
/// including parks that are closed — the "Open" filter only narrows the list once a date is picked.
public struct ParkFilters: Equatable, Sendable {
    public var openOnDate: Date?
    public var cableDirections: Set<ParkCableDirection>
    public var favoritesOnly: Bool

    public init(
        openOnDate: Date? = nil,
        cableDirections: Set<ParkCableDirection> = [],
        favoritesOnly: Bool = false
    ) {
        self.openOnDate = openOnDate
        self.cableDirections = cableDirections
        self.favoritesOnly = favoritesOnly
    }

    public var isActive: Bool {
        openOnDate != nil || !cableDirections.isEmpty || favoritesOnly
    }
}

public enum ParkListing {
    /// A session counts as a visit when its center is this close to the park pin or a traced cable point.
    public static let visitRadiusMeters = 750.0

    /// Closest park whose pin or traced cable is within `radiusMeters` of `coordinate`.
    public static func nearest(
        to coordinate: ParkCoordinate,
        in parks: [Park],
        radiusMeters: Double = visitRadiusMeters
    ) -> Park? {
        parks
            .map { park -> (park: Park, distance: Double) in
                let anchors = [park.location] + (park.cables ?? []).flatMap { ($0.points ?? []).map(\.coordinate) }
                return (park, anchors.map { $0.meters(to: coordinate) }.min() ?? .infinity)
            }
            .filter { $0.distance <= radiusMeters }
            .min { $0.distance < $1.distance }?
            .park
    }

    public static func visitCounts(
        parks: [Park],
        sessionCenters: [ParkCoordinate],
        radiusMeters: Double = visitRadiusMeters
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for park in parks {
            let anchors = [park.location] + (park.cables ?? []).flatMap { ($0.points ?? []).map(\.coordinate) }
            let visits = sessionCenters.filter { center in
                anchors.contains { $0.meters(to: center) <= radiusMeters }
            }.count
            if visits > 0 { counts[park.id] = visits }
        }
        return counts
    }

    /// Applies the Open/Cable/Favourites filters. "Open" checks the picked date's own schedule
    /// (not the current time of day), so a future date works the same as today.
    public static func filtered(
        _ parks: [Park],
        favorites: Set<String>,
        filters: ParkFilters
    ) -> [Park] {
        guard filters.isActive else { return parks }
        return parks.filter { park in
            if filters.favoritesOnly, !favorites.contains(park.id) { return false }
            if !filters.cableDirections.isEmpty {
                let directions = Set((park.cables ?? []).compactMap(\.direction))
                if directions.isDisjoint(with: filters.cableDirections) { return false }
            }
            if let openOnDate = filters.openOnDate {
                let schedule = ParkSchedule.day(for: park.opening, on: openOnDate, timeZone: park.resolvedTimeZone)
                if !schedule.isOpen { return false }
            }
            return true
        }
    }

    /// Favorites first, then by the chosen sort. Distance sort without a fix falls back to name.
    public static func sorted(
        _ parks: [Park],
        favorites: Set<String>,
        visits: [String: Int],
        userLocation: ParkCoordinate?,
        sort: ParkListSort
    ) -> [Park] {
        func distance(_ park: Park) -> Double {
            userLocation.map { park.location.meters(to: $0) } ?? .infinity
        }
        func byName(_ a: Park, _ b: Park) -> Bool {
            a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return parks.sorted { a, b in
            let favA = favorites.contains(a.id)
            let favB = favorites.contains(b.id)
            if favA != favB { return favA }
            if sort == .visits {
                let visitsA = visits[a.id] ?? 0
                let visitsB = visits[b.id] ?? 0
                if visitsA != visitsB { return visitsA > visitsB }
            }
            let distA = distance(a)
            let distB = distance(b)
            if distA != distB { return distA < distB }
            return byName(a, b)
        }
    }
}
