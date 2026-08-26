import Foundation

/// Injectable set-crossing thresholds (fixed defaults now; dynamic resolver later).
public struct SetThresholds: Equatable, Sendable {
    /// Re-enter within this radius of start to count a crossing.
    public var startSafeRadiusM: Double
    /// Must leave beyond this radius before a crossing can arm (hysteresis ≥ safe).
    public var exitRadiusM: Double
    /// Minimum accepted path while outside before re-entry counts.
    public var minPathBeforeCrossingM: Double
    public var maxHorizontalAccuracyM: Double

    public init(
        startSafeRadiusM: Double = 50,
        exitRadiusM: Double = 70,
        minPathBeforeCrossingM: Double = 200,
        maxHorizontalAccuracyM: Double = DetectionThresholds.default.maxHorizontalAccuracyM
    ) {
        self.startSafeRadiusM = startSafeRadiusM
        self.exitRadiusM = exitRadiusM
        self.minPathBeforeCrossingM = minPathBeforeCrossingM
        self.maxHorizontalAccuracyM = maxHorizontalAccuracyM
    }

    /// Cable-loop defaults (safe 50 m / exit 70 m / min path 200 m).
    public static let `default` = SetThresholds()
}
