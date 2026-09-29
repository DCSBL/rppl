import CoreLocation
import Foundation
import RpplCore

extension WatchSessionController {
    private static let waterEstimateTimeout: TimeInterval = 8

    func resetWaterEstimate() {
        waterEstimateFetchTask?.cancel()
        waterEstimateFetchTask = nil
        waterEstimate = nil
        waterEstimateAttempted = false
    }

    /// Once per session, from the first usable GPS fix: look up the nearest park's station reading so
    /// watches without a submersion sensor (and Ultras before first submersion) still show a water
    /// temperature. Fails open — no park, no source or no network just means no estimate.
    func requestWaterEstimateIfNeeded(from location: CLLocation) {
        guard !waterEstimateAttempted else { return }
        guard AirWeatherKit.isUsable(location) else { return }
        waterEstimateAttempted = true
        let coordinate = ParkCoordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        waterEstimateFetchTask = Task { [weak self] in
            let estimate = await Self.fetchWaterEstimate(near: coordinate)
            guard let self, !Task.isCancelled else { return }
            self.waterEstimateFetchTask = nil
            guard let estimate else { return }
            self.waterEstimate = estimate
            self.persistWaterEstimate(estimate)
            WakeLog.debug(.water, String(format: "water estimate %.1f C (%@)", estimate.celsius, estimate.stationName))
        }
    }

    private func persistWaterEstimate(_ estimate: ParkWaterTemperature) {
        guard let store, var current = manifest else { return }
        current.waterTemperatureEstimate = estimate
        manifest = current
        do {
            try store.updateWaterTemperatureEstimate(estimate, sessionId: current.sessionId)
        } catch {
            WakeLog.error(.store, "water estimate manifest: \(error.localizedDescription)")
        }
    }

    private nonisolated static func fetchWaterEstimate(near coordinate: ParkCoordinate) async -> ParkWaterTemperature? {
        guard
            let park = ParkListing.nearest(to: coordinate, in: ParkCatalog.loadBundled()),
            let source = park.waterTemperature,
            let fetcher = ParkWaterTemperatureFetchers.fetcher(for: source.provider)
        else { return nil }
        let reading = await withTaskGroup(of: ParkWaterTemperature?.self) { group in
            group.addTask { await fetcher.fetch(source) }
            group.addTask {
                try? await Task.sleep(for: .seconds(waterEstimateTimeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let reading, reading.isFresh() else { return nil }
        return reading
    }
}
