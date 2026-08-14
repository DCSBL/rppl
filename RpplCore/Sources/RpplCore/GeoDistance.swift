import Foundation

/// Haversine distance and GPS step gates for ride-path meters.
public enum GeoDistance {
    private static let earthRadiusM = 6_371_000.0

    /// Great-circle distance in meters between two WGS84 points.
    public static func meters(
        fromLat: Double,
        fromLon: Double,
        toLat: Double,
        toLon: Double
    ) -> Double {
        let lat1 = fromLat * .pi / 180
        let lat2 = toLat * .pi / 180
        let dLat = (toLat - fromLat) * .pi / 180
        let dLon = (toLon - fromLon) * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusM * c
    }

    /// Dynamic max step: `min(50 m, max(15 m, |speed|×Δt + 20 m))` when speed valid; else 50 m.
    public static func maxStepMeters(deltaSeconds: TimeInterval, speedMps: Double?) -> Double {
        let hardCap = 50.0
        guard let speedMps, speedMps >= 0, deltaSeconds > 0 else {
            return hardCap
        }
        let dynamic = abs(speedMps) * deltaSeconds + 20
        return min(hardCap, max(15, dynamic))
    }

    /// Whether a GPS segment may contribute to ride distance.
    public static func acceptsStep(
        from: LocationSample,
        to: LocationSample,
        maxHorizontalAccuracyM: Double
    ) -> Bool {
        guard from.horizontalAccuracy >= 0, to.horizontalAccuracy >= 0 else { return false }
        guard from.horizontalAccuracy <= maxHorizontalAccuracyM,
              to.horizontalAccuracy <= maxHorizontalAccuracyM
        else {
            return false
        }

        let delta = to.timestamp.timeIntervalSince(from.timestamp)
        guard delta > 0 else { return false }

        let step = meters(
            fromLat: from.latitude,
            fromLon: from.longitude,
            toLat: to.latitude,
            toLon: to.longitude
        )
        let speed = to.speed ?? from.speed
        let maxStep = maxStepMeters(deltaSeconds: delta, speedMps: speed)
        return step <= maxStep
    }
}
