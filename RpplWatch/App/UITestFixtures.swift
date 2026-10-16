import Foundation
import RpplCore

/// Launch with `-rpplUITest` (Debug builds only) for a frozen clock and a known Watch logbook.
/// Wipes the Watch session store, so it must never exist in Release.
/// `-rpplUITestSummary` also shows the end-of-session summary.
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
        #endif
    }
}
