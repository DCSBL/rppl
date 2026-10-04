import Foundation

/// "Share with Rppl": turns a session into a copy that can leave the phone without saying who
/// rode or where. Pure and deterministic (apart from the fresh session id), so `swift test` covers it.
///
/// - Every GPS point moves with one `GeoRecenter` rotation, so the session sits around (0°, 0°)
///   with its geometry intact: distances, speeds and laps are the same as in the original.
/// - Personal strings become `redacted`.
/// - The copy gets a new session id. The phone refuses an import whose id is already in the
///   logbook, and a copy that kept the id would otherwise be mistaken for the original.
/// - `derived` is dropped. It carries the real map frame, track and city name; whoever opens the
///   copy rebuilds it from the shifted raw streams.
///
/// Kept on purpose, because analysis needs them: timestamps, altitude, heart rate and energy,
/// motion, weather, device model and OS version, and the shape and orientation of the track.
public enum SessionAnonymizer {
    /// Stands in for every personal string.
    public static let redacted = "REDACTEDREDACTEDREDACTED"

    public static func anonymized(
        _ package: SessionTransferPackage,
        sessionId: String = UUID().uuidString
    ) -> SessionTransferPackage {
        var result = package
        result.manifest = anonymized(package.manifest, sessionId: sessionId)
        result.locations = recentered(package.locations)
        result.derived = nil
        return result
    }

    /// `locations` moved so their centre is (0°, 0°); everything but latitude and longitude is untouched.
    public static func recentered(_ locations: [LocationSample]) -> [LocationSample] {
        let coordinates = locations.map { (latitude: $0.latitude, longitude: $0.longitude) }
        guard let recenter = GeoRecenter(centeringOn: coordinates) else { return locations }
        return locations.map { sample in
            var moved = sample
            let position = recenter.apply(latitude: sample.latitude, longitude: sample.longitude)
            moved.latitude = position.latitude
            moved.longitude = position.longitude
            return moved
        }
    }

    private static func anonymized(_ manifest: SessionManifest, sessionId: String) -> SessionManifest {
        var result = manifest
        result.sessionId = sessionId
        result.testerId = redacted
        // The park id names the place. Nil on both lets the phone that opens the copy try to match
        // a park by position, which finds none near (0°, 0°).
        result.parkId = nil
        result.parkIdSource = nil
        if var estimate = manifest.waterTemperatureEstimate {
            estimate.stationName = redacted
            estimate.providerName = redacted
            result.waterTemperatureEstimate = estimate
        }
        // Free text from the system; can hold file paths.
        if manifest.lastTransferError != nil {
            result.lastTransferError = redacted
        }
        return result
    }
}
