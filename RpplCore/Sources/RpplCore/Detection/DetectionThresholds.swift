import Foundation

/// Detection constants — speeds in km/h (park-human units).
public struct DetectionThresholds: Equatable, Sendable {
    public var rideEnterSpeedKmh: Double
    public var rideEnterHold: TimeInterval
    /// Last usable speed at/below this (km/h) when highSpeed starts → use `rideEnterHoldFromWalk`.
    public var walkBandSpeedKmh: Double
    /// Longer enter hold after a walk-band start (dock GPS spikes).
    public var rideEnterHoldFromWalk: TimeInterval
    public var stoppedSpeedKmh: Double
    public var rideExitHold: TimeInterval
    /// Riding + unusable GPS for this long → `unsure`.
    public var gapUnsureHold: TimeInterval
    /// Unsure younger than this can lookback-merge into the same ride; at/after → new set.
    public var unsureSameRideWindow: TimeInterval
    public var maxHorizontalAccuracyM: Double
    public var maxPlausibleSpeedKmh: Double
    public var maxSpeedJumpKmh: Double
    /// Jump filter only compares against a usable sample younger than this — a speed step
    /// measured across a long GPS silence says nothing about a spike.
    public var maxSpeedJumpWindow: TimeInterval
    /// Two consecutive samples agreeing within this (km/h) make a jump a real step, not a
    /// spike: accept the second one instead of latching on a stale comparison.
    public var speedJumpCorroborationKmh: Double

    public init(
        rideEnterSpeedKmh: Double = 20,
        rideEnterHold: TimeInterval = 3.0,
        walkBandSpeedKmh: Double = 8,
        rideEnterHoldFromWalk: TimeInterval = 4.0,
        stoppedSpeedKmh: Double = 4,
        rideExitHold: TimeInterval = 3.0,
        gapUnsureHold: TimeInterval = 3.0,
        unsureSameRideWindow: TimeInterval = 60.0,
        maxHorizontalAccuracyM: Double = 25,
        maxPlausibleSpeedKmh: Double = 80,
        maxSpeedJumpKmh: Double = 30,
        maxSpeedJumpWindow: TimeInterval = 10.0,
        speedJumpCorroborationKmh: Double = 10
    ) {
        self.rideEnterSpeedKmh = rideEnterSpeedKmh
        self.rideEnterHold = rideEnterHold
        self.walkBandSpeedKmh = walkBandSpeedKmh
        self.rideEnterHoldFromWalk = rideEnterHoldFromWalk
        self.stoppedSpeedKmh = stoppedSpeedKmh
        self.rideExitHold = rideExitHold
        self.gapUnsureHold = gapUnsureHold
        self.unsureSameRideWindow = unsureSameRideWindow
        self.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        self.maxPlausibleSpeedKmh = maxPlausibleSpeedKmh
        self.maxSpeedJumpKmh = maxSpeedJumpKmh
        self.maxSpeedJumpWindow = maxSpeedJumpWindow
        self.speedJumpCorroborationKmh = speedJumpCorroborationKmh
    }

    public static let `default` = DetectionThresholds()

    public var rideEnterSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: rideEnterSpeedKmh)
    }

    public var stoppedSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: stoppedSpeedKmh)
    }

    public var walkBandSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: walkBandSpeedKmh)
    }
}
