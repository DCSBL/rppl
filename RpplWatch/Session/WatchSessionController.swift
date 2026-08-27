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
    /// True while stop teardown / Health save runs — keep active UI with spinner; block Start.
    var isStopping = false
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
    /// On-disk size of the active session package (updated after flushes / detection writes).
    var storedByteSize: Int64 = 0
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastHorizontalAccuracy: Double?
    var lastHeartRate: Double?
    var lastSpeedMps: Double?
    /// Ride-gated session distance (sum of ride meters). Not dock/pause walking.
    var totalDistanceM: Double { liveRideTracker.sessionRideMeters }
    var currentRideDuration: TimeInterval = 0
    var currentInactiveDuration: TimeInterval = 0
    var filterRejectionReason: String?
    var statusText = String(localized: "Idle")
    var errorText: String?
    var healthAuthStatus = "unknown"
    var locationAuthStatus = "unknown"
    var motionAvailability = "unknown"
    /// Structured gate states for Watch permissions onboarding.
    var locationPermission: WatchPermissionState = .notDetermined
    var healthPermission: WatchPermissionState = .notDetermined
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

    var areRecordingPermissionsReady: Bool {
        WatchPermissionOrder.areAllReady(permissionStates)
    }

    /// `workout` when HK session started; `sensorsOnly` when Health denied / simulator fallback.
    var recordingMode = "none"
    /// Mirrors `WKInterfaceDevice.current().isWaterLockEnabled` (refreshed by controls UI).
    var isWaterLockEnabled = false
    var motionRecordingEnabled = false

    var isUnsure: Bool { detectionCode == DetectionCodes.unsure }
    var rideCount: Int { liveRideTracker.rideCount }
    var currentRideSpeedKmh: Double? { liveRideTracker.currentSpeedKmh }
    var currentRideLapCount: Int { liveRideTracker.currentRideLapCount }
    var lastRideLapCount: Int { liveRideTracker.lastRideLapCount }
    /// Live meters while riding; frozen last-ride meters when inactive (`0 m` before first ride).
    var displayRideMeters: Double {
        liveRideTracker.isRideOngoing
            ? liveRideTracker.currentRideMeters
            : liveRideTracker.lastRideMeters
    }
    var lastRideMeters: Double { liveRideTracker.lastRideMeters }
    var lastRideDuration: TimeInterval { liveRideTracker.lastRideDuration }
    var didCompleteRide: Bool { liveRideTracker.didCompleteRide }
    var isRideOngoing: Bool { liveRideTracker.isRideOngoing }
    /// Ultra water-temp hardware present. Drives hide vs `- C` on inactive overview.
    var waterTemperatureAvailable = false
    /// Running mean of persisted submerged samples this session.
    var averageWaterTemperatureCelsius: Double?

    /// Debug-only: force pause/ride UI, or leave live detection (`detected`).
    var detectionSimulationMode: DetectionSimulationMode = .detected

    var liveRideTracker = LiveRideTracker()
    let healthStore = HKHealthStore()
    var workoutSession: HKWorkoutSession?
    var workoutBuilder: HKLiveWorkoutBuilder?
    var workoutDataSource: HKLiveWorkoutDataSource?
    var workoutConfiguration: HKWorkoutConfiguration?
    var workoutRouteBuilder: HKWorkoutRouteBuilder?
    /// True while an HK ride activity is open (ended on detection `inactive`).
    var hkRideActivityOpen = false
    var workoutStoppedContinuation: CheckedContinuation<Date, Never>?
    var workoutRunningContinuation: CheckedContinuation<Void, Never>?
    var hkRideDistanceMeters = 0.0
    var hkRideDistanceAnchorMeters = 0.0
    /// Ride windows for HealthKit distance samples and interval metadata.
    var hkRides: [HKRideMetric] = []
    var hkRideStartedAt: Date?
    var hkGpsFilter = GpsSignalFilter()
    var hkPreviousUsableSpeedMps: Double?
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
    var lastPersistedWaterTempAt: Date?
    var lastLoggedWaterTempC: Double?
    var waterTempNeedsBoutSample = false
    var waterTempSum = 0.0
    var waterTempCount = 0
    var detectionEngine = DetectionEngine()
    var locationBuffer: [LocationSample] = []
    var motionBuffer: [MotionSample] = []
    var healthBuffer: [HealthMetricSample] = []
    /// Recent GPS fixes for backdating live ride meters on `ride_enter`.
    var recentLocationRing: [LocationSample] = []
    var sensorSamplingDense = false
    var flushTask: Task<Void, Never>?
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
    #if RPPL_WEATHERKIT
    var airWeatherSnapshot: AirWeatherSnapshot?
    var airWeatherFetchTask: Task<Void, Never>?
    var airWeatherAttempted = false
    #endif

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
        refreshPermissionStatus()

        if CMWaterSubmersionManager.waterSubmersionAvailable {
            let manager = CMWaterSubmersionManager()
            manager.delegate = self
            waterManager = manager
            waterTemperatureAvailable = true
        }
    }

}
