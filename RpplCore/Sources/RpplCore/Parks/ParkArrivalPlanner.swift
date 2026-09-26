import Foundation

/// Pure selection/cooldown logic for park-arrival geofence notifications (opt-in, local only —
/// no server, no continuous tracking). The app layer owns `CLLocationManager` region monitoring
/// and `UNUserNotificationCenter`; this just decides *which* parks to watch and *whether* a fresh
/// arrival is worth notifying about.
public enum ParkArrivalPlanner {
    /// CoreLocation allows at most 20 monitored regions per app — always-favorites plus nearby
    /// fill-in must fit under that ceiling.
    public static let regionLimit = 20
    /// Small and centered on the park's start location: big enough to notify promptly, tight
    /// enough that passing nearby on a road doesn't count as "arrived".
    public static let regionRadiusMeters: Double = 100
    /// Once notified for a park, stay quiet about it for this long even if you leave and re-enter.
    public static let renotifyCooldown: TimeInterval = 12 * 60 * 60

    /// Favorites are always included; the rest of the budget goes to the nearest other parks to
    /// `currentLocation` (most recent fix from app open, not a live/background track).
    public static func selectMonitoredParkIDs(
        favoriteIDs: Set<String>,
        allParks: [Park],
        currentLocation: ParkCoordinate?,
        limit: Int = regionLimit
    ) -> [String] {
        guard limit > 0 else { return [] }
        let favorites = allParks.filter { favoriteIDs.contains($0.id) }
        var selected = favorites.map(\.id)
        guard selected.count < limit, let currentLocation else {
            return Array(selected.prefix(limit))
        }

        let remaining = allParks
            .filter { !favoriteIDs.contains($0.id) }
            .sorted { $0.location.meters(to: currentLocation) < $1.location.meters(to: currentLocation) }

        for park in remaining {
            if selected.count >= limit { break }
            selected.append(park.id)
        }
        return selected
    }

    public static func shouldNotify(
        lastNotifiedAt: Date?,
        now: Date = Date(),
        cooldown: TimeInterval = renotifyCooldown
    ) -> Bool {
        guard let lastNotifiedAt else { return true }
        return now.timeIntervalSince(lastNotifiedAt) >= cooldown
    }
}
