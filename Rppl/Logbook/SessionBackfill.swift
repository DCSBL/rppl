import Foundation
import RpplCore

/// One-time catch-up for sessions that never got air weather or a water estimate (older sessions,
/// sessions logged before the water setting was on). Each session gets one attempt per kind, ever:
/// the attempt is remembered whether it found data or not, so WeatherKit is never hit twice for it.
@MainActor
enum SessionBackfill {
    private static let weatherKey = "rppl.backfill.weatherAttempted"
    private static let waterKey = "rppl.backfill.waterAttempted"
    private static var isRunning = false

    static func run(store: SessionFileStore, entries: [SessionEntry], parks: [Park]) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var weatherDone = Set(UserDefaults.standard.stringArray(forKey: weatherKey) ?? [])
        var waterDone = Set(UserDefaults.standard.stringArray(forKey: waterKey) ?? [])
        var changed = false

        for entry in entries {
            let manifest = entry.manifest
            let id = manifest.sessionId
            guard let end = manifest.endedAt, end < .now else { continue }
            let park = manifest.parkId.flatMap { id in parks.first { $0.id == id } }

            let spot = manifest.manual?.location ?? entry.center ?? park?.location
            if manifest.weather == nil, !weatherDone.contains(id), let spot {
                weatherDone.insert(id)
                UserDefaults.standard.set(Array(weatherDone), forKey: weatherKey)
                if let weather = await ManualSessionWeather.fetch(at: spot, from: manifest.startedAt, to: end) {
                    try? await StoreIO.runOffMain { try store.updateWeather(weather, sessionId: id) }
                    changed = true
                }
            }

            let waterEnabled = UserDefaults.standard.bool(forKey: AppSettingsKey.parkWaterTemperatureEnabled)
            if let stats = entry.stats, !waterDone.contains(id), park?.waterTemperature != nil, waterEnabled,
               stats.averageWaterTemperatureCelsius == nil, manifest.waterTemperatureEstimate == nil {
                waterDone.insert(id)
                UserDefaults.standard.set(Array(waterDone), forKey: waterKey)
                if await SessionWaterEstimate.fetchIfNeeded(store: store, manifest: manifest, stats: stats, park: park) != nil {
                    changed = true
                }
            }
        }
        if changed { PhoneConnectivityService.shared.bumpSessionsRevision() }
    }
}
