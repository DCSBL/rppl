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

    /// Saturday 15 Aug 2026 12:30 Amsterdam, the day after the bundled tracked demo session.
    /// `-rpplUITestNow <epoch>` freezes another moment (e.g. a winter weekday for closed parks).
    static let now: Date = {
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-rpplUITestNow"), args.indices.contains(flag + 1),
           let epoch = TimeInterval(args[flag + 1]) {
            return Date(timeIntervalSince1970: epoch)
        }
        return Date(timeIntervalSince1970: 1_786_789_800)
    }()

    private struct Ride {
        let parkId: String
        let daysAgo: Int
        let hour: Int
        let sets: Int
        let laps: Int
    }

    private static let manualRides = [
        GeneratedRide(ride: Ride(parkId: "lakeside-zwolle", daysAgo: 3, hour: 18, sets: 5, laps: 9), minutes: 95, airCelsius: 24, waterCelsius: 20),
        GeneratedRide(ride: Ride(parkId: "wakepark-groningen", daysAgo: 9, hour: 14, sets: 4, laps: 7), minutes: 80, airCelsius: 19, waterCelsius: 18),
        GeneratedRide(ride: Ride(parkId: "project7-rotterdam", daysAgo: 21, hour: 11, sets: 6, laps: 12), minutes: 110, airCelsius: 26, waterCelsius: 21),
    ]

    /// `-rpplUITestSessions N`: a logbook of N sessions (the tracked demo session plus N-1 manual ones) instead of the default (0 = empty).
    private static var generatedCount: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-rpplUITestSessions"), args.indices.contains(flag + 1) else { return nil }
        return Int(args[flag + 1])
    }

    /// Realistic summer Dutch park days: every 3-4 days, 6-16 laps of ~850 m, air 17-27 °C, water 16-22 °C.
    private static func generatedRides(count: Int) -> [GeneratedRide] {
        let parkIds = ["lakeside-zwolle", "wakepark-groningen", "project7-rotterdam"]
        // from 1: the tracked demo session already sits on day 1
        return (1..<max(count, 1)).map { i in
            let wave = sin(Double(i) * 1.7)
            let laps = 11 + Int((wave * 5).rounded())
            return GeneratedRide(
                ride: Ride(parkId: parkIds[i % parkIds.count], daysAgo: 1 + i * 3 + i % 2, hour: i % 2 == 0 ? 18 : 11, sets: max(2, laps / 2), laps: laps),
                minutes: 90 + (i * 17) % 60,
                airCelsius: 22 + wave * 5 - Double(i) * 0.1,
                waterCelsius: 19 + wave * 2 - Double(i) * 0.05
            )
        }
    }

    private struct GeneratedRide {
        let ride: Ride
        let minutes: Int
        let airCelsius: Double
        let waterCelsius: Double
    }

    /// The bundled example (a real Watch session at Project7 Rotterdam) imported as an ordinary
    /// tracked wakeboard session, so the logbook never shows the "Example session" label.
    private static func importTrackedDemo(into store: SessionFileStore) {
        guard let url = Bundle.main.url(forResource: ExampleSessionPreload.resourceName, withExtension: "json", subdirectory: "Exports")
            ?? Bundle.main.url(forResource: ExampleSessionPreload.resourceName, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            var package = try? SessionImportLimits.decodeTransferPackage(from: data) else { return }
        package.manifest.activityCode = ActivityCodes.wakeboard
        package.manifest.parkId = "project7-rotterdam"
        package.manifest.parkIdSource = SessionParkSource.auto
        package.manifest.weather = SessionWeather(temperatureCelsius: 23, humidityPercent: 58, windSpeedKmh: 14, windDirectionDegrees: 250)
        package.manifest.waterTemperatureEstimate = ParkWaterTemperature(
            celsius: 20, observedAt: package.manifest.startedAt, stationName: "Mock", providerName: "Mock"
        )
        try? store.importExportedPackage(package, intoPhoneStore: store.rootURL, importedAt: now)
    }

    static func seed() {
        #if DEBUG
        AppClock.override = now
        let store = PhoneConnectivityService.shared.store
        let fm = FileManager.default
        try? fm.removeItem(at: store.rootURL)
        try? store.ensureRootExists()

        let count = generatedCount
        if count != 0 { importTrackedDemo(into: store) }

        let parks = ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot)
        let rides = count.map(generatedRides) ?? manualRides
        for item in rides {
            let ride = item.ride
            guard let park = parks.first(where: { $0.id == ride.parkId }) else { continue }
            let day = now.addingTimeInterval(-Double(ride.daysAgo) * 86_400)
            let start = Calendar.current.date(bySettingHour: ride.hour, minute: 0, second: 0, of: day) ?? day
            let manifest = SessionManifest(
                testerId: "ui-test", appVersion: "1.0", buildNumber: "1", watchModel: "none",
                systemVersion: "26.0", startedAt: start, endedAt: start.addingTimeInterval(Double(item.minutes) * 60),
                transferState: .acknowledged, activityCode: ActivityCodes.wakeboard,
                weather: SessionWeather(temperatureCelsius: item.airCelsius, humidityPercent: 60),
                waterTemperatureEstimate: ParkWaterTemperature(
                    celsius: item.waterCelsius, observedAt: start, stationName: "Mock", providerName: "Mock"
                ),
                parkId: ride.parkId, parkIdSource: SessionParkSource.manual,
                manual: ManualEntry(
                    tallies: [.init(sets: ride.sets, laps: ride.laps)],
                    distanceM: Double(ride.laps) * 850,
                    location: park.location
                )
            )
            try? store.saveManual(manifest, label: park.compactName)
        }
        PhoneConnectivityService.shared.bumpSessionsRevision()
        #endif
    }
}
