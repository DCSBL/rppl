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

    /// `-rpplUITestSessions N`: N generated manual sessions instead of the default logbook (season chart tests).
    private static var generatedCount: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-rpplUITestSessions"), args.indices.contains(flag + 1) else { return nil }
        return Int(args[flag + 1])
    }

    /// Realistic summer Dutch park days: every 3-4 days, 6-16 laps of ~850 m, air 17-27 °C, water 16-22 °C.
    private static func generatedRides(count: Int) -> [GeneratedRide] {
        let parkIds = ["lakeside-zwolle", "wakepark-groningen", "project7-rotterdam"]
        return (0..<count).map { i in
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

    static func seed() {
        #if DEBUG
        AppClock.override = now
        let store = PhoneConnectivityService.shared.store
        let fm = FileManager.default
        try? fm.removeItem(at: store.rootURL)
        try? store.ensureRootExists()

        let generated = generatedCount.map(generatedRides)
        if generated == nil, let url = Bundle.main.url(forResource: ExampleSessionPreload.resourceName, withExtension: "json", subdirectory: "Exports")
            ?? Bundle.main.url(forResource: ExampleSessionPreload.resourceName, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let package = try? SessionImportLimits.decodeTransferPackage(from: data) {
            try? store.importExportedPackage(package, intoPhoneStore: store.rootURL, importedAt: now)
        }

        let parks = ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot)
        let rides = generated ?? manualRides.map { GeneratedRide(ride: $0, minutes: 90, airCelsius: 0, waterCelsius: 0) }
        for item in rides {
            let ride = item.ride
            guard let park = parks.first(where: { $0.id == ride.parkId }) else { continue }
            let day = now.addingTimeInterval(-Double(ride.daysAgo) * 86_400)
            let start = Calendar.current.date(bySettingHour: ride.hour, minute: 0, second: 0, of: day) ?? day
            let manifest = SessionManifest(
                testerId: "ui-test", appVersion: "1.0", buildNumber: "1", watchModel: "none",
                systemVersion: "26.0", startedAt: start, endedAt: start.addingTimeInterval(Double(item.minutes) * 60),
                transferState: .acknowledged, activityCode: ActivityCodes.wakeboard,
                weather: generated == nil ? nil : SessionWeather(temperatureCelsius: item.airCelsius, humidityPercent: 60),
                waterTemperatureEstimate: generated == nil ? nil : ParkWaterTemperature(
                    celsius: item.waterCelsius, observedAt: start, stationName: "Mock", providerName: "Mock"
                ),
                parkId: ride.parkId, parkIdSource: SessionParkSource.manual,
                manual: ManualEntry(
                    tallies: [.init(sets: ride.sets, laps: ride.laps)],
                    distanceM: generated == nil ? nil : Double(ride.laps) * 850,
                    location: park.location
                )
            )
            try? store.saveManual(manifest, label: park.compactName)
        }
        PhoneConnectivityService.shared.bumpSessionsRevision()
        #endif
    }
}
