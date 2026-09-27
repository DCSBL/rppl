import Foundation
import Observation
import RpplCore

/// Rijkswaterstaat WaterWebServices ("OphalenLaatsteWaarnemingen") — CC0-licensed Dutch government
/// open data. Looks up the latest surface-water temperature at a station by its opaque code.
/// https://rijkswaterstaatdata.nl/waterdata/
struct RWSWaterTemperatureClient: ParkWaterTemperatureFetching {
    private static let endpoint = URL(
        string: "https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES/OphalenLaatsteWaarnemingen"
    )!

    func fetch(_ source: ParkWaterTemperatureSource) async -> ParkWaterTemperature? {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "AquoPlusWaarnemingMetadataLijst": [
                ["AquoMetadata": ["Compartiment": ["Code": "OW"], "Grootheid": ["Code": "T"]]]
            ],
            "LocatieLijst": [["Code": source.stationId]],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return Self.parse(data)
        } catch {
            return nil
        }
    }

    private static func parse(_ data: Data) -> ParkWaterTemperature? {
        guard
            let decoded = try? JSONDecoder().decode(ObservationResponse.self, from: data),
            let observation = decoded.waarnemingenLijst?.first,
            let latest = observation.metingenLijst.max(by: { $0.tijdstip < $1.tijdstip }),
            let celsius = latest.meetwaarde.waardeNumeriek,
            let observedAt = timestampFormatter.date(from: latest.tijdstip)
        else { return nil }
        return ParkWaterTemperature(
            celsius: celsius,
            observedAt: observedAt,
            stationName: observation.locatie.naam ?? observation.locatie.code,
            providerName: "Rijkswaterstaat"
        )
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private struct ObservationResponse: Decodable {
        let waarnemingenLijst: [Observation]?
        enum CodingKeys: String, CodingKey { case waarnemingenLijst = "WaarnemingenLijst" }
    }

    private struct Observation: Decodable {
        let locatie: Locatie
        let metingenLijst: [Meting]
        enum CodingKeys: String, CodingKey {
            case locatie = "Locatie"
            case metingenLijst = "MetingenLijst"
        }
    }

    private struct Locatie: Decodable {
        let code: String
        let naam: String?
        enum CodingKeys: String, CodingKey {
            case code = "Code"
            case naam = "Naam"
        }
    }

    private struct Meting: Decodable {
        let tijdstip: String
        let meetwaarde: Meetwaarde
        enum CodingKeys: String, CodingKey {
            case tijdstip = "Tijdstip"
            case meetwaarde = "Meetwaarde"
        }
    }

    private struct Meetwaarde: Decodable {
        let waardeNumeriek: Double?
        enum CodingKeys: String, CodingKey { case waardeNumeriek = "Waarde_Numeriek" }
    }
}

/// Estimated ambient water temperature per park, opt-in and provider-generic (today only
/// `"rws_nl"` exists; a future country adds another entry to `fetchers`, not a new abstraction).
///
/// Shared (`.shared`) rather than per-view so the cache and failure backoff apply across
/// park-detail navigations and geofence arrivals, matching `ParksWeatherProvider`.
@Observable
@MainActor
final class ParkWaterTemperatureProvider {
    static let shared = ParkWaterTemperatureProvider()

    private static let fetchers: [String: any ParkWaterTemperatureFetching] = [
        "rws_nl": RWSWaterTemperatureClient()
    ]

    private var cache: [String: (date: Date, reading: ParkWaterTemperature)] = [:]
    private var lastFailure: [String: Date] = [:]
    /// User-specified ceiling: never fetch the same station more than once per 4 hours.
    private static let maxAge: TimeInterval = 4 * 60 * 60
    /// Skip re-hitting a station that just failed, so a screen revisit or geofence arrival
    /// doesn't retry an already-failing request.
    private static let failureBackoff: TimeInterval = 5 * 60
    private static let fetchTimeout: TimeInterval = 8

    /// `nil` whenever the feature is off, the park has no configured source, or the fetch/timeout
    /// failed — callers simply don't show a row, no error surfaced (fail-open, like park weather).
    func temperature(for park: Park) async -> ParkWaterTemperature? {
        guard UserDefaults.standard.bool(forKey: AppSettingsKey.parkWaterTemperatureEnabled) else { return nil }
        guard let source = park.waterTemperature, let fetcher = Self.fetchers[source.provider] else { return nil }

        let key = Self.cacheKey(source)
        if let hit = cache[key], Date().timeIntervalSince(hit.date) < Self.maxAge {
            return hit.reading
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
            return reading
        } catch {
            WakeLog.debug(.ui, "park water temperature: timed out")
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
        guard Self.fetchers[source.provider] != nil else {
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
            return ParkWaterTemperatureDebugStatus(
                source: source, reading: hit.reading,
                statusText: enabledPrefix + String(
                    localized: "Cached from \(hit.date.formatted(date: .omitted, time: .standard)), valid until \(validUntil.formatted(date: .omitted, time: .standard))."
                )
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
        guard let fetcher = Self.fetchers[source.provider] else {
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
            return ParkWaterTemperatureDebugStatus(
                source: source, reading: reading, statusText: String(localized: "Fetched just now.")
            )
        } catch {
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
