import Foundation

/// Thresholds for `FallDetector` — a GPS speed cliff, not an accelerometer impact (Watch does not
/// feed raw motion into `DetectionEngine` yet; see hard constraint in `Docs/RideDetection.md`).
public struct FallDetectionThresholds: Equatable, Sendable {
    /// Only a decel starting at/above this speed (km/h) counts — dock noise near a stop should
    /// not qualify.
    public var minBaseSpeedKmh: Double
    /// Speed drop (km/h) within `maxWindow` that counts as a cliff.
    public var minDropKmh: Double
    /// Longest span a qualifying drop may take, when both ends have a GPS fix.
    public var maxWindow: TimeInterval
    /// A silence between two usable fixes at/above this counts as a GPS blackout — long enough
    /// that a real fix was missed, not just a slow tick (matches `DetectionThresholds.gapUnsureHold`,
    /// the same "GPS gone missing" bar the live engine uses).
    public var gpsBlackoutGap: TimeInterval
    /// The fix right after a blackout must be at/below this (km/h) for the blackout itself to
    /// count as a fall signature — a gap that resumes at cable speed is a flake, not a stop.
    public var gpsBlackoutResumeSpeedKmh: Double

    public init(
        minBaseSpeedKmh: Double = 15,
        minDropKmh: Double = 15,
        maxWindow: TimeInterval = 2.5,
        gpsBlackoutGap: TimeInterval = 3.0,
        gpsBlackoutResumeSpeedKmh: Double = 8
    ) {
        self.minBaseSpeedKmh = minBaseSpeedKmh
        self.minDropKmh = minDropKmh
        self.maxWindow = maxWindow
        self.gpsBlackoutGap = gpsBlackoutGap
        self.gpsBlackoutResumeSpeedKmh = gpsBlackoutResumeSpeedKmh
    }

    public static let `default` = FallDetectionThresholds()
}

/// Flags a set as a likely fall / hard letting-go from the GPS speed trace alone: cable speed
/// collapsing to near-zero within a couple of seconds, rather than a controlled glide to a stop.
///
/// Two rules, both GPS-only (no accelerometer — see thresholds doc comment):
///  1. **Cliff**: two usable fixes ≤`maxWindow` apart show speed drop ≥`minDropKmh` from
///     ≥`minBaseSpeedKmh`.
///  2. **Blackout**: cable speed (≥`minBaseSpeedKmh`) is immediately followed by a GPS silence of
///     ≥`gpsBlackoutGap`, and the fix that ends the silence is already slow
///     (≤`gpsBlackoutResumeSpeedKmh`). A real fall often knocks GPS out entirely for a couple of
///     seconds (splashdown, antenna pinned underwater) rather than merely recording a fast-to-slow
///     step, so the cliff itself is invisible in the fix stream — only the gap is.
///
/// Calibrated against real recorded sets in `RpplCore/Tests/RpplCoreTests/Fixtures/Detection` and
/// `Fixtures/FallDetection`:
///  - Every fixture set that exits by falling with continuous fixes (`good-ride-1`, `good-ride-2`,
///    `walk-spike-orig`, `walk-spike-fp1`) shows a ≥19 km/h cliff inside 2 s: 34→8, 36→9, 28→9,
///    36→5 — rule 1.
///  - A real park-day session (`2026-09-24-park-day`) contains a set that opens at cable speed,
///    holds it for ~7 s, then loses GPS for 4 s and resumes at a near-stop (20→gap→1 km/h) — no two
///    fixes ever show the cliff directly, only rule 2 catches it. The same session has five more
///    sets with plain rule-1 cliffs, and two sets with a gradual, fully-sampled decel (no gap, no
///    cliff ≥15 km/h in any ≤2.5 s span) left unflagged as controlled stops.
///  - The one fixture set that ends through a GPS gap but resumes above `gpsBlackoutResumeSpeedKmh`
///    instead of near-stopped (`walk-spike-fp2`) is left unflagged by both rules — a flake, not a
///    stop.
///
/// No fixture captures a controlled dock landing (edging to a stop) closely enough to calibrate the
/// negative case beyond the cases above, so treat this as tuned on falls, not a fully validated
/// soft-stop classifier.
public enum FallDetector {
    /// `true` when the GPS trace in `locations` shows a fall signature per the two rules above.
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
                let nextKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: next.speedMps)

                if elapsed <= thresholds.maxWindow {
                    if baseKmh - nextKmh >= thresholds.minDropKmh {
                        return true
                    }
                    continue
                }

                // Past the cliff window: only a blackout straight off base's own cable speed
                // counts (the very next usable fix, not one further out that already ruled
                // out a cliff on its own terms).
                if nextIndex == baseIndex + 1,
                   elapsed >= thresholds.gpsBlackoutGap,
                   nextKmh <= thresholds.gpsBlackoutResumeSpeedKmh {
                    return true
                }
                break
            }
        }
        return false
    }
}
