import Foundation
import RpplCore

/// Launch with `-rpplUITest` (Debug builds only) for a frozen clock and a known Watch logbook.
/// Wipes the Watch session store, so it must never exist in Release.
/// `-rpplUITestSummary` also shows the end-of-session summary.
/// `-rpplUITestSession riding|inactive` shows the live recording screen about an hour into a park day.
enum UITestFixtures {
    #if DEBUG
    static let isActive = ProcessInfo.processInfo.arguments.contains("-rpplUITest")
    #else
    static let isActive = false
    #endif

    /// Saturday 15 Aug 2026 12:30 Amsterdam, same as the iPhone fixtures.
    static let now = Date(timeIntervalSince1970: 1_786_789_800)

    /// Hours before `now` that each seeded session ended.
    private static let endedHoursAgo: [Double] = [22, 70, 190]

    static func seed() {
        #if DEBUG
        AppClock.override = now
        let store = SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
        try? FileManager.default.removeItem(at: store.rootURL)
        try? store.ensureRootExists()

        guard let url = Bundle.main.url(forResource: ExampleSessionPreload.resourceName, withExtension: "json", subdirectory: "Exports")
                ?? Bundle.main.url(forResource: ExampleSessionPreload.resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let example = try? SessionImportLimits.decodeTransferPackage(from: data) else { return }
        var firstId: String?
        for hours in endedHoursAgo {
            var package = SessionTimelineRebase.package(example, soEndedAt: now.addingTimeInterval(-hours * 3600))
            package.manifest.sessionId = UUID().uuidString
            package.manifest.activityCode = ActivityCodes.wakeboard
            package.manifest.parkId = "project7-rotterdam"
            package.manifest.parkIdSource = SessionParkSource.auto
            try? store.importTransferPackage(package, intoPhoneStore: store.rootURL)
            firstId = firstId ?? package.manifest.sessionId
        }

        if ProcessInfo.processInfo.arguments.contains("-rpplUITestSummary"), let firstId {
            WatchSessionController.shared.endedSessionSummary = EndedSessionSummary(
                sessionId: firstId, duration: 5_400, setCount: 4, distanceMeters: 6_800,
                lastSetDuration: 1_100, lastSetMeters: 1_700, lastSetLapCount: 2, didCompleteSet: true,
                startLatitude: nil, startLongitude: nil
            )
        }

        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-rpplUITestSession"), args.indices.contains(flag + 1) {
            seedLiveSession(riding: args[flag + 1] == "riding")
        }
        #endif
    }

    #if DEBUG
    /// Three sets of three laps (~6 min, ~2.7 km at 27 km/h) in 63 minutes, driven through the real
    /// `LiveSetTracker`: riding is 5:52 into the third set (just past lap 3), inactive is 30 s after it.
    private static func seedLiveSession(riding: Bool) {
        let session = WatchSessionController.shared
        let sessionStart = now.addingTimeInterval(-3_835)
        let setLength = 365.0
        var tracker = LiveSetTracker()

        func runSet(enter: Double, seconds: Double, finish: Bool) {
            let enterAt = sessionStart.addingTimeInterval(enter)
            let enterEvent = DetectionEvent(
                code: DetectionCodes.riding, timestamp: enterAt, reason: "ui_fixture", detectorId: "ui_fixture"
            )
            tracker.update(currentCode: DetectionCodes.riding, lastConfident: DetectionCodes.riding, events: [enterEvent])
            for second in 0...Int(seconds) {
                tracker.addLocation(circuitFix(at: enterAt.addingTimeInterval(Double(second)), second: second))
            }
            guard finish else { return }
            let exitEvent = DetectionEvent(
                code: DetectionCodes.inactive, timestamp: enterAt.addingTimeInterval(setLength),
                reason: "ui_fixture", detectorId: "ui_fixture"
            )
            tracker.update(currentCode: DetectionCodes.inactive, lastConfident: DetectionCodes.inactive, events: [exitEvent])
        }

        runSet(enter: 720, seconds: setLength, finish: true)
        runSet(enter: 2_460, seconds: setLength, finish: true)
        runSet(enter: 3_440, seconds: riding ? 352 : setLength, finish: !riding)

        session.liveSetTracker = tracker
        session.isRunning = true
        session.lastConfidentCode = riding ? DetectionCodes.riding : DetectionCodes.inactive
        session.detectionCode = session.lastConfidentCode
        session.elapsed = riding ? 3_792 : 3_835
        session.currentSetDuration = riding ? 352 : 0
        session.currentInactiveDuration = riding ? 0 : 30
        session.cumulativeRidingDuration = riding ? 2 * setLength : 3 * setLength
        session.cumulativeInactiveDuration = 2_710
        session.lastHeartRate = riding ? 151 : 118
        session.activeEnergyKilocalories = riding ? 231 : 237
        session.basalEnergyKilocalories = riding ? 101 : 102
        session.waterTemperatureAvailable = true
        session.averageWaterTemperatureCelsius = 20.8
    }

    /// One fix per second along a 275 x 137.5 m rectangle (825 m, 110 s per lap) at 7.5 m/s.
    private static func circuitFix(at timestamp: Date, second: Int) -> LocationSample {
        let width = 275.0, height = 137.5, perimeter = 2 * (width + height), speed = 7.5
        let s = (Double(second) * speed).truncatingRemainder(dividingBy: perimeter)
        let x: Double, y: Double
        switch s {
        case ..<width: (x, y) = (s, 0)
        case ..<(width + height): (x, y) = (width, s - width)
        case ..<(2 * width + height): (x, y) = (width - (s - width - height), height)
        default: (x, y) = (0, perimeter - s)
        }
        let originLat = 51.97, originLon = 4.50, metersPerDegree = 111_320.0
        return LocationSample(
            timestamp: timestamp,
            latitude: originLat + y / metersPerDegree,
            longitude: originLon + x / (metersPerDegree * cos(originLat * .pi / 180)),
            horizontalAccuracy: 5,
            speed: speed
        )
    }
    #endif
}
