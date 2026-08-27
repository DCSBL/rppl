import Foundation
import Observation
import RpplCore

struct SessionEntry: Identifiable, Sendable {
    let manifest: SessionManifest
    let stats: SessionStats?
    let topSpeedKmh: Double?
    let cityName: String?
    let highlights: [SessionHighlight]

    var id: String { manifest.sessionId }
}

struct TotalsSummary: Sendable {
    var sessionCount = 0
    var totalDistanceMeters = 0.0
    var topSpeedKmh = 0.0
    var totalRuns = 0
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
                summary.totalRuns += stats.rideCount
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

            var loaded: [SessionEntry] = []
            loaded.reserveCapacity(manifests.count)

            for manifest in manifests {
                try Task.checkCancellation()
                let entry = try await buildEntry(store: store, manifest: manifest)
                loaded.append(entry)
            }

            let highlightMap = HighlightAssigner.assignSessionHighlights(
                loaded.compactMap { entry in
                    guard let stats = entry.stats else { return nil }
                    return SessionHighlightInput(
                        id: entry.manifest.sessionId,
                        totalDuration: stats.totalDuration,
                        ridingDuration: stats.ridingDuration,
                        lapCount: stats.totalLapCount
                    )
                }
            )

            entries = loaded.map { entry in
                SessionEntry(
                    manifest: entry.manifest,
                    stats: entry.stats,
                    topSpeedKmh: entry.topSpeedKmh,
                    cityName: entry.cityName,
                    highlights: highlightMap[entry.manifest.sessionId] ?? []
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

    private func buildEntry(store: SessionFileStore, manifest: SessionManifest) async throws -> SessionEntry {
        let summary = try await StoreIO.runOffMain {
            try SessionLoader.loadSummary(store: store, sessionId: manifest.sessionId)
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
            }
        } else if let cityName {
            SessionCityResolver.shared.remember(sessionId: manifest.sessionId, cityName: cityName)
        }

        return SessionEntry(
            manifest: summary.manifest,
            stats: summary.stats,
            topSpeedKmh: topSpeedKmh,
            cityName: cityName,
            highlights: []
        )
    }
}
