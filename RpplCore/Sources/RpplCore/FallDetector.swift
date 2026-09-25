import Foundation

/// Thresholds for `FallDetector`.
public struct FallDetectionThresholds: Equatable, Sendable {
    /// A set shorter than this counts as cut short. A full untroubled lap at a cable park runs
    /// several minutes; a set well under that is a sign something ended it early.
    public var maxCutShortDuration: TimeInterval

    public init(maxCutShortDuration: TimeInterval = 150) {
        self.maxCutShortDuration = maxCutShortDuration
    }

    public static let `default` = FallDetectionThresholds()
}

/// Flags a set as a likely fall / wipeout / failed attempt: not from the shape of its GPS speed
/// trace, but from being conspicuously shorter than a normal full run.
///
/// An earlier version of this flagged a GPS speed cliff (cable speed collapsing to near-zero
/// within a couple of seconds). That turned out to be the wrong signal: letting go of a cable
/// running ~30 km/h produces a sharp deceleration whether the dismount was clean or not, so it
/// flagged most ordinary set endings as falls.
///
/// Calibrated against a real, hand-labeled park-day session (`Fixtures/FallDetection/2026-09-24-park-day.json`,
/// 10 sets):
///  - The 3 sets that really did end early (a failed start at 17 s, a failed kicker attempt at
///    9 s, and another failed kicker attempt at 110 s — the last with no GPS speed cliff at all,
///    just a long steady cruise cut short) all sit well under 2 minutes.
///  - The 6 sets that ran a normal full lap (212–303 s) and simply ended — some after landing
///    real tricks — all show the exact same kind of sharp GPS speed cliff at the end, because
///    that is just what letting go of the cable looks like. None of them belong here.
///  - One set (122 s, a failed trick with a gradual, gentle-looking ending) sits in between;
///    `maxCutShortDuration` is set to include it, but it is genuinely ambiguous from GPS alone.
///
/// No GPS-only signal distinguished the 110 s failed attempt from a normal ending — its speed
/// trace is a steady cruise start to finish. Duration is the only signal in this data that
/// separates cut-short sets from normal ones; treat this as a first pass, not a validated
/// wipeout classifier, and revisit if real data shows a normal short set (a deliberate quick lap)
/// or a normal-length set with a genuine early fall.
public enum FallDetector {
    /// `true` when `duration` is shorter than `thresholds.maxCutShortDuration`.
    public static func detectsFall(
        duration: TimeInterval,
        thresholds: FallDetectionThresholds = .default
    ) -> Bool {
        duration < thresholds.maxCutShortDuration
    }
}
