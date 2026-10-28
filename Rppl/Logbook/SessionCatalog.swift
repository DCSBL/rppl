import Foundation
import Observation
import RpplCore
import WidgetKit

struct SessionEntry: Identifiable, Sendable {
    let manifest: SessionManifest
    let stats: SessionStats?
    let topSpeedKmh: Double?
    /// Filled in after the list is on screen when the session had no label yet (reverse geocode).
    var cityName: String?
    let highlights: [SessionHighlight]
    /// Track center from the derived map frame; used to match sessions to parks.
    var center: ParkCoordinate?

    var id: String { manifest.sessionId }

    var seasonSession: SeasonSession {
        SeasonSession(
            date: manifest.startedAt,
            distanceMeters: stats?.totalDistanceMeters ?? 0,
            duration: stats?.totalDuration ?? 0,
            ridingDuration: stats?.ridingDuration ?? 0,
            sets: stats?.knownSetCount,
            laps: stats?.knownLapCount,
            kilocalories: stats.flatMap { $0.totalEnergyKilocalories ?? $0.activeEnergyKilocalories },
            topSpeedKmh: topSpeedKmh,
            typicalSpeedKmh: stats?.cableSpeedKmh,
            airCelsius: manifest.weather?.temperatureCelsius,
            waterCelsius: stats?.averageWaterTemperatureCelsius ?? manifest.waterTemperatureEstimate?.celsius
        )
    }
}

private struct SessionLoadPass: Sendable {
    var entries: [SessionEntry]
    /// Sessions whose label changed to their linked park's name; the Watch mirror needs them.
    var relabeled: [String]
    var parks: [Park]
}

@Observable
@MainActor
final class SessionCatalog {
    var entries: [SessionEntry] = []
    var isLoading = false

    var season: SeasonStats {
        SeasonStats(sessions: entries.map(\.seasonSession))
    }

    private var loadTask: Task<Void, Never>?
    /// A load now outlives its list publish (geocoding runs after), so a superseded load must
    /// not touch state a newer one owns: only the newest generation writes.
    private var loadGeneration = 0

    func reload(store: SessionFileStore, acceptedSessionIDs: Set<String>? = nil) {
        loadTask?.cancel()
        isLoading = true
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask = Task(priority: .userInitiated) {
            await load(store: store, acceptedSessionIDs: acceptedSessionIDs, generation: generation)
        }
    }

    private func load(store: SessionFileStore, acceptedSessionIDs: Set<String>?, generation: Int) async {
        do {
            // One background pass for every session: this used to hop to the main actor three to
            // five times per session (summary, park link, second summary, geocode peek), so a
            // logbook of N sessions paid N round trips before anything was on screen.
            let pass = try await StoreIO.runOffMain {
                try Self.loadEntries(store: store, acceptedSessionIDs: acceptedSessionIDs)
            }
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }

            for entry in pass.entries {
                if let cityName = entry.cityName {
                    SessionCityResolver.shared.remember(sessionId: entry.manifest.sessionId, cityName: cityName)
                }
            }
            for sessionId in pass.relabeled {
                PhoneWatchViewSync.pushViewUpdate(store: store, sessionId: sessionId)
            }

            entries = Self.withHighlights(pass.entries)
            isLoading = false
            publishLastSessionToWidget()
            let settled = entries
            Task { await SessionBackfill.run(store: store, entries: settled, parks: pass.parks) }
            WakeLog.debug(.ui, "SessionCatalog loaded count=\(pass.entries.count)")

            // Reverse geocoding is a network call per session; it fills labels in after the list
            // is up instead of holding every session back behind it.
            try await geocodeMissingCities(store: store, generation: generation)
            if generation == loadGeneration { loadTask = nil }
        } catch is CancellationError {
            if generation == loadGeneration { loadTask = nil }
        } catch {
            guard generation == loadGeneration else { return }
            entries = []
            isLoading = false
            loadTask = nil
            WakeLog.error(.store, "SessionCatalog load: \(error.localizedDescription)")
        }
    }

    nonisolated private static func loadEntries(
        store: SessionFileStore,
        acceptedSessionIDs: Set<String>?
    ) throws -> SessionLoadPass {
        let parks = ParkCatalog.loadApp()
        let manifests = try store.listReadableManifests()
            .filter { acceptedSessionIDs?.contains($0.sessionId) ?? true }
            .sorted { $0.startedAt > $1.startedAt }

        var entries: [SessionEntry] = []
        entries.reserveCapacity(manifests.count)
        var relabeled: [String] = []

        for manifest in manifests {
            try Task.checkCancellation()
            let sessionId = manifest.sessionId
            var derived: DerivedSessionView
            do {
                derived = try store.ensureDerivedView(sessionId: sessionId)
            } catch {
                // One unreadable package must not empty the whole logbook.
                WakeLog.error(.store, "SessionCatalog skip \(sessionId.prefix(8))…: \(error.localizedDescription)")
                continue
            }

            // Park link: the label becomes the park's short name; unlinked sessions fall through to city geocoding.
            let center = derived.mapFrame.map { ParkCoordinate(lat: $0.centerLatitude, lon: $0.centerLongitude) }
            var current = manifest
            if let park = try? store.linkPark(sessionId: sessionId, center: center, parks: parks) {
                if park.compactName != derived.cityName {
                    derived.cityName = park.compactName
                    relabeled.append(sessionId)
                }
                if manifest.parkId != park.id {
                    current = (try? store.readManifest(sessionId: sessionId)) ?? manifest
                }
            }

            let stats = derived.stats
            entries.append(
                SessionEntry(
                    manifest: current,
                    stats: stats,
                    topSpeedKmh: stats.maxSpeedKmh ?? stats.topSpeedKmh,
                    cityName: derived.cityName,
                    highlights: [],
                    center: center
                )
            )
        }
        return SessionLoadPass(entries: entries, relabeled: relabeled, parks: parks)
    }

    private static func withHighlights(_ loaded: [SessionEntry]) -> [SessionEntry] {
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
                        lapCount: stats.knownLapCount ?? 0,
                        setCount: stats.knownSetCount
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
        return loaded.map { entry in
            SessionEntry(
                manifest: entry.manifest,
                stats: entry.stats,
                topSpeedKmh: entry.topSpeedKmh,
                cityName: entry.cityName,
                highlights: highlightMap[entry.manifest.sessionId] ?? [],
                center: entry.center
            )
        }
    }

    private func geocodeMissingCities(store: SessionFileStore, generation: Int) async throws {
        let missing = entries.filter { $0.cityName == nil }.map(\.manifest.sessionId)
        var changed = false
        for sessionId in missing {
            let peek = try await StoreIO.runOffMain {
                try store.peekLocationSamples(sessionId: sessionId)
            }
            try Task.checkCancellation()
            guard let cityName = await SessionCityResolver.shared.cityName(sessionId: sessionId, locations: peek) else {
                continue
            }
            try Task.checkCancellation()
            try? await StoreIO.runOffMain {
                try store.updateDerivedCityName(cityName, sessionId: sessionId)
            }
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            if let index = entries.firstIndex(where: { $0.manifest.sessionId == sessionId }) {
                entries[index].cityName = cityName
                changed = true
            }
            PhoneWatchViewSync.pushViewUpdate(store: store, sessionId: sessionId)
        }
        if changed { publishLastSessionToWidget() }
    }

    /// shortcut: an empty logbook never clears the widget (also guards a filtered or half-loaded first pass).
    private func publishLastSessionToWidget() {
        guard let entry = entries.first, let stats = entry.stats else { return }
        let snapshot = LastSessionWidgetSnapshot(manifest: entry.manifest, stats: stats, place: entry.cityName)
        if LastSessionWidgetStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
