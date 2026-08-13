import Foundation

/// One GPS/water/activity sample fed into `SegmentAssumer`.
public struct AssumerTick: Equatable, Sendable {
    public var timestamp: Date
    public var speedMps: Double?
    public var horizontalAccuracy: Double?
    public var waterSubmersionState: String?
    public var motionActivity: String?

    public init(
        timestamp: Date,
        speedMps: Double? = nil,
        horizontalAccuracy: Double? = nil,
        waterSubmersionState: String? = nil,
        motionActivity: String? = nil
    ) {
        self.timestamp = timestamp
        self.speedMps = speedMps
        self.horizontalAccuracy = horizontalAccuracy
        self.waterSubmersionState = waterSubmersionState
        self.motionActivity = motionActivity
    }
}

/// Auto-proposed segment label written to `assumptions.jsonl`.
public struct AssumptionEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var code: String
    public var timestamp: Date
    /// Rule id + key values; speeds printed in km/h.
    public var reason: String
    public var speedMps: Double?
    public var waterSubmersionState: String?
    public var motionActivity: String?

    public init(
        id: String = UUID().uuidString,
        code: String,
        timestamp: Date = Date(),
        reason: String,
        speedMps: Double? = nil,
        waterSubmersionState: String? = nil,
        motionActivity: String? = nil
    ) {
        self.id = id
        self.code = code
        self.timestamp = timestamp
        self.reason = reason
        self.speedMps = speedMps
        self.waterSubmersionState = waterSubmersionState
        self.motionActivity = motionActivity
    }
}
