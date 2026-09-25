import Foundation

/// Thresholds for `FallDetector` — a GPS speed cliff, not an accelerometer impact (Watch does not
/// feed raw motion into `DetectionEngine` yet; see hard constraint in `Docs/RideDetection.md`).
public struct FallDetectionThresholds: Equatable, Sendable {
    /// Only a decel starting at/above this speed (km/h) counts — dock noise near a stop should
    /// not qualify.
    public var minBaseSpeedKmh: Double
    /// Speed drop (km/h) within `maxWindow` that counts as a cliff.
    public var minDropKmh: Double
    /// Longest span a qualifying drop may take.
    public var maxWindow: TimeInterval

    public init(
        minBaseSpeedKmh: Double = 15,
        minDropKmh: Double = 15,
        maxWindow: TimeInterval = 2.5
    ) {
        self.minBaseSpeedKmh = minBaseSpeedKmh
        self.minDropKmh = minDropKmh
        self.maxWindow = maxWindow
    }

    public static let `default` = FallDetectionThresholds()
}

/// Flags a set as a likely fall / hard letting-go from the GPS speed trace alone: cable speed
/// collapsing to near-zero within a couple of seconds, rather than a controlled glide to a stop.
///
/// Calibrated against real recorded sets in `RpplCore/Tests/RpplCoreTests/Fixtures/Detection`:
/// every fixture set that exits by falling (`good-ride-1`, `good-ride-2`, `walk-spike-orig`,
/// `walk-spike-fp1`) shows a ≥19 km/h drop inside 2 s: 34→8, 36→9, 28→9, 36→5. The one fixture set
/// that ends through a GPS gap instead of a visible cliff (`walk-spike-fp2`) shows no such drop —
/// its speed just stops updating rather than collapsing, so it is left `unsure`/`unknown` here.
/// No fixture captures a controlled dock landing (edging to a stop) to calibrate the negative case
/// beyond that, so treat this as a first pass tuned on falls, not a validated soft-stop detector.
public enum FallDetector {
    /// `true` when GPS speed inside `locations` collapses by `minDropKmh` within `maxWindow`,
    /// starting from at least `minBaseSpeedKmh` — a fall or hard letting-go, not a gradual stop.
    public static func detectsFall(
        in locations: [LocationSample],
        thresholds: FallDetectionThresholds = .default,
        gpsThresholds: DetectionThresholds = .default
    ) -> Bool {
        let usable = LocationSpeedStats.usableSpeeds(from: locations, thresholds: gpsThresholds)
        guard usable.count >= 2 else { return false }

        for baseIndex in 0..<usable.count {
            let base = usable[baseIndex]
            let baseKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: base.speedMps)
            guard baseKmh >= thresholds.minBaseSpeedKmh else { continue }

            for nextIndex in (baseIndex + 1)..<usable.count {
                let next = usable[nextIndex]
                let elapsed = next.timestamp.timeIntervalSince(base.timestamp)
                guard elapsed > 0 else { continue }
                guard elapsed <= thresholds.maxWindow else { break }
                let nextKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: next.speedMps)
                if baseKmh - nextKmh >= thresholds.minDropKmh {
                    return true
                }
            }
        }
        return false
    }
}
