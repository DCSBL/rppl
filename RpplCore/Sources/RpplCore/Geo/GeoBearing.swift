import Foundation

/// Great-circle bearing for map direction chevrons and heading readouts.
public enum GeoBearing {
    /// Initial bearing in degrees clockwise from true north (0…360).
    public static func degrees(
        fromLat: Double,
        fromLon: Double,
        toLat: Double,
        toLon: Double
    ) -> Double {
        let lat1 = fromLat * .pi / 180
        let lat2 = toLat * .pi / 180
        let dLon = (toLon - fromLon) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Bearing between two samples, or nil when they sit on the same point.
    public static func degrees(from: LocationSample, to: LocationSample) -> Double? {
        let step = GeoDistance.meters(
            fromLat: from.latitude,
            fromLon: from.longitude,
            toLat: to.latitude,
            toLon: to.longitude
        )
        guard step > 0.5 else { return nil }
        return degrees(
            fromLat: from.latitude,
            fromLon: from.longitude,
            toLat: to.latitude,
            toLon: to.longitude
        )
    }
}
