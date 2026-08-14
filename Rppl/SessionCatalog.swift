import Foundation
import Observation
import RpplCore

struct SessionEntry: Identifiable, Sendable {
    let manifest: SessionManifest
    let stats: SessionStats?
    let topSpeedKmh: Double?

    var id: String { manifest.sessionId }
}

@Observable
@MainActor
final class SessionCatalog {
    var entries: [SessionEntry] = []
    var isLoading = false

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

            entries = loaded
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
        try await runStoreIO {
            let detections = try store.readDetections(sessionId: manifest.sessionId)
            let locations = try store.readLocationSamples(sessionId: manifest.sessionId)
            let health = try store.readHealthSamples(sessionId: manifest.sessionId)
            let stats = SessionStatsBuilder.build(
                manifest: manifest,
                detections: detections,
                locations: locations,
                health: health
            )
            let topSpeedKmh = SessionLocationHelpers.peakSpeedKmh(from: locations)
            return SessionEntry(manifest: manifest, stats: stats, topSpeedKmh: topSpeedKmh)
        }
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
