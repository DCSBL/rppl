import Foundation

/// Detection constants — speeds in km/h (park-human units).
public struct DetectionThresholds: Equatable, Sendable {
    public var rideEnterSpeedKmh: Double
    public var rideEnterHold: TimeInterval
    public var stoppedSpeedKmh: Double
    public var rideExitHold: TimeInterval
    /// Riding + unusable GPS for this long → `unsure`.
    public var gapUnsureHold: TimeInterval
    /// Unsure younger than this can lookback-merge into the same ride; at/after → new ride.
    public var unsureSameRideWindow: TimeInterval
    public var maxHorizontalAccuracyM: Double
    public var maxPlausibleSpeedKmh: Double
    public var maxSpeedJumpKmh: Double

    public init(
        rideEnterSpeedKmh: Double = 15,
        rideEnterHold: TimeInterval = 2.0,
        stoppedSpeedKmh: Double = 4,
        rideExitHold: TimeInterval = 3.0,
        gapUnsureHold: TimeInterval = 3.0,
        unsureSameRideWindow: TimeInterval = 180.0,
        maxHorizontalAccuracyM: Double = 25,
        maxPlausibleSpeedKmh: Double = 45,
        maxSpeedJumpKmh: Double = 30
    ) {
        self.rideEnterSpeedKmh = rideEnterSpeedKmh
        self.rideEnterHold = rideEnterHold
        self.stoppedSpeedKmh = stoppedSpeedKmh
        self.rideExitHold = rideExitHold
        self.gapUnsureHold = gapUnsureHold
        self.unsureSameRideWindow = unsureSameRideWindow
        self.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        self.maxPlausibleSpeedKmh = maxPlausibleSpeedKmh
        self.maxSpeedJumpKmh = maxSpeedJumpKmh
    }

    public static let `default` = DetectionThresholds()

    public var rideEnterSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: rideEnterSpeedKmh)
    }

    public var stoppedSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: stoppedSpeedKmh)
    }
}
