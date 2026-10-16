import Foundation
import RpplCore

/// Launch with `-rpplUITest` (Debug builds only) for a frozen clock and a known logbook.
/// Wipes the phone session store, so it must never exist in Release.
enum UITestFixtures {
    #if DEBUG
    static let isActive = ProcessInfo.processInfo.arguments.contains("-rpplUITest")
    #else
    static let isActive = false
    #endif

    /// Saturday 15 Aug 2026 12:30 Amsterdam, the day after the bundled example session.
    static let now = Date(timeIntervalSince1970: 1_786_789_800)

    private struct Ride {
        let parkId: String
        let daysAgo: Int
        let hour: Int
        let sets: Int
        let laps: Int
    }

    private static let manualRides = [
        Ride(parkId: "lakeside-zwolle", daysAgo: 3, hour: 18, sets: 5, laps: 9),
        Ride(parkId: "wakepark-groningen", daysAgo: 9, hour: 14, sets: 4, laps: 7),
        Ride(parkId: "project7-rotterdam", daysAgo: 21, hour: 11, sets: 6, laps: 12),
    ]

    static func seed() {
        #if DEBUG
        AppClock.override = now
        let store = PhoneConnectivityService.shared.store
        let fm = FileManager.default
        try? fm.removeItem(at: store.rootURL)
        try? store.ensureRootExists()

        if let url = Bundle.main.url(forResource: ExampleSessionPreload.resourceName, withExtension: "json", subdirectory: "Exports")
            ?? Bundle.main.url(forResource: ExampleSessionPreload.resourceName, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let package = try? SessionImportLimits.decodeTransferPackage(from: data) {
            try? store.importExportedPackage(package, intoPhoneStore: store.rootURL, importedAt: now)
        }

        let parks = ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot)
        for ride in manualRides {
            guard let park = parks.first(where: { $0.id == ride.parkId }) else { continue }
            let day = now.addingTimeInterval(-Double(ride.daysAgo) * 86_400)
            let start = Calendar.current.date(bySettingHour: ride.hour, minute: 0, second: 0, of: day) ?? day
            let manifest = SessionManifest(
                testerId: "ui-test", appVersion: "1.0", buildNumber: "1", watchModel: "none",
                systemVersion: "26.0", startedAt: start, endedAt: start.addingTimeInterval(5_400),
                transferState: .acknowledged, activityCode: ActivityCodes.wakeboard,
                parkId: ride.parkId, parkIdSource: SessionParkSource.manual,
                manual: ManualEntry(tallies: [.init(sets: ride.sets, laps: ride.laps)], location: park.location)
            )
            try? store.saveManual(manifest, label: park.compactName)
        }
        PhoneConnectivityService.shared.bumpSessionsRevision()
        #endif
    }
}
