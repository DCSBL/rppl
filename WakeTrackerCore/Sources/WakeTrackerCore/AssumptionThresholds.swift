import Foundation

/// ASSUMPTION constants for `SegmentAssumer` — speeds in km/h (park-human units).
/// Tune after real exports; gap: ride enter 15 below typical cable >22, above walk/swim ceiling 10.
public struct AssumptionThresholds: Equatable, Sendable {
    public var rideEnterSpeedKmh: Double
    public var rideEnterHold: TimeInterval
    public var swimMaxSpeedKmh: Double
    public var stoppedSpeedKmh: Double
    public var failedStartMaxRide: TimeInterval
    public var longStopHold: TimeInterval
    public var walkSpeedMinKmh: Double
    public var walkSpeedMaxKmh: Double
    public var walkHold: TimeInterval
    public var waitSpeedKmh: Double
    public var waitHold: TimeInterval
    public var maxHorizontalAccuracyM: Double
    /// Reject GPS speeds above this (cable parks are slower; spikes are noise).
    public var maxPlausibleSpeedKmh: Double
    /// Reject a sample whose speed jumps this many km/h vs last *usable* sample.
    public var maxSpeedJumpKmh: Double

    public init(
        rideEnterSpeedKmh: Double = 15,
        rideEnterHold: TimeInterval = 2.0,
        swimMaxSpeedKmh: Double = 10,
        stoppedSpeedKmh: Double = 4,
        failedStartMaxRide: TimeInterval = 5.0,
        longStopHold: TimeInterval = 3.0,
        walkSpeedMinKmh: Double = 2,
        walkSpeedMaxKmh: Double = 10,
        walkHold: TimeInterval = 3.0,
        waitSpeedKmh: Double = 1.5,
        waitHold: TimeInterval = 5.0,
        maxHorizontalAccuracyM: Double = 25,
        maxPlausibleSpeedKmh: Double = 45,
        maxSpeedJumpKmh: Double = 30
    ) {
        self.rideEnterSpeedKmh = rideEnterSpeedKmh
        self.rideEnterHold = rideEnterHold
        self.swimMaxSpeedKmh = swimMaxSpeedKmh
        self.stoppedSpeedKmh = stoppedSpeedKmh
        self.failedStartMaxRide = failedStartMaxRide
        self.longStopHold = longStopHold
        self.walkSpeedMinKmh = walkSpeedMinKmh
        self.walkSpeedMaxKmh = walkSpeedMaxKmh
        self.walkHold = walkHold
        self.waitSpeedKmh = waitSpeedKmh
        self.waitHold = waitHold
        self.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        self.maxPlausibleSpeedKmh = maxPlausibleSpeedKmh
        self.maxSpeedJumpKmh = maxSpeedJumpKmh
    }

    public static let `default` = AssumptionThresholds()

    public var rideEnterSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: rideEnterSpeedKmh)
    }

    public var swimMaxSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: swimMaxSpeedKmh)
    }

    public var stoppedSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: stoppedSpeedKmh)
    }

    public var walkSpeedMinMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: walkSpeedMinKmh)
    }

    public var walkSpeedMaxMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: walkSpeedMaxKmh)
    }

    public var waitSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: waitSpeedKmh)
    }
}
