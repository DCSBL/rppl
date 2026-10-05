import Foundation

/// A condition that puts the recording at risk. `code` is an opaque string (hard constraint 4).
public struct RecordingIssue: Equatable, Hashable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        case warning = 0
        case critical = 1

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let code: String
    public let severity: Severity

    public init(code: String, severity: Severity) {
        self.code = code
        self.severity = severity
    }
}

/// Pure evaluation of "is this recording still safe?", so the Watch can show it during a session.
public enum RecordingHealth {
    /// Opaque issue codes.
    public enum Code {
        public static let hkMissing = "hk_missing"
        public static let writeFailing = "write_failing"
        public static let storageLow = "storage_low"
        public static let gpsMissing = "gps_missing"
        public static let batteryLow = "battery_low"
        public static let locationReduced = "location_reduced"
    }

    public struct Inputs: Equatable, Sendable {
        /// True when no running HealthKit workout backs the session (sensors-only, or lost).
        public var hkMissing: Bool
        public var consecutiveWriteFailures: Int
        /// Free space on the volume; nil when unknown.
        public var freeBytes: Int64?
        /// Seconds since the last usable GPS fix (or since recording started); nil before start.
        public var secondsSinceUsableFix: TimeInterval?
        public var isProductPaused: Bool
        /// Battery fraction 0…1; negative when unknown.
        public var batteryLevel: Double
        /// `BatteryStateCodes`.
        public var batteryState: String
        public var locationReduced: Bool

        public init(
            hkMissing: Bool = false,
            consecutiveWriteFailures: Int = 0,
            freeBytes: Int64? = nil,
            secondsSinceUsableFix: TimeInterval? = nil,
            isProductPaused: Bool = false,
            batteryLevel: Double = -1,
            batteryState: String = BatteryStateCodes.unknown,
            locationReduced: Bool = false
        ) {
            self.hkMissing = hkMissing
            self.consecutiveWriteFailures = consecutiveWriteFailures
            self.freeBytes = freeBytes
            self.secondsSinceUsableFix = secondsSinceUsableFix
            self.isProductPaused = isProductPaused
            self.batteryLevel = batteryLevel
            self.batteryState = batteryState
            self.locationReduced = locationReduced
        }
    }

    /// Failed flushes / detection writes in a row before the rider is told.
    public static let writeFailureThreshold = 3
    /// No usable GPS fix for this long (not paused) counts as missing.
    public static let gpsMissingAfter: TimeInterval = 120

    /// Issues most severe first, then by code, so the UI shows the worst one.
    public static func evaluate(_ inputs: Inputs) -> [RecordingIssue] {
        var issues: [RecordingIssue] = []
        if inputs.hkMissing {
            issues.append(.init(code: Code.hkMissing, severity: .critical))
        }
        if inputs.consecutiveWriteFailures >= writeFailureThreshold {
            issues.append(.init(code: Code.writeFailing, severity: .critical))
        }
        if let free = inputs.freeBytes, free < SampleRequeue.lowStorageWarningBytes {
            let critical = free < MotionRecordingPolicy.dropBelowFreeBytes
            issues.append(.init(code: Code.storageLow, severity: critical ? .critical : .warning))
        }
        if !inputs.isProductPaused, let gap = inputs.secondsSinceUsableFix, gap > gpsMissingAfter {
            issues.append(.init(code: Code.gpsMissing, severity: .warning))
        }
        if inputs.batteryLevel >= 0, inputs.batteryLevel <= BatteryGuardPolicy.warnLevels[1].level,
           inputs.batteryState != BatteryStateCodes.charging, inputs.batteryState != BatteryStateCodes.full {
            let critical = inputs.batteryLevel <= BatteryGuardPolicy.warnLevels[0].level
            issues.append(.init(code: Code.batteryLow, severity: critical ? .critical : .warning))
        }
        if inputs.locationReduced {
            issues.append(.init(code: Code.locationReduced, severity: .warning))
        }
        return issues.sorted {
            $0.severity != $1.severity ? $0.severity > $1.severity : $0.code < $1.code
        }
    }
}

/// Tells which issues are new, so the haptic fires once per appearance, not every second.
public struct RecordingAlertGate: Sendable {
    private var active: Set<String> = []

    public init() {}

    /// Codes of critical issues that were not active at the previous call. An issue that cleared
    /// and came back counts as new again.
    public mutating func newCriticalCodes(_ issues: [RecordingIssue]) -> [String] {
        let current = Set(issues.map(\.code))
        let fresh = issues.filter { $0.severity == .critical && !active.contains($0.code) }.map(\.code)
        active = current
        return fresh
    }

    public mutating func reset() { active = [] }
}
