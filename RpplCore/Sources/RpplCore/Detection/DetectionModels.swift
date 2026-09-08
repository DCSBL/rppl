import Foundation

/// One GPS sample (+ optional water/activity for later detectors) fed into `DetectionEngine`.
public struct DetectionTick: Equatable, Sendable {
    public var timestamp: Date
    public var speedMps: Double?
    public var horizontalAccuracy: Double?
    public var waterSubmersionState: String?
    public var motionActivity: String?
    /// `false` for a heartbeat tick that carries no new GPS fix (Watch 1 Hz timer, water-state
    /// change). Heartbeats advance the gap / timeout clocks but never present speed evidence.
    public var hasFreshFix: Bool

    public init(
        timestamp: Date,
        speedMps: Double? = nil,
        horizontalAccuracy: Double? = nil,
        waterSubmersionState: String? = nil,
        motionActivity: String? = nil,
        hasFreshFix: Bool = true
    ) {
        self.timestamp = timestamp
        self.speedMps = speedMps
        self.horizontalAccuracy = horizontalAccuracy
        self.waterSubmersionState = waterSubmersionState
        self.motionActivity = motionActivity
        self.hasFreshFix = hasFreshFix
    }

    /// Time-only tick for when no new fix arrived. Keeps gap / timeout clocks running so
    /// detection does not stall while GPS is silent.
    public static func heartbeat(
        at timestamp: Date,
        waterSubmersionState: String? = nil,
        motionActivity: String? = nil
    ) -> DetectionTick {
        DetectionTick(
            timestamp: timestamp,
            waterSubmersionState: waterSubmersionState,
            motionActivity: motionActivity,
            hasFreshFix: false
        )
    }
}

/// Detector decision written to `detections.jsonl` (transitions + lookback revisions only).
public struct DetectionEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var code: String
    public var timestamp: Date
    /// Rule/detector id + key values; speeds printed in km/h.
    public var reason: String
    public var detectorId: String
    public var speedMps: Double?
    public var horizontalAccuracy: Double?
    public var waterSubmersionState: String?
    public var motionActivity: String?
    /// When set, this line revises a prior event (append-only lookback).
    public var supersedesId: String?

    public init(
        id: String = UUID().uuidString,
        code: String,
        timestamp: Date = Date(),
        reason: String,
        detectorId: String,
        speedMps: Double? = nil,
        horizontalAccuracy: Double? = nil,
        waterSubmersionState: String? = nil,
        motionActivity: String? = nil,
        supersedesId: String? = nil
    ) {
        self.id = id
        self.code = code
        self.timestamp = timestamp
        self.reason = reason
        self.detectorId = detectorId
        self.speedMps = speedMps
        self.horizontalAccuracy = horizontalAccuracy
        self.waterSubmersionState = waterSubmersionState
        self.motionActivity = motionActivity
        self.supersedesId = supersedesId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        code = try container.decode(String.self, forKey: .code)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        reason = try container.decode(String.self, forKey: .reason)
        detectorId = try container.decodeIfPresent(String.self, forKey: .detectorId) ?? "unknown"
        speedMps = try container.decodeIfPresent(Double.self, forKey: .speedMps)
        horizontalAccuracy = try container.decodeIfPresent(Double.self, forKey: .horizontalAccuracy)
        waterSubmersionState = try container.decodeIfPresent(String.self, forKey: .waterSubmersionState)
        motionActivity = try container.decodeIfPresent(String.self, forKey: .motionActivity)
        supersedesId = try container.decodeIfPresent(String.self, forKey: .supersedesId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, timestamp, reason, detectorId, speedMps, horizontalAccuracy
        case waterSubmersionState, motionActivity, supersedesId
    }
}

/// Signal emitted by a `Detector` for the merger to apply.
public struct DetectionSignal: Equatable, Sendable {
    public var kind: Kind
    public var detectorId: String
    public var reason: String

    public enum Kind: String, Equatable, Sendable {
        case enterRide
        case exitRide
        case enterUnsure
        case unsureTimeout
    }

    public init(kind: Kind, detectorId: String, reason: String) {
        self.kind = kind
        self.detectorId = detectorId
        self.reason = reason
    }
}
