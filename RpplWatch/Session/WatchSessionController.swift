import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import WatchKit
import RpplCore
import Observation

@Observable
@MainActor
final class WatchSessionController: NSObject {
    static let shared = WatchSessionController()

    var isRunning = false
    /// Post-stop summary until Done; takes precedence over idle in ContentView.
    var endedSessionSummary: EndedSessionSummary?
    /// First usable GPS fix this session — start pin on end summary map.
    var sessionStartLatitude: Double?
    var sessionStartLongitude: Double?
    /// True while stop teardown / Health save runs — block Start.
    var isStopping = false
    /// Crash recovery started at launch (dangling Health workout, orphaned session files).
    var launchRecoveryTask: Task<Void, Never>?
    /// True while a product Pause is flushing, before `isProductPaused` is set.
    var isPausing = false
    /// True after Stop while the summary is already on screen and the Health save, derived view
    /// and transfer package are still being written in the background.
    var isFinalizing = false
    /// True while permissions / HK start run — stay on the tapped picker card.
    var isStarting = false
    /// Opaque code of the activity card currently starting.
    var startingActivityCode: String?
    /// Product pause: sensors/timers halted; distinct from detection `inactive`.
    var isProductPaused = false
    var detectionCode = DetectionCodes.inactive
    var lastConfidentCode = DetectionCodes.inactive
    var elapsed: TimeInterval = 0
    var locationCount = 0
    var motionCount = 0
    var detectionCount = 0
    /// Detection events whose write failed; retried on the next event and on every flush.
    var pendingDetections = PendingDetectionQueue()
    /// On-disk size of the active session package (updated after flushes / detection writes).
    var storedByteSize: Int64 = 0
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastHorizontalAccuracy: Double?
    var lastHeartRate: Double?
    var lastSpeedMps: Double?
    /// Cumulative active energy this session (mirrors `HKLiveWorkoutBuilder` statistics).
    var activeEnergyKilocalories: Double?
    /// Cumulative basal/resting energy this session (mirrors `HKLiveWorkoutBuilder` statistics).
    var basalEnergyKilocalories: Double?
    /// Active + basal, when active energy has started reporting.
    var totalEnergyKilocalories: Double? {
        guard let activeEnergyKilocalories else { return nil }
        return activeEnergyKilocalories + (basalEnergyKilocalories ?? 0)
    }
    /// Set-gated session distance (sum of set meters). Not dock/pause walking.
    var totalDistanceM: Double { liveSetTracker.sessionSetMeters }
    /// Session-wide average speed (total set distance over elapsed time), nil before any movement.
    var sessionAverageSpeedKmh: Double? {
        guard elapsed > 0, totalDistanceM > 0 else { return nil }
        return (totalDistanceM / elapsed) * 3.6
    }
    var currentSetDuration: TimeInterval = 0
    var currentInactiveDuration: TimeInterval = 0
    /// Sum of completed `riding` segments this session (current ongoing segment added separately).
    var cumulativeRidingDuration: TimeInterval = 0
    /// Sum of completed `inactive` segments this session (current ongoing segment added separately).
    var cumulativeInactiveDuration: TimeInterval = 0
    var filterRejectionReason: String?
    var statusText = String(localized: "Idle")
    var errorText: String?
    var healthAuthStatus = "unknown"
    var locationAuthStatus = "unknown"
    var motionAvailability = "unknown"
    /// Structured gate states for Watch permissions onboarding.
    var locationPermission: WatchPermissionState = .notDetermined
    var healthPermission: WatchPermissionState = .notDetermined
    /// False until the first off-main Health status lookup returns; gates onboarding vs idle.
    var isHealthPermissionResolved = false
    @ObservationIgnored var healthStatusLookup: Task<HKAuthorizationStatus, Never>?
    var motionPermission: WatchPermissionState = .notDetermined
    /// True while an auto or manual system permission sheet sequence is in flight.
    /// Kept separate from ProgressView so the list stays interactive while HealthKit warms up.
    var isPromptingPermissions = false

    var permissionStates: [WatchPermissionKind: WatchPermissionState] {
        [
            .location: locationPermission,
            .health: healthPermission,
            .motion: motionPermission
        ]
    }

    /// Set when Start was refused for a missing required permission; drives the explain sheet.
    var startBlockedBy: WatchPermissionKind?

    /// First run only: a required permission can still show its system sheet.
    var needsFirstRunPermissionPrompt: Bool {
        WatchPermissionOrder.needsFirstRunPrompt(states: permissionStates)
    }

    var areRecordingPermissionsReady: Bool {
        WatchPermissionOrder.areAllReady(permissionStates)
    }

    /// `workout` when HK session started; `sensorsOnly` when Health denied / simulator fallback.
    var recordingMode = "none"
    /// Mirrors `WKInterfaceDevice.current().isWaterLockEnabled` (refreshed by controls UI).
    var isWaterLockEnabled = false
    var motionRecordingEnabled = false
    /// Set when `MotionRecordingPolicy` stopped motion for the rest of this session.
    var motionStoppedReason: String?
    /// Last motion frame write; motion is flushed once per `MotionRecordingPolicy.frameInterval`.
    var lastMotionFlushAt: Date?

    var isUnsure: Bool { detectionCode == DetectionCodes.unsure }
    var setCount: Int { liveSetTracker.setCount }
    var currentSetSpeedKmh: Double? { liveSetTracker.currentSpeedKmh }
    /// Cable speed estimated from finished sets; nil until enough riding GPS.
    var cableSpeedKmh: Double? { liveSetTracker.cableSpeedKmh }
    var currentSetLapCount: Int { liveSetTracker.currentSetLapCount }
    var lastSetLapCount: Int { liveSetTracker.lastSetLapCount }
    /// Live meters while riding; frozen last-set meters when inactive (`0 m` before first set).
    var displaySetMeters: Double {
        liveSetTracker.isSetOngoing
            ? liveSetTracker.currentSetMeters
            : liveSetTracker.lastSetMeters
    }
    var lastSetMeters: Double { liveSetTracker.lastSetMeters }
    var lastSetDuration: TimeInterval { liveSetTracker.lastSetDuration }
    var didCompleteSet: Bool { liveSetTracker.didCompleteSet }
    var isSetOngoing: Bool { liveSetTracker.isSetOngoing }
    /// Ultra water-temp hardware present. Drives hide vs `- C` on inactive overview.
    var waterTemperatureAvailable = false
    /// Running mean of persisted submerged samples this session.
    var averageWaterTemperatureCelsius: Double?
    /// Measured average when available, else the park-station estimate (flagged `isEstimate`).
    var waterTemperatureDisplay: WaterTemperatureDisplay? {
        WaterTemperatureDisplay.resolve(measuredAverage: averageWaterTemperatureCelsius, estimate: waterEstimate)
    }

    /// Debug-only: force pause/ride UI, or leave live detection (`detected`).
    var detectionSimulationMode: DetectionSimulationMode = .detected
    /// Debug-only: shrink the app's root view to a smaller watch's point size for layout checks.
    var debugScreenSize: DebugScreenSize = .actual

    var liveSetTracker = LiveSetTracker()
    let healthStore = HKHealthStore()
    var workoutSession: HKWorkoutSession?
    var workoutBuilder: HKLiveWorkoutBuilder?
    var workoutDataSource: HKLiveWorkoutDataSource?
    var workoutConfiguration: HKWorkoutConfiguration?
    var workoutRouteBuilder: HKWorkoutRouteBuilder?
    /// True while an HK set activity is open (ended on detection `inactive`).
    var hkRideActivityOpen = false
    /// True while `handleWorkoutSessionLost` runs, so `.ended` + `.stopped` callbacks act once.
    var isHandlingWorkoutLoss = false
    var workoutStoppedContinuation: CheckedContinuation<Date, Never>?
    /// Callers waiting for the HK session to reach `.running`, keyed per caller.
    var workoutRunningWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    var hkRideDistanceMeters = 0.0
    var hkRideDistanceAnchorMeters = 0.0
    /// Set windows for HealthKit distance samples and interval metadata.
    var hkRides: [HKRideMetric] = []
    var hkRideStartedAt: Date?
    var hkGpsFilter = GpsSignalFilter()
    var hkPreviousUsableSpeedMps: Double?
    var hkPreviousUsableAt: Date?
    var hkPendingJumpSpeedMps: Double?
    var hkPeakSpeedMps: Double = 0

    struct HKRideMetric {
        var startedAt: Date
        var endedAt: Date
        var meters: Double
        var duration: TimeInterval
    }

    let locationManager = CLLocationManager()
    let motionManager = CMMotionManager()
    let activityManager = CMMotionActivityManager()
    var waterManager: CMWaterSubmersionManager?

    var store: SessionFileStore?
    var manifest: SessionManifest?
    var latestLocation: CLLocation?
    var latestActivity: String?
    var latestWaterState: String?
    var waterBuffer: [WaterTemperatureSample] = []
    var batteryBuffer: [BatterySample] = []
    var lastPersistedBatteryAt: Date?
    var lastPersistedBatteryLevel: Double?
    var lastPersistedBatteryState: String?
    var lastPersistedLowPowerMode: Bool?
    /// Battery warnings already shown this session (`BatteryGuardPolicy`).
    var batteryWarnedCodes: Set<String> = []
    /// A battery-critical stop is under way; never started twice.
    var isBatteryAutoStopping = false
    var lastPersistedWaterTempAt: Date?
    var lastLoggedWaterTempC: Double?
    var waterTempNeedsBoutSample = false
    var waterTempSum = 0.0
    var waterTempCount = 0
    var detectionEngine = DetectionEngine()
    var locationBuffer: [LocationSample] = []
    var motionBuffer: [MotionSample] = []
    var healthBuffer: [HealthMetricSample] = []
    /// Recent GPS fixes for backdating live set meters on `ride_enter`.
    var recentLocationRing: [LocationSample] = []
    /// Drops repeated / out-of-order CoreLocation deliveries before detection sees them.
    var locationSequencer = LocationFixSequencer()
    /// Route points waiting for the next batched `insertRouteData` (never awaited by detection).
    var pendingRouteLocations: [CLLocation] = []
    var routeInsertTask: Task<Void, Never>?
    var sensorSamplingDense = false
    var flushTask: Task<Void, Never>?
    /// Last off-main flush; the next one waits on it so batches append in order.
    var flushChain: Task<Void, Never>?
    /// Retries the HealthKit start while a session records sensors-only (`startHealthKitRestartLoop`).
    var healthKitRestartTask: Task<Void, Never>?
    /// The last HealthKit start was skipped because Health is denied; a denial is never retried.
    var lastHealthKitStartWasDenied = false
    var timerTask: Task<Void, Never>?
    var startedAt: Date?
    /// Wall time excluded from `elapsed` while product-paused (completed pauses).
    var pausedAccumulated: TimeInterval = 0
    var productPausedAt: Date?
    var currentSegmentStartedAt: Date?
    var lastPersistedConfidentCode = DetectionCodes.inactive
    var motionUpdatesStarted = false
    var activityUpdatesStarted = false
    var sessionWaterSamples: [WaterTemperatureSample] = []
    var airWeatherSnapshot: AirWeatherSnapshot?
    var airWeatherFetchTask: Task<Void, Never>?
    var airWeatherAttempted = false
    /// Park-station water estimate for this session; shown until the Watch measures real water temp.
    var waterEstimate: ParkWaterTemperature?
    var waterEstimateFetchTask: Task<Void, Never>?
    var waterEstimateAttempted = false

    let workoutType = HKObjectType.workoutType()
    let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
    let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    let basalEnergyType = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!
    let distanceType = HKObjectType.quantityType(forIdentifier: .distancePaddleSports)!
    let waterTemperatureType = HKObjectType.quantityType(forIdentifier: .waterTemperature)!
    let workoutRouteType = HKSeriesType.workoutRoute()

    /// Write access required to start HKWorkoutSession and save the workout/route.
    var typesToShare: Set<HKSampleType> {
        [
            workoutType,
            activeEnergyType,
            basalEnergyType,
            heartRateType,
            distanceType,
            waterTemperatureType,
            workoutRouteType
        ]
    }

    var typesToRead: Set<HKObjectType> {
        [heartRateType, activeEnergyType, basalEnergyType, workoutType, distanceType, waterTemperatureType]
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        // Permission status is refreshed from ContentView.onAppear — never block init on healthd.

        if CMWaterSubmersionManager.waterSubmersionAvailable {
            let manager = CMWaterSubmersionManager()
            manager.delegate = self
            waterManager = manager
            waterTemperatureAvailable = true
        }
    }

}
