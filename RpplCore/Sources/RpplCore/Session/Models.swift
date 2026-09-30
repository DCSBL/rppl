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
    /// True when Watch had water-submersion hardware at session start (Ultra).
    public var waterTemperatureAvailable: Bool?
    /// Opaque activity code (`wakeboard`, …). Localized titles are display-only.
    public var activityCode: String?
    /// Watch settings wrist side at session start (`left` / `right`). Nil for older sessions.
    public var wristLocation: String?
    /// Watch settings Digital Crown side at session start (`left` / `right`). Nil for older sessions.
    public var crownOrientation: String?
    /// When set, session was imported from an export JSON on phone (not Watch WC transfer). No HealthKit.
    public var imported: Date?
    /// WeatherKit current conditions near the start of the session. Nil when unavailable.
    public var weather: SessionWeather?
    /// Estimated water temperature from the nearest park's monitoring station, fetched at session
    /// start. A stand-in until (or instead of) real Watch measurements. Nil when unavailable.
    public var waterTemperatureEstimate: ParkWaterTemperature?
    /// `Park.id` this session belongs to. Written by the phone after import; nil when unlinked.
    public var parkId: String?
    /// How `parkId` was set (`auto` / `manual`). `manual` is never overwritten by auto-matching,
    /// including a manual "no park" (`parkId` nil).
    public var parkIdSource: String?
    /// Watch-side transfer bookkeeping: packages queued so far, earliest next attempt
    /// (`TransferRetryPolicy`), and the phone's last import error.
    public var transferAttempts: Int?
    public var nextTransferAttemptAt: Date?
    public var lastTransferError: String?

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
        transferState: TransferState = .recording,
        waterTemperatureAvailable: Bool? = nil,
        activityCode: String? = nil,
        wristLocation: String? = nil,
        crownOrientation: String? = nil,
        imported: Date? = nil,
        weather: SessionWeather? = nil,
        waterTemperatureEstimate: ParkWaterTemperature? = nil,
        parkId: String? = nil,
        parkIdSource: String? = nil,
        transferAttempts: Int? = nil,
        nextTransferAttemptAt: Date? = nil,
        lastTransferError: String? = nil
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
        self.waterTemperatureAvailable = waterTemperatureAvailable
        self.activityCode = activityCode
        self.wristLocation = wristLocation
        self.crownOrientation = crownOrientation
        self.imported = imported
        self.weather = weather
        self.waterTemperatureEstimate = waterTemperatureEstimate
        self.parkId = parkId
        self.parkIdSource = parkIdSource
        self.transferAttempts = transferAttempts
        self.nextTransferAttemptAt = nextTransferAttemptAt
        self.lastTransferError = lastTransferError
    }
}

/// Current weather captured once per session (Watch, via WeatherKit). Wind + precipitation are
/// nil for sessions recorded before those fields existed.
public struct SessionWeather: Codable, Equatable, Sendable {
    public var temperatureCelsius: Double
    /// Relative humidity, 0–100.
    public var humidityPercent: Double
    public var windSpeedKmh: Double?
    /// Meteorological "wind from" bearing, degrees clockwise from true north.
    public var windDirectionDegrees: Double?
    public var precipitationMmPerHour: Double?

    public init(
        temperatureCelsius: Double,
        humidityPercent: Double,
        windSpeedKmh: Double? = nil,
        windDirectionDegrees: Double? = nil,
        precipitationMmPerHour: Double? = nil
    ) {
        self.temperatureCelsius = temperatureCelsius
        self.humidityPercent = humidityPercent
        self.windSpeedKmh = windSpeedKmh
        self.windDirectionDegrees = windDirectionDegrees
        self.precipitationMmPerHour = precipitationMmPerHour
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
    public var basalEnergyKilocalories: Double?

    public init(
        timestamp: Date,
        heartRateBPM: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        basalEnergyKilocalories: Double? = nil
    ) {
        self.timestamp = timestamp
        self.heartRateBPM = heartRateBPM
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.basalEnergyKilocalories = basalEnergyKilocalories
    }
}

/// Sparse Ultra water-temperature reading (persisted while submerged).
public struct WaterTemperatureSample: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var celsius: Double

    public init(timestamp: Date, celsius: Double) {
        self.timestamp = timestamp
        self.celsius = celsius
    }
}

/// Sparse Watch battery reading (`WKInterfaceDevice.batteryLevel` / `batteryState`).
/// No public mV API — `level` is the raw 0…1 fraction (full Float precision as Double).
public struct BatterySample: Codable, Equatable, Sendable {
    public var timestamp: Date
    /// Fraction 0…1 from `WKInterfaceDevice.batteryLevel`.
    public var level: Double
    /// Opaque: `unplugged` | `charging` | `full` | `unknown`.
    public var state: String

    public init(timestamp: Date, level: Double, state: String) {
        self.timestamp = timestamp
        self.level = level
        self.state = state
    }
}
