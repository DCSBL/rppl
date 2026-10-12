import Foundation

/// What the app tells the widgets about the rider: starred parks and visits per park.
/// The widget extension cannot read the app's own defaults or the session logbook, so the app
/// writes this small snapshot to the App Group.
public struct ParkWidgetSnapshot: Codable, Equatable, Sendable {
    public var favoriteIDs: [String]
    /// Park id → number of sessions near that park (`ParkListing.visitCounts`).
    public var visits: [String: Int]

    public init(favoriteIDs: [String] = [], visits: [String: Int] = [:]) {
        self.favoriteIDs = favoriteIDs
        self.visits = visits
    }

    /// The park with the most visits; ties go to the first by name. `nil` when there are no visits.
    public func mostVisited(in parks: [Park]) -> Park? {
        ranked(parks.filter { (visits[$0.id] ?? 0) > 0 }).first
    }

    /// Starred parks, most visited first (ties and never-visited parks by name), at most `limit`.
    public func topFavorites(in parks: [Park], limit: Int) -> [Park] {
        let starred = Set(favoriteIDs)
        return Array(ranked(parks.filter { starred.contains($0.id) }).prefix(max(limit, 0)))
    }

    private func ranked(_ parks: [Park]) -> [Park] {
        parks.sorted { a, b in
            let visitsA = visits[a.id] ?? 0
            let visitsB = visits[b.id] ?? 0
            if visitsA != visitsB { return visitsA > visitsB }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

public enum ParkWidgetSnapshotStore {
    static let key = "nl.dcsbl.rppl.parkWidgetSnapshot"

    public static var shared: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }

    /// Empty snapshot when nothing was written yet or the stored data is unreadable.
    public static func load(from defaults: UserDefaults = shared) -> ParkWidgetSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(ParkWidgetSnapshot.self, from: data)
        else { return ParkWidgetSnapshot() }
        return snapshot
    }

    /// Applies `change` and writes the result. Returns `true` only when the snapshot changed,
    /// so callers reload widget timelines only then.
    @discardableResult
    public static func update(
        in defaults: UserDefaults = shared,
        _ change: (inout ParkWidgetSnapshot) -> Void
    ) -> Bool {
        let old = load(from: defaults)
        var new = old
        change(&new)
        guard new != old, let data = try? JSONEncoder().encode(new) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
