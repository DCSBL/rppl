import Foundation

/// The hardest hit around a set end, from device motion. A set that ends in a fall shows a
/// user-acceleration spike of several g a few seconds before the detector lets go (the rider is
/// already in the water while the GPS speed is still decaying); a clean dock exit stays under ~2 g.
public enum SetImpact {
    /// At or above this the set end counts as a fall.
    public static let fallThresholdG = 4.0
    /// Detection ends a set ~7 s (up to ~25 s) after the fall, so the window reaches back.
    public static let windowBefore: TimeInterval = 10
    public static let windowAfter: TimeInterval = 3

    /// Peak |userAcceleration| (g) within the window around `end`; nil without motion there.
    public static func peakG(motion: [MotionSample], around end: Date) -> Double? {
        let start = end.addingTimeInterval(-windowBefore)
        let stop = end.addingTimeInterval(windowAfter)
        var peak: Double?
        for sample in motion where sample.timestamp >= start && sample.timestamp <= stop {
            let magnitude = (sample.userAccelX * sample.userAccelX
                + sample.userAccelY * sample.userAccelY
                + sample.userAccelZ * sample.userAccelZ).squareRoot()
            peak = max(peak ?? 0, magnitude)
        }
        return peak
    }

    /// The watch is on the wrist, so a hand or arm slapping the water reads far above what the body
    /// feels. Shown capped: a single spike past this is the wrist whipping, not a measurement.
    public static let displayCapG = 30.0

    /// `17.7 g`, or `30+ g` at the cap.
    public static func label(_ peakG: Double) -> String {
        if peakG >= displayCapG { return "\(Int(displayCapG))+ g" }
        return "\(peakG.formatted(.number.precision(.fractionLength(1)))) g"
    }

    public static func isFall(_ peakG: Double?) -> Bool {
        guard let peakG else { return false }
        return peakG >= fallThresholdG
    }
}
