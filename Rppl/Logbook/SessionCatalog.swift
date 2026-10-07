import Foundation
import Observation
import RpplCore

struct SessionEntry: Identifiable, Sendable {
    let manifest: SessionManifest
    let stats: SessionStats?
    let topSpeedKmh: Double?
    let cityName: String?
    let highlights: [SessionHighlight]
    /// Track center from the derived map frame; used to match sessions to parks.
    var center: ParkCoordinate?

    var id: String { manifest.sessionId }
}

struct TotalsSummary: Sendable {
    var sessionCount = 0
    var totalDistanceMeters = 0.0
    var topSpeedKmh = 0.0
    var totalSets = 0
    var totalLaps = 0
}

@Observable
@MainActor
final class SessionCatalog {
    var entries: [SessionEntry] = []
    var isLoading = false

    var totals: TotalsSummary {
        var summary = TotalsSummary()
        summary.sessionCount = entries.count
        for entry in entries {
            if let stats = entry.stats {
                summary.totalDistanceMeters += stats.totalDistanceMeters
                summary.totalSets += stats.setCount
                summary.totalLaps += stats.totalLapCount
            }
            if let speed = entry.topSpeedKmh {
                summary.topSpeedKmh = max(summary.topSpeedKmh, speed)
            }
        }
        return summary
    }

    private var loadTask: Task<Void, Never>?

    func reload(store: SessionFileStore, acceptedSessionIDs: Set<String>? = nil) {
        loadTask?.cancel()
        isLoading = true
        loadTask = Task(priority: .userInitiated) {
            await load(store: store, acceptedSessionIDs: acceptedSessionIDs)
        }
    }

    private func load(store: SessionFileStore, acceptedSessionIDs: Set<String>?) async {
        do {
            let ids = try await StoreIO.runOffMain { try store.listSessionIDs() }
            let filteredIDs: [String]
            if let acceptedSessionIDs {
                filteredIDs = ids.filter { acceptedSessionIDs.contains($0) }
            } else {
                filteredIDs = ids
            }
            let manifests = try await StoreIO.runOffMain {
                try filteredIDs.compactMap { try store.readManifest(sessionId: $0) }
                    .sorted { $0.startedAt > $1.startedAt }
            }

            let parks = ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot)
            var loaded: [SessionEntry] = []
            loaded.reserveCapacity(manifests.count)

            for manifest in manifests {
                try Task.checkCancellation()
                let entry = try await buildEntry(store: store, manifest: manifest, parks: parks)
                loaded.append(entry)
            }

            let highlightMap = HighlightAssigner.assignSessionHighlights(
                loaded.compactMap { entry in
                    guard let stats = entry.stats else { return nil }
                    let manifest = entry.manifest
                    if manifest.manual != nil {
                        // Typed-in sessions only compete for "most sets" and "most laps".
                        return SessionHighlightInput(
                            id: manifest.sessionId,
                            totalDuration: 0,
                            ridingDuration: 0,
                            lapCount: stats.totalLapCount,
                            setCount: stats.setCount
                        )
                    }
                    let minutes = SessionHighlightInput.minutesOfDay(
                        start: stats.startedAt,
                        end: stats.endedAt,
                        calendar: .current
                    )
                    return SessionHighlightInput(
                        id: manifest.sessionId,
                        totalDuration: stats.totalDuration,
                        ridingDuration: stats.ridingDuration,
                        lapCount: stats.totalLapCount,
                        ridingInactiveRatio: stats.ridingInactiveRatio,
                        totalEnergyKilocalories: stats.totalEnergyKilocalories ?? stats.activeEnergyKilocalories,
                        longestSetDistanceMeters: stats.sets.map(\.distanceMeters).max(),
                        setCount: stats.setCount,
                        totalDistanceMeters: stats.totalDistanceMeters,
                        topSpeedKmh: entry.topSpeedKmh,
                        airTemperatureCelsius: manifest.weather?.temperatureCelsius,
                        windSpeedKmh: manifest.weather?.windSpeedKmh,
                        precipitationMmPerHour: manifest.weather?.precipitationMmPerHour,
                        waterTemperatureCelsius: stats.averageWaterTemperatureCelsius
                            ?? manifest.waterTemperatureEstimate?.celsius,
                        startMinuteOfDay: minutes.start,
                        endMinuteOfDay: minutes.end
                    )
                }
            )

            entries = loaded.map { entry in
                SessionEntry(
                    manifest: entry.manifest,
                    stats: entry.stats,
                    topSpeedKmh: entry.topSpeedKmh,
                    cityName: entry.cityName,
                    highlights: highlightMap[entry.manifest.sessionId] ?? [],
                    center: entry.center
                )
            }
            isLoading = false
            loadTask = nil
            WakeLog.debug(.ui, "SessionCatalog loaded count=\(loaded.count)")
        } catch is CancellationError {
            loadTask = nil
        } catch {
            entries = []
            isLoading = false
            loadTask = nil
            WakeLog.error(.store, "SessionCatalog load: \(error.localizedDescription)")
        }
    }

    private func buildEntry(
        store: SessionFileStore,
        manifest: SessionManifest,
        parks: [Park]
    ) async throws -> SessionEntry {
        var summary = try await StoreIO.runOffMain {
            try SessionLoader.loadSummary(store: store, sessionId: manifest.sessionId)
        }

        // Park link: the label becomes the park name; unlinked sessions fall through to city geocoding.
        let center = summary.mapFrame.map { ParkCoordinate(lat: $0.centerLatitude, lon: $0.centerLongitude) }
        let park = try? await StoreIO.runOffMain {
            try store.linkPark(sessionId: manifest.sessionId, center: center, parks: parks)
        }
        if let park, park.name != summary.cityName {
            summary = try await StoreIO.runOffMain {
                try SessionLoader.loadSummary(store: store, sessionId: manifest.sessionId)
            }
            PhoneWatchViewSync.pushViewUpdate(store: store, sessionId: manifest.sessionId)
        }

        let topSpeedKmh = summary.stats.maxSpeedKmh ?? summary.stats.topSpeedKmh

        var cityName = summary.cityName
        if cityName == nil {
            let peek = try await StoreIO.runOffMain {
                try store.peekLocationSamples(sessionId: manifest.sessionId)
            }
            cityName = await SessionCityResolver.shared.cityName(
                sessionId: manifest.sessionId,
                locations: peek
            )
            if let cityName {
                try? await StoreIO.runOffMain {
                    try store.updateDerivedCityName(cityName, sessionId: manifest.sessionId)
                }
                PhoneWatchViewSync.pushViewUpdate(store: store, sessionId: manifest.sessionId)
            }
        } else if let cityName {
            SessionCityResolver.shared.remember(sessionId: manifest.sessionId, cityName: cityName)
        }

        return SessionEntry(
            manifest: summary.manifest,
            stats: summary.stats,
            topSpeedKmh: topSpeedKmh,
            cityName: cityName,
            highlights: [],
            center: summary.mapFrame.map {
                ParkCoordinate(lat: $0.centerLatitude, lon: $0.centerLongitude)
            }
        )
    }
}
