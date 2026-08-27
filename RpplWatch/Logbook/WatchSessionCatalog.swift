import Foundation
import Observation
import RpplCore

struct WatchSessionEntry: Identifiable, Equatable, Sendable {
    let manifest: SessionManifest
    let stats: SessionStats
    let cityName: String?
    let mapFrame: MapTrackFrame?
    let isSynced: Bool

    var id: String { manifest.sessionId }
}

@Observable
@MainActor
final class WatchSessionCatalog {
    var entries: [WatchSessionEntry] = []
    var isLoading = false

    private var loadTask: Task<Void, Never>?
    private let store: SessionFileStore

    init(store: SessionFileStore = SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)) {
        self.store = store
    }

    func reload() {
        loadTask?.cancel()
        isLoading = true
        loadTask = Task(priority: .userInitiated) {
            await load()
        }
    }

    private func load() async {
        do {
            let loaded = try await StoreIO.runOffMain { try Self.loadEntries(store: self.store) }
            try Task.checkCancellation()
            entries = loaded
            isLoading = false
            loadTask = nil
            WakeLog.debug(.ui, "WatchSessionCatalog loaded count=\(loaded.count)")
        } catch is CancellationError {
            loadTask = nil
        } catch {
            entries = []
            isLoading = false
            loadTask = nil
            WakeLog.error(.store, "WatchSessionCatalog load: \(error.localizedDescription)")
        }
    }

    nonisolated private static func loadEntries(store: SessionFileStore) throws -> [WatchSessionEntry] {
        let manifests = try store.listSessionIDs()
            .compactMap { try? store.readManifest(sessionId: $0) }
            .filter { $0.transferState != .recording }
            .sorted { $0.startedAt > $1.startedAt }

        var entries: [WatchSessionEntry] = []
        entries.reserveCapacity(manifests.count)

        for manifest in manifests {
            guard let derived = try store.readDerivedView(sessionId: manifest.sessionId) else {
                continue
            }
            entries.append(
                WatchSessionEntry(
                    manifest: manifest,
                    stats: derived.stats,
                    cityName: derived.cityName,
                    mapFrame: derived.mapFrame,
                    isSynced: manifest.transferState == .acknowledged
                )
            )
        }
        return entries
    }
}
