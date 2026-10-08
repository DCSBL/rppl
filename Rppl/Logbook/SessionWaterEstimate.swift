import RpplCore
import SwiftUI

/// Station water temperature for a past session that has none measured (manual, or tracked without a
/// submersion sensor): the nearest official reading within `ParkWaterTemperature.maxHistoryOffset` of
/// the session, stored as `manifest.waterTemperatureEstimate`. Opt-in like the park screen's reading,
/// best effort: a miss just means no tile. One attempt per session per launch.
@MainActor
enum SessionWaterEstimate {
    private static var attempted: Set<String> = []

    /// Returns the stored estimate when one was fetched, `nil` otherwise.
    static func fetchIfNeeded(
        store: SessionFileStore, manifest: SessionManifest, stats: SessionStats, park: Park?
    ) async -> ParkWaterTemperature? {
        guard
            UserDefaults.standard.bool(forKey: AppSettingsKey.parkWaterTemperatureEnabled),
            stats.averageWaterTemperatureCelsius == nil, manifest.waterTemperatureEstimate == nil,
            let end = manifest.endedAt, end < .now,
            let source = park?.waterTemperature,
            let fetcher = ParkWaterTemperatureFetchers.fetcher(for: source.provider),
            attempted.insert(manifest.sessionId).inserted
        else { return nil }
        let start = manifest.startedAt
        let reading = try? await Deadline.run(8, label: "pastWaterEstimate") {
            await fetcher.fetchHistorical(source, from: start, to: end)
        }
        guard let reading = reading ?? nil else { return nil }
        let sessionId = manifest.sessionId
        try? await StoreIO.runOffMain { try store.updateWaterTemperatureEstimate(reading, sessionId: sessionId) }
        return reading
    }
}
