import Foundation
import Observation
import RpplCore

/// Estimated ambient water temperature per park, opt-in and provider-generic (today `"rws_nl"`,
/// `"hic_be"` and `"vmm_be"` exist; a future country adds another entry to
/// `ParkWaterTemperatureFetchers`, not a new abstraction).
///
/// Shared (`.shared`) rather than per-view so the cache and failure backoff apply across
/// park-detail navigations and geofence arrivals, matching `ParksWeatherProvider`.
@Observable
@MainActor
final class ParkWaterTemperatureProvider {
    static let shared = ParkWaterTemperatureProvider()

    private var cache: [String: (date: Date, reading: ParkWaterTemperature)] = [:]
    private var lastFailure: [String: Date] = [:]
    /// User-specified ceiling: never fetch the same station more than once per 4 hours.
    private static let maxAge: TimeInterval = 4 * 60 * 60
    /// A reading older than this is stale (some stations, e.g. wetnwild-alphen's, report
    /// infrequently or have stopped reporting) — never shown, even if the fetch itself succeeded.
    private static let maxReadingAge: TimeInterval = 48 * 60 * 60
    /// Skip re-hitting a station that just failed, so a screen revisit or geofence arrival
    /// doesn't retry an already-failing request.
    private static let failureBackoff: TimeInterval = 5 * 60
    private static let fetchTimeout: TimeInterval = 8

    private static func isFresh(_ reading: ParkWaterTemperature) -> Bool {
        Date().timeIntervalSince(reading.observedAt) <= maxReadingAge
    }

    /// `nil` whenever the feature is off, the park has no configured source, the fetch/timeout
    /// failed, or the latest reading is older than `maxReadingAge` — callers show "Not available"
    /// rather than a stale or missing reading.
    func temperature(for park: Park) async -> ParkWaterTemperature? {
        guard UserDefaults.standard.bool(forKey: AppSettingsKey.parkWaterTemperatureEnabled) else { return nil }
        guard let source = park.waterTemperature else { return nil }
        guard let fetcher = ParkWaterTemperatureFetchers.fetcher(for: source.provider) else {
            WakeLog.warning(.water, "\(park.name): unknown provider \"\(source.provider)\"")
            return nil
        }

        let key = Self.cacheKey(source)
        if let hit = cache[key], Date().timeIntervalSince(hit.date) < Self.maxAge {
            return Self.isFresh(hit.reading) ? hit.reading : nil
        }
        if let failedAt = lastFailure[key], Date().timeIntervalSince(failedAt) < Self.failureBackoff {
            return nil
        }

        do {
            guard let reading = try await Self.withTimeout(Self.fetchTimeout, { await fetcher.fetch(source) }) else {
                lastFailure[key] = Date()
                return nil
            }
            cache[key] = (Date(), reading)
            lastFailure[key] = nil
            guard Self.isFresh(reading) else {
                WakeLog.warning(
                    .water,
                    "\(park.name): latest reading from \(source.provider)/\(source.stationId) is from "
                        + "\(reading.observedAt), older than \(Int(Self.maxReadingAge / 3600))h — treating as unavailable"
                )
                return nil
            }
            return reading
        } catch {
            WakeLog.warning(
                .water,
                "\(park.name): fetch timed out after \(Int(Self.fetchTimeout))s (\(source.provider)/\(source.stationId))"
            )
            lastFailure[key] = Date()
            return nil
        }
    }

    /// Debug screen only: current settings/cache/backoff state for a park, without fetching.
    func debugSnapshot(for park: Park) -> ParkWaterTemperatureDebugStatus {
        guard let source = park.waterTemperature else {
            return ParkWaterTemperatureDebugStatus(
                source: nil, reading: nil, statusText: String(localized: "No water_temperature configured for this park.")
            )
        }
        guard ParkWaterTemperatureFetchers.fetcher(for: source.provider) != nil else {
            return ParkWaterTemperatureDebugStatus(
                source: source, reading: nil,
                statusText: String(localized: "Unknown provider \"\(source.provider)\".")
            )
        }
        let enabledPrefix = UserDefaults.standard.bool(forKey: AppSettingsKey.parkWaterTemperatureEnabled)
            ? "" : String(localized: "Setting is off (won't auto-fetch). ")
        let key = Self.cacheKey(source)
        if let failedAt = lastFailure[key], Date().timeIntervalSince(failedAt) < Self.failureBackoff {
            let retryAt = failedAt.addingTimeInterval(Self.failureBackoff)
            return ParkWaterTemperatureDebugStatus(
                source: source, reading: cache[key]?.reading,
                statusText: enabledPrefix + String(
                    localized: "Last attempt failed; backing off until \(retryAt.formatted(date: .omitted, time: .standard))."
                )
            )
        }
        if let hit = cache[key] {
            let validUntil = hit.date.addingTimeInterval(Self.maxAge)
            let staleSuffix = Self.isFresh(hit.reading)
                ? ""
                : " " + String(
                    localized: "Reading is from \(hit.reading.observedAt.formatted(date: .abbreviated, time: .standard)), older than \(Int(Self.maxReadingAge / 3600))h — shown as \"Not available\" in the app."
                )
            return ParkWaterTemperatureDebugStatus(
                source: source, reading: hit.reading,
                statusText: enabledPrefix + String(
                    localized: "Cached from \(hit.date.formatted(date: .omitted, time: .standard)), valid until \(validUntil.formatted(date: .omitted, time: .standard))."
                ) + staleSuffix
            )
        }
        return ParkWaterTemperatureDebugStatus(
            source: source, reading: nil, statusText: enabledPrefix + String(localized: "Not fetched yet.")
        )
    }

    /// Debug screen only: a real network fetch that ignores the setting toggle, cache freshness and
    /// failure backoff — so a developer can tell "the fetch itself is broken" apart from "the
    /// setting is off" or "still inside the 4h cache window". Updates the shared cache on success,
    /// same as a normal fetch would, so the park screen picks it up too.
    func debugRefresh(for park: Park) async -> ParkWaterTemperatureDebugStatus {
        guard let source = park.waterTemperature else {
            return ParkWaterTemperatureDebugStatus(
                source: nil, reading: nil, statusText: String(localized: "No water_temperature configured for this park.")
            )
        }
        guard let fetcher = ParkWaterTemperatureFetchers.fetcher(for: source.provider) else {
            return ParkWaterTemperatureDebugStatus(
                source: source, reading: nil,
                statusText: String(localized: "Unknown provider \"\(source.provider)\".")
            )
        }
        let key = Self.cacheKey(source)
        do {
            guard let reading = try await Self.withTimeout(Self.fetchTimeout, { await fetcher.fetch(source) }) else {
                lastFailure[key] = Date()
                return ParkWaterTemperatureDebugStatus(
                    source: source, reading: nil,
                    statusText: String(localized: "Fetch returned no data (station may be unreachable, or have no recent reading).")
                )
            }
            cache[key] = (Date(), reading)
            lastFailure[key] = nil
            let staleSuffix = Self.isFresh(reading)
                ? ""
                : " " + String(
                    localized: "Reading is from \(reading.observedAt.formatted(date: .abbreviated, time: .standard)), older than \(Int(Self.maxReadingAge / 3600))h — shown as \"Not available\" in the app."
                )
            return ParkWaterTemperatureDebugStatus(
                source: source, reading: reading, statusText: String(localized: "Fetched just now.") + staleSuffix
            )
        } catch {
            WakeLog.warning(
                .water,
                "\(park.name): manual \"Fetch now\" timed out after \(Int(Self.fetchTimeout))s "
                    + "(\(source.provider)/\(source.stationId)) — see the other \(source.provider) log line "
                    + "at nearly the same timestamp for the underlying network error"
            )
            lastFailure[key] = Date()
            return ParkWaterTemperatureDebugStatus(
                source: source, reading: nil,
                statusText: String(localized: "Timed out after \(Int(Self.fetchTimeout))s.")
            )
        }
    }

    private static func cacheKey(_ source: ParkWaterTemperatureSource) -> String {
        "\(source.provider)|\(source.stationId)"
    }

    private static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ work: @escaping @Sendable () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ParkWaterTemperatureTimeoutError()
            }
            guard let result = try await group.next() else {
                throw ParkWaterTemperatureTimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

private struct ParkWaterTemperatureTimeoutError: Error {}

/// Debug screen only: a park's configured source, cached reading (if any) and a human-readable
/// explanation of the current cache/backoff/settings state.
struct ParkWaterTemperatureDebugStatus: Equatable {
    var source: ParkWaterTemperatureSource?
    var reading: ParkWaterTemperature?
    var statusText: String
}
