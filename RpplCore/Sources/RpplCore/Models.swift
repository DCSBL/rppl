import Foundation

public struct SessionManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sessionId: String
    public var testerId: String
    public var appVersion: String
    public var buildNumber: String
    public var watchModel: String
    public var systemVersion: String
    public var startedAt: Date
    public var endedAt: Date?
    public var transferState: TransferState

    public enum TransferState: String, Codable, Equatable, Sendable {
        case recording
        case readyToTransfer
        case transferring
        case acknowledged
    }

    public init(
        schemaVersion: Int = SessionSchema.currentVersion,
        sessionId: String = UUID().uuidString,
        testerId: String,
        appVersion: String,
        buildNumber: String,
        watchModel: String,
        systemVersion: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        transferState: TransferState = .recording
    ) {
        self.schemaVersion = schemaVersion
        self.sessionId = sessionId
        self.testerId = testerId
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.watchModel = watchModel
        self.systemVersion = systemVersion
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.transferState = transferState
    }
}

public struct GPSSnapshot: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double?
    public var speed: Double?
    public var course: Double?
    public var timestamp: Date

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double,
        verticalAccuracy: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }
}

public struct LabelEvent: Codable, Equatable, Sendable, Identifiable {
    /// Legacy manual label from older builds; new sessions leave `labels.jsonl` empty.
    public var id: String
    public var code: String
    public var timestamp: Date
    public var gps: GPSSnapshot?
    public var waterSubmersionState: String?
    public var waterTemperatureCelsius: Double?
    public var motionActivity: String?

    public init(
        id: String = UUID().uuidString,
        code: String,
        timestamp: Date = Date(),
        gps: GPSSnapshot? = nil,
        waterSubmersionState: String? = nil,
        waterTemperatureCelsius: Double? = nil,
        motionActivity: String? = nil
    ) {
        self.id = id
        self.code = code
        self.timestamp = timestamp
        self.gps = gps
        self.waterSubmersionState = waterSubmersionState
        self.waterTemperatureCelsius = waterTemperatureCelsius
        self.motionActivity = motionActivity
    }
}

public struct LocationSample: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double?
    public var speed: Double?
    public var course: Double?

    public init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double,
        verticalAccuracy: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
    }
}

public struct MotionSample: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var userAccelX: Double
    public var userAccelY: Double
    public var userAccelZ: Double
    public var rotationX: Double
    public var rotationY: Double
    public var rotationZ: Double
    public var pitch: Double
    public var roll: Double
    public var yaw: Double

    public init(
        timestamp: Date,
        userAccelX: Double,
        userAccelY: Double,
        userAccelZ: Double,
        rotationX: Double,
        rotationY: Double,
        rotationZ: Double,
        pitch: Double,
        roll: Double,
        yaw: Double
    ) {
        self.timestamp = timestamp
        self.userAccelX = userAccelX
        self.userAccelY = userAccelY
        self.userAccelZ = userAccelZ
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
    }

    /// Short keys + 4-decimal quantize — JSONL shrinks hard before zlib.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CompactCodingKeys.self)
        try container.encode(timestamp, forKey: .t)
        try container.encode(Self.quantize(userAccelX), forKey: .ax)
        try container.encode(Self.quantize(userAccelY), forKey: .ay)
        try container.encode(Self.quantize(userAccelZ), forKey: .az)
        try container.encode(Self.quantize(rotationX), forKey: .rx)
        try container.encode(Self.quantize(rotationY), forKey: .ry)
        try container.encode(Self.quantize(rotationZ), forKey: .rz)
        try container.encode(Self.quantize(pitch), forKey: .p)
        try container.encode(Self.quantize(roll), forKey: .r)
        try container.encode(Self.quantize(yaw), forKey: .y)
    }

    public init(from decoder: Decoder) throws {
        if let compact = try? decoder.container(keyedBy: CompactCodingKeys.self),
           compact.contains(.t) {
            timestamp = try compact.decode(Date.self, forKey: .t)
            userAccelX = try compact.decode(Double.self, forKey: .ax)
            userAccelY = try compact.decode(Double.self, forKey: .ay)
            userAccelZ = try compact.decode(Double.self, forKey: .az)
            rotationX = try compact.decode(Double.self, forKey: .rx)
            rotationY = try compact.decode(Double.self, forKey: .ry)
            rotationZ = try compact.decode(Double.self, forKey: .rz)
            pitch = try compact.decode(Double.self, forKey: .p)
            roll = try compact.decode(Double.self, forKey: .r)
            yaw = try compact.decode(Double.self, forKey: .y)
            return
        }
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        timestamp = try legacy.decode(Date.self, forKey: .timestamp)
        userAccelX = try legacy.decode(Double.self, forKey: .userAccelX)
        userAccelY = try legacy.decode(Double.self, forKey: .userAccelY)
        userAccelZ = try legacy.decode(Double.self, forKey: .userAccelZ)
        rotationX = try legacy.decode(Double.self, forKey: .rotationX)
        rotationY = try legacy.decode(Double.self, forKey: .rotationY)
        rotationZ = try legacy.decode(Double.self, forKey: .rotationZ)
        pitch = try legacy.decode(Double.self, forKey: .pitch)
        roll = try legacy.decode(Double.self, forKey: .roll)
        yaw = try legacy.decode(Double.self, forKey: .yaw)
    }

    private enum CompactCodingKeys: String, CodingKey {
        case t, ax, ay, az, rx, ry, rz, p, r, y
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case timestamp, userAccelX, userAccelY, userAccelZ
        case rotationX, rotationY, rotationZ, pitch, roll, yaw
    }

    private static func quantize(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}

public struct HealthMetricSample: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var heartRateBPM: Double?
    public var activeEnergyKilocalories: Double?

    public init(
        timestamp: Date,
        heartRateBPM: Double? = nil,
        activeEnergyKilocalories: Double? = nil
    ) {
        self.timestamp = timestamp
        self.heartRateBPM = heartRateBPM
        self.activeEnergyKilocalories = activeEnergyKilocalories
    }
}
