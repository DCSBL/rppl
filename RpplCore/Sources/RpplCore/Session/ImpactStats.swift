import Foundation

/// Peak g-force ("impact") per set, from the Watch's gravity-free `userAcceleration` (already in g).
public enum ImpactStats {
    /// A set peak at or above this is a notably hard hit (wipeout-grade). Wrist, 25 Hz, gravity
    /// removed. Real session (9 sets): every set ends in a 4–10 g peak (fall or stop), so 10 g
    /// only marks the clearly harder hits (12 g, 24 g); dock and walking peaks stay under 5 g.
    /// Calibrated on one session; revisit with more data.
    public static let highImpactG = 10.0

    /// Magnitudes above this are sensor glitches or the watch banging on the dock, not a rider.
    public static let implausibleAboveG = 50.0

    /// Largest plausible `|userAcceleration|` (g) with a timestamp in `start...end`; nil when
    /// there is none.
    public static func peakG(in samples: [MotionSample], from start: Date, to end: Date) -> Double? {
        var peak: Double?
        for sample in samples where sample.timestamp >= start && sample.timestamp <= end {
            let magnitude = (sample.userAccelX * sample.userAccelX
                + sample.userAccelY * sample.userAccelY
                + sample.userAccelZ * sample.userAccelZ).squareRoot()
            guard magnitude.isFinite, magnitude <= implausibleAboveG else { continue }
            peak = max(peak ?? magnitude, magnitude)
        }
        return peak
    }

    public static func isHighImpact(_ peakG: Double?) -> Bool {
        (peakG ?? 0) >= highImpactG
    }
}
