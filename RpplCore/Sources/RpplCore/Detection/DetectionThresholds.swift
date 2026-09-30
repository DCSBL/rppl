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
    /// Off the cable but still moving (km/h): swimming or coasting back sits in this band while
    /// the cable itself runs ~31 km/h. Above `walkBandSpeedKmh`, well below `rideEnterSpeedKmh`.
    public var offCableSpeedKmh: Double
    /// Longer than `rideExitHold` because the band is wider.
    public var offCableExitHold: TimeInterval
    /// A set younger than this can be revoked as a failed start.
    public var failedStartMaxAge: TimeInterval
    /// Cable-speed seconds a set must show to be real. Above the enter hold that opened it, so
    /// revocation needs more evidence than a single dock spike can produce.
    public var failedStartCableEvidence: TimeInterval
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
    /// A fresh fix older than the latest tick by more than this is stale and ignored: the
    /// heartbeat clock already judged that moment. Wider than normal CoreLocation delivery lag.
    public var maxFixLag: TimeInterval

    public init(
        rideEnterSpeedKmh: Double = 20,
        rideEnterHold: TimeInterval = 3.0,
        walkBandSpeedKmh: Double = 8,
        rideEnterHoldFromWalk: TimeInterval = 4.0,
        stoppedSpeedKmh: Double = 4,
        rideExitHold: TimeInterval = 3.0,
        offCableSpeedKmh: Double = 13,
        offCableExitHold: TimeInterval = 4.0,
        failedStartMaxAge: TimeInterval = 12.0,
        failedStartCableEvidence: TimeInterval = 6.0,
        gapUnsureHold: TimeInterval = 3.0,
        unsureSameRideWindow: TimeInterval = 60.0,
        maxHorizontalAccuracyM: Double = 25,
        maxPlausibleSpeedKmh: Double = 80,
        maxSpeedJumpKmh: Double = 30,
        maxSpeedJumpWindow: TimeInterval = 10.0,
        speedJumpCorroborationKmh: Double = 10,
        maxFixLag: TimeInterval = 10.0
    ) {
        self.rideEnterSpeedKmh = rideEnterSpeedKmh
        self.rideEnterHold = rideEnterHold
        self.walkBandSpeedKmh = walkBandSpeedKmh
        self.rideEnterHoldFromWalk = rideEnterHoldFromWalk
        self.stoppedSpeedKmh = stoppedSpeedKmh
        self.rideExitHold = rideExitHold
        self.offCableSpeedKmh = offCableSpeedKmh
        self.offCableExitHold = offCableExitHold
        self.failedStartMaxAge = failedStartMaxAge
        self.failedStartCableEvidence = failedStartCableEvidence
        self.gapUnsureHold = gapUnsureHold
        self.unsureSameRideWindow = unsureSameRideWindow
        self.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        self.maxPlausibleSpeedKmh = maxPlausibleSpeedKmh
        self.maxSpeedJumpKmh = maxSpeedJumpKmh
        self.maxSpeedJumpWindow = maxSpeedJumpWindow
        self.speedJumpCorroborationKmh = speedJumpCorroborationKmh
        self.maxFixLag = maxFixLag
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

    public var offCableSpeedMps: Double {
        SpeedUnits.metersPerSecond(fromKilometersPerHour: offCableSpeedKmh)
    }
}
