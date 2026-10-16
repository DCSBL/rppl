import Foundation

/// Water temperature for the single-park widget. The widget fetches it itself, so this keeps the
/// last reading and the next allowed fetch per park in the App Group: a timeline reload (opening
/// hours changing, the system refreshing) never turns into another request.
public struct ParkWidgetWaterEntry: Codable, Equatable, Sendable {
    public var reading: ParkWaterTemperature?
    public var nextFetch: Date
}

public enum ParkWidgetWater {
    /// 6 fetches a day per park at most. The sensors' own cadence is unknown, so every park gets this.
    public static let minInterval: TimeInterval = 4 * 60 * 60
    /// Added on top, so refreshes never land on the same clock times.
    public static let maxJitter: TimeInterval = 30 * 60

    private static let entriesKey = "nl.dcsbl.rppl.parkWidgetWater"
    private static let enabledKey = "nl.dcsbl.rppl.parkWidgetWaterEnabled"

    public static func nextFetch(
        after now: Date, jitter: TimeInterval = .random(in: 0...maxJitter)
    ) -> Date {
        now.addingTimeInterval(minInterval + min(max(jitter, 0), maxJitter))
    }

    /// Mirror of the app's opt-in setting, which the widget cannot read itself. Returns `true` when it changed.
    @discardableResult
    public static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = ParkWidgetSnapshotStore.shared) -> Bool {
        guard defaults.bool(forKey: enabledKey) != enabled else { return false }
        defaults.set(enabled, forKey: enabledKey)
        return true
    }

    /// The entry and the moment the widget should ask for a new timeline at the latest.
    public struct Result: Equatable, Sendable {
        public var reading: ParkWaterTemperature?
        public var nextFetch: Date?
    }

    /// The park's fresh reading, fetched at most once per `minInterval` (failures count too, so an
    /// outage is not retried in a loop). Nothing without a station or while the opt-in is off.
    public static func result(
        for park: Park,
        now: Date = Date(),
        defaults: UserDefaults = ParkWidgetSnapshotStore.shared,
        fetcher: (any ParkWaterTemperatureFetching)? = nil,
        jitter: TimeInterval = .random(in: 0...maxJitter)
    ) async -> Result {
        guard defaults.bool(forKey: enabledKey), let source = park.waterTemperature else {
            return Result(reading: nil, nextFetch: nil)
        }
        var entries = loadEntries(from: defaults)
        var entry = entries[park.id]
        // A next fetch further away than one full interval means the clock moved; fetch again.
        let isDue = entry.map { now >= $0.nextFetch || $0.nextFetch > now.addingTimeInterval(minInterval + maxJitter) } ?? true
        if isDue, let fetcher = fetcher ?? ParkWaterTemperatureFetchers.fetcher(for: source.provider) {
            let fetched = await fetcher.fetch(source)
            entry = ParkWidgetWaterEntry(reading: fetched ?? entry?.reading, nextFetch: nextFetch(after: now, jitter: jitter))
            entries[park.id] = entry
            if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: entriesKey) }
        }
        let fresh = entry?.reading.flatMap { $0.isFresh(now: now) ? $0 : nil }
        return Result(reading: fresh, nextFetch: entry?.nextFetch)
    }

    private static func loadEntries(from defaults: UserDefaults) -> [String: ParkWidgetWaterEntry] {
        defaults.data(forKey: entriesKey).flatMap { try? JSONDecoder().decode([String: ParkWidgetWaterEntry].self, from: $0) } ?? [:]
    }
}
