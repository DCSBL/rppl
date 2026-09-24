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

public enum ParkListSort: String, Sendable, CaseIterable {
    case distance
    case visits
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
