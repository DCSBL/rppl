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

    func reload(store: SessionFileStore) {
        loadTask?.cancel()
        isLoading = true
        loadTask = Task(priority: .userInitiated) {
            await load(store: store)
        }
    }

    private func load(store: SessionFileStore) async {
        do {
            let ids = try await runStoreIO { try store.listSessionIDs() }
            let manifests = try await runStoreIO {
                try ids.compactMap { try store.readManifest(sessionId: $0) }
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
        let bundle = try await runStoreIO {
            let detections = try store.readDetections(sessionId: manifest.sessionId)
            let locations = try store.readLocationSamples(sessionId: manifest.sessionId)
            let health = try store.readHealthSamples(sessionId: manifest.sessionId)
            let stats = SessionStatsBuilder.build(
                manifest: manifest,
                detections: detections,
                locations: locations,
                health: health
            )
            let topSpeedKmh = stats.topSpeedKmh
                ?? SessionLocationHelpers.sustainedSpeedKmh(
                    rides: stats.rides,
                    locations: locations
                )
            return (stats: stats, topSpeedKmh: topSpeedKmh, locations: locations)
        }

        let cityName = await SessionCityResolver.shared.cityName(
            sessionId: manifest.sessionId,
            locations: bundle.locations
        )

        return SessionEntry(
            manifest: manifest,
            stats: bundle.stats,
            topSpeedKmh: bundle.topSpeedKmh,
            cityName: cityName,
            highlights: []
        )
    }

    private func runStoreIO<T: Sendable>(
        _ work: @Sendable @escaping () throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: .userInitiated) {
                try work()
            }
            guard let value = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return value
        }
    }
}
