import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func manifest(endedAt: Date? = nil, waterTemperatureAvailable: Bool? = nil) -> SessionManifest {
    SessionManifest(
        sessionId: "test-session",
        testerId: "tester",
        appVersion: "1.0",
        buildNumber: "1",
        watchModel: "Watch",
        systemVersion: "11.0",
        startedAt: t0,
        endedAt: endedAt,
        transferState: .acknowledged,
        waterTemperatureAvailable: waterTemperatureAvailable
    )
}

private func detection(
    code: String,
    at offset: TimeInterval,
    id: String = UUID().uuidString,
    supersedesId: String? = nil
) -> DetectionEvent {
    DetectionEvent(
        id: id,
        code: code,
        timestamp: t0.addingTimeInterval(offset),
        reason: code,
        detectorId: "test",
        supersedesId: supersedesId
    )
}

private func location(
    at offset: TimeInterval,
    lat: Double,
    lon: Double,
    accuracy: Double = 10,
    speedMps: Double? = 5
) -> LocationSample {
    LocationSample(
        timestamp: t0.addingTimeInterval(offset),
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: accuracy,
        speed: speedMps
    )
}

private func waterSample(at offset: TimeInterval, celsius: Double) -> WaterTemperatureSample {
    WaterTemperatureSample(timestamp: t0.addingTimeInterval(offset), celsius: celsius)
}

@Suite("GeoDistance")
struct GeoDistanceTests {
    @Test func haversineShortStep() {
        // ~111 m per 0.001° latitude at equator
        let meters = GeoDistance.meters(fromLat: 52.0, fromLon: 5.0, toLat: 52.001, toLon: 5.0)
        #expect(meters > 100)
        #expect(meters < 120)
    }

    @Test func rejectsBadAccuracy() {
        let from = location(at: 0, lat: 52.0, lon: 5.0, accuracy: 10)
        let to = location(at: 1, lat: 52.001, lon: 5.0, accuracy: 40)
        #expect(!GeoDistance.acceptsStep(from: from, to: to, maxHorizontalAccuracyM: 25))
    }

    @Test func rejectsImpliedSpeedAbovePlausible() {
        // ~24 m in 1 s ≈ 86 km/h implied; above the 80 km/h ceiling.
        let from = location(
            at: 0,
            lat: 52.0,
            lon: 5.0,
            speedMps: SpeedUnits.metersPerSecond(fromKilometersPerHour: 85)
        )
        let to = location(
            at: 1,
            lat: 52.00022,
            lon: 5.0,
            speedMps: SpeedUnits.metersPerSecond(fromKilometersPerHour: 85)
        )
        let step = GeoDistance.meters(
            fromLat: from.latitude,
            fromLon: from.longitude,
            toLat: to.latitude,
            toLon: to.longitude
        )
        #expect(step > 15)
        #expect(step < 50)
        #expect(!GeoDistance.acceptsStep(from: from, to: to, maxHorizontalAccuracyM: 25))
    }

    @Test func acceptsPlausibleRideStep() {
        let from = location(at: 0, lat: 52.0, lon: 5.0, speedMps: 8)
        let to = location(at: 1, lat: 52.00005, lon: 5.0, speedMps: 8)
        #expect(GeoDistance.acceptsStep(from: from, to: to, maxHorizontalAccuracyM: 25))
    }
}

@Suite("DistanceFormat")
struct DistanceFormatTests {
    @Test func dutchLocaleUsesGrouping() {
        let formatted = DistanceFormat.meters(1234, locale: Locale(identifier: "nl_NL"))
        #expect(formatted.contains("m"))
        #expect(formatted.contains("1") && formatted.contains("234"))
    }

    @Test func kilometersUsesLocaleUnit() {
        let en = DistanceFormat.kilometers(2500, locale: Locale(identifier: "en_US"))
        #expect(en.lowercased().contains("mi"))
        let nl = DistanceFormat.kilometers(2500, locale: Locale(identifier: "nl_NL"))
        #expect(nl.lowercased().contains("km"))
    }

    @Test func usLocaleUsesImperialUnits() {
        let us = Locale(identifier: "en_US")
        #expect(DistanceFormat.meters(100, locale: us).contains("ft"))
        #expect(DistanceFormat.kilometers(1609.344, locale: us).contains("mi"))
        let mph = DistanceFormat.kilometersPerHour(16.09344, locale: us)
        #expect(mph.contains("10.0") && mph.lowercased().contains("mph"))
        #expect(DistanceFormat.speedUnitSymbol(locale: us).lowercased() == "mph")
        #expect(DistanceFormat.speedUnitSymbol(locale: Locale(identifier: "nl_NL")).lowercased().hasPrefix("km/"))
    }

    @Test func speedUsesLocaleUnit() {
        let formatted = DistanceFormat.kilometersPerHour(24.5, locale: Locale(identifier: "nl_NL"))
        #expect(formatted.contains("24"))
    }
}

@Suite("DurationFormat")
struct DurationFormatTests {
    @Test func wideSingleMinuteUsesLocaleWord() {
        let en = DurationFormat.units(60, width: .wide, locale: Locale(identifier: "en_US"))
        #expect(en.contains("minute"))
        let nl = DurationFormat.units(60, width: .wide, locale: Locale(identifier: "nl_NL"))
        #expect(nl.lowercased().contains("minuut") || nl.lowercased().contains("min"))
    }

    @Test func zeroIsNonEmpty() {
        #expect(!DurationFormat.units(0, width: .wide, locale: Locale(identifier: "en_US")).isEmpty)
    }
}

@Suite("EnergyFormat")
struct EnergyFormatTests {
    @Test func kilocaloriesIncludesUnit() {
        let formatted = EnergyFormat.kilocalories(120, locale: Locale(identifier: "en_US"))
        #expect(formatted.contains("120"))
        #expect(formatted.lowercased().contains("cal") || formatted.lowercased().contains("kcal"))
    }
}

@Suite("TemperatureFormat")
struct TemperatureFormatTests {
    @Test func metricLocaleKeepsCelsius() {
        let formatted = TemperatureFormat.celsius(21.4, locale: Locale(identifier: "nl_NL"))
        #expect(formatted.contains("21") && formatted.contains("C"))
    }

    @Test func usLocaleConvertsToFahrenheit() {
        let formatted = TemperatureFormat.celsius(20, locale: Locale(identifier: "en_US"))
        #expect(formatted.contains("68") && formatted.contains("F"))
    }
}

@Suite("SessionStatsBuilder")
struct SessionStatsBuilderTests {
    @Test func emptyDetectionsZeroStats() {
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(600)),
            detections: [detection(code: DetectionCodes.inactive, at: 0, id: "start")],
            locations: [],
            health: []
        )
        #expect(stats.setCount == 0)
        #expect(stats.totalDistanceMeters == 0)
        #expect(stats.ridingDuration == 0)
        #expect(stats.inactiveDuration == 600)
    }

    @Test func singleRideDistanceAndDuration() {
        let detections = [
            detection(code: DetectionCodes.inactive, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.inactive, at: 100, id: "p1"),
        ]
        let locations = [
            location(at: 20, lat: 52.0, lon: 5.0, speedMps: 5),
            location(at: 21, lat: 52.0001, lon: 5.0, speedMps: 8),
            location(at: 22, lat: 52.0002, lon: 5.0, speedMps: 6),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(200)),
            detections: detections,
            locations: locations,
            health: []
        )
        #expect(stats.setCount == 1)
        #expect(stats.sets.count == 1)
        #expect(stats.sets[0].duration == 90)
        #expect(stats.sets[0].distanceMeters > 10)
        #expect(stats.sets[0].peakSpeedKmh != nil)
        #expect(abs((stats.sets[0].peakSpeedKmh ?? 0) - SpeedUnits.kilometersPerHour(fromMetersPerSecond: 8)) < 0.5)
        #expect(stats.maxSpeedKmh != nil)
        #expect(stats.averageSpeedKmh != nil)
        #expect(stats.ridingDuration == 90)
        #expect(stats.inactiveDuration == 110)
        #expect(abs(stats.ridingInactiveRatio - 90.0 / 200.0) < 0.001)
    }

    @Test func twoRidesFromInactiveBetween() {
        let detections = [
            detection(code: DetectionCodes.inactive, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.inactive, at: 50, id: "p1"),
            detection(code: DetectionCodes.riding, at: 100, id: "r2"),
            detection(code: DetectionCodes.inactive, at: 150, id: "p2"),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(200)),
            detections: detections,
            locations: [],
            health: []
        )
        #expect(stats.setCount == 2)
        #expect(stats.sets.count == 2)
    }

    @Test func supersededUnsureMergesIntoOneRide() {
        let unsureId = "unsure-1"
        let detections = [
            detection(code: DetectionCodes.inactive, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.unsure, at: 30, id: unsureId),
            detection(
                code: DetectionCodes.riding,
                at: 45,
                id: "lookback",
                supersedesId: unsureId
            ),
            detection(code: DetectionCodes.inactive, at: 100, id: "p1"),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(120)),
            detections: detections,
            locations: [],
            health: []
        )
        #expect(stats.setCount == 1)
        #expect(stats.sets[0].duration == 90)
    }

    @Test func timedOutUnsureEndsRideAtGap() {
        // Unsure without lookback supersede: set ends at unsure (not attributed riding).
        let detections = [
            detection(code: DetectionCodes.inactive, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.unsure, at: 40, id: "u1"),
            detection(code: DetectionCodes.inactive, at: 100, id: "p1"),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(120)),
            detections: detections,
            locations: [],
            health: []
        )
        #expect(stats.setCount == 1)
        #expect(stats.sets[0].duration == 30)
        #expect(stats.ridingDuration == 30)
    }

    @Test func caloriesUsesMaxCumulative() {
        let health = [
            HealthMetricSample(timestamp: t0.addingTimeInterval(10), activeEnergyKilocalories: 50),
            HealthMetricSample(timestamp: t0.addingTimeInterval(100), activeEnergyKilocalories: 180),
            HealthMetricSample(timestamp: t0.addingTimeInterval(200), activeEnergyKilocalories: 120),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(300)),
            detections: [detection(code: DetectionCodes.inactive, at: 0, id: "s")],
            locations: [],
            health: health
        )
        #expect(stats.activeEnergyKilocalories == 180)
        #expect(stats.totalEnergyKilocalories == 180)
    }

    @Test func totalCaloriesSumsActiveAndBasal() {
        let health = [
            HealthMetricSample(
                timestamp: t0.addingTimeInterval(10),
                activeEnergyKilocalories: 100,
                basalEnergyKilocalories: 40
            ),
            HealthMetricSample(
                timestamp: t0.addingTimeInterval(100),
                activeEnergyKilocalories: 200,
                basalEnergyKilocalories: 80
            ),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(300)),
            detections: [detection(code: DetectionCodes.inactive, at: 0, id: "s")],
            locations: [],
            health: health
        )
        #expect(stats.activeEnergyKilocalories == 200)
        #expect(stats.totalEnergyKilocalories == 280)
    }

    @Test func openRideClosedAtSessionEnd() {
        let detections = [
            detection(code: DetectionCodes.inactive, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(100)),
            detections: detections,
            locations: [],
            health: []
        )
        #expect(stats.setCount == 1)
        #expect(stats.sets[0].endedAt == t0.addingTimeInterval(100))
    }

    @Test func waterTemperatureAveragesAllSamples() {
        let detections = [
            detection(code: DetectionCodes.inactive, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.inactive, at: 50, id: "p1"),
        ]
        let water = [
            waterSample(at: 5, celsius: 18),
            waterSample(at: 20, celsius: 20),
            waterSample(at: 60, celsius: 22),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(80), waterTemperatureAvailable: true),
            detections: detections,
            locations: [],
            health: [],
            water: water
        )
        #expect(stats.waterTemperatureAvailable)
        #expect(stats.averageWaterTemperatureCelsius == 20)
    }

    @Test func missingCapabilityHidesWaterTemperature() {
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(60)),
            detections: [detection(code: DetectionCodes.inactive, at: 0, id: "s")],
            locations: [],
            health: [],
            water: []
        )
        #expect(!stats.waterTemperatureAvailable)
        #expect(stats.averageWaterTemperatureCelsius == nil)
    }

    @Test func capableWithoutSamplesLeavesAverageNil() {
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(60), waterTemperatureAvailable: true),
            detections: [detection(code: DetectionCodes.inactive, at: 0, id: "s")],
            locations: [],
            health: [],
            water: []
        )
        #expect(stats.waterTemperatureAvailable)
        #expect(stats.averageWaterTemperatureCelsius == nil)
    }

    @Test func shortSetFlagsFallDetected() {
        // 90 s riding window, well under the 150 s cutoff.
        let detections = [
            detection(code: DetectionCodes.inactive, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.inactive, at: 100, id: "p1"),
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(120)),
            detections: detections,
            locations: [],
            health: []
        )
        #expect(stats.sets[0].fallDetected)
        #expect(stats.fallCount == 1)
    }

    /// Regression guard for the bug this design replaced: a full-length set ending in a sharp
    /// GPS speed cliff (a normal cable dismount) must not be flagged just because of that cliff.
    @Test func longSetWithSpeedCliffDoesNotFlagFallDetected() {
        let detections = [
            detection(code: DetectionCodes.inactive, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.inactive, at: 250, id: "p1"),
        ]
        let locations = [
            location(at: 240, lat: 52.0, lon: 5.0, speedMps: 8.3), // ~30 km/h cable speed
            location(at: 241, lat: 52.0001, lon: 5.0, speedMps: 1.4), // ~5 km/h: a normal dismount
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(260)),
            detections: detections,
            locations: locations,
            health: []
        )
        #expect(!stats.sets[0].fallDetected)
        #expect(stats.fallCount == 0)
    }

    @Test func fallCountSumsOnlyShortSetsAcrossSession() {
        let detections = [
            detection(code: DetectionCodes.inactive, at: 0, id: "s"),
            detection(code: DetectionCodes.riding, at: 10, id: "r1"),
            detection(code: DetectionCodes.inactive, at: 50, id: "p1"), // set 1: 40 s
            detection(code: DetectionCodes.riding, at: 100, id: "r2"),
            detection(code: DetectionCodes.inactive, at: 400, id: "p2"), // set 2: 300 s
        ]
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(450)),
            detections: detections,
            locations: [],
            health: []
        )
        #expect(stats.sets.count == 2)
        #expect(stats.sets[0].fallDetected)
        #expect(!stats.sets[1].fallDetected)
        #expect(stats.fallCount == 1)
    }
}

@Suite("SessionStats.fallCount")
struct SessionStatsFallCountTests {
    private func set(index: Int, fallDetected: Bool) -> SetSegmentStats {
        SetSegmentStats(
            index: index,
            startedAt: t0,
            endedAt: t0.addingTimeInterval(60),
            duration: 60,
            distanceMeters: 300,
            fallDetected: fallDetected
        )
    }

    private func stats(sets: [SetSegmentStats]) -> SessionStats {
        SessionStats(
            startedAt: t0,
            endedAt: t0.addingTimeInterval(600),
            totalDuration: 600,
            totalDistanceMeters: sets.reduce(0) { $0 + $1.distanceMeters },
            activeEnergyKilocalories: nil,
            setCount: sets.count,
            ridingDuration: 300,
            inactiveDuration: 300,
            ridingInactiveRatio: 0.5,
            sets: sets
        )
    }

    @Test func zeroWhenNoSetsFlagged() {
        #expect(stats(sets: [set(index: 1, fallDetected: false), set(index: 2, fallDetected: false)]).fallCount == 0)
    }

    @Test func countsOnlyFlaggedSets() {
        let value = stats(sets: [
            set(index: 1, fallDetected: true),
            set(index: 2, fallDetected: false),
            set(index: 3, fallDetected: true),
        ]).fallCount
        #expect(value == 2)
    }

    @Test func zeroWhenNoSets() {
        #expect(stats(sets: []).fallCount == 0)
    }
}

@Suite("LiveSetTracker")
struct LiveSetTrackerTests {
    @Test func setCountOnEnter() {
        var tracker = LiveSetTracker()
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 10)]
        )
        #expect(tracker.setCount == 1)
        #expect(tracker.isSetOngoing)
    }

    @Test func frozenLastRideMetersWhenInactive() {
        var tracker = LiveSetTracker()
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 0)]
        )
        tracker.addLocation(location(at: 1, lat: 52.0, lon: 5.0))
        tracker.addLocation(location(at: 2, lat: 52.0001, lon: 5.0))
        let meters = tracker.currentSetMeters
        #expect(meters > 0)

        tracker.update(
            currentCode: DetectionCodes.inactive,
            lastConfident: DetectionCodes.inactive,
            events: [detection(code: DetectionCodes.inactive, at: 50)]
        )
        #expect(!tracker.isSetOngoing)
        #expect(tracker.lastSetMeters == meters)
        #expect(tracker.currentSetMeters == 0)
        #expect(tracker.currentSpeedKmh == nil)
    }

    @Test func zeroMetersBeforeFirstRide() {
        let tracker = LiveSetTracker()
        #expect(tracker.lastSetMeters == 0)
        #expect(tracker.setCount == 0)
        #expect(tracker.sessionSetMeters == 0)
    }

    @Test func unsureDoesNotAccrueDistance() {
        var tracker = LiveSetTracker()
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 0)]
        )
        tracker.addLocation(location(at: 1, lat: 52.0, lon: 5.0))
        tracker.addLocation(location(at: 2, lat: 52.0001, lon: 5.0))
        let meters = tracker.currentSetMeters
        #expect(meters > 0)

        tracker.update(
            currentCode: DetectionCodes.unsure,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.unsure, at: 3)]
        )
        #expect(tracker.isSetOngoing)
        tracker.addLocation(location(at: 4, lat: 52.0003, lon: 5.0))
        #expect(tracker.currentSetMeters == meters)
        #expect(tracker.currentSpeedKmh == nil)
        #expect(tracker.sessionSetMeters == meters)
    }

    @Test func sessionSetMetersSumsFinishedRides() {
        var tracker = LiveSetTracker()
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 0)]
        )
        tracker.addLocation(location(at: 1, lat: 52.0, lon: 5.0))
        tracker.addLocation(location(at: 2, lat: 52.0001, lon: 5.0))
        let first = tracker.currentSetMeters

        tracker.update(
            currentCode: DetectionCodes.inactive,
            lastConfident: DetectionCodes.inactive,
            events: [detection(code: DetectionCodes.inactive, at: 10)]
        )
        #expect(tracker.sessionSetMeters == first)

        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 20)]
        )
        tracker.addLocation(location(at: 21, lat: 52.0, lon: 5.0))
        tracker.addLocation(location(at: 22, lat: 52.0001, lon: 5.0))
        #expect(tracker.sessionSetMeters == first + tracker.currentSetMeters)
        #expect(tracker.setCount == 2)
    }

    @Test func lastSetDurationOnFinish() {
        var tracker = LiveSetTracker()
        #expect(!tracker.didCompleteSet)
        #expect(tracker.lastSetDuration == 0)

        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 10)]
        )
        tracker.update(
            currentCode: DetectionCodes.inactive,
            lastConfident: DetectionCodes.inactive,
            events: [detection(code: DetectionCodes.inactive, at: 55)]
        )
        #expect(tracker.didCompleteSet)
        #expect(tracker.lastSetDuration == 45)
        #expect(!tracker.isSetOngoing)
        #expect(tracker.sessionRidingDuration == 45)
    }

    @Test func sessionRidingDurationSumsFinishedRides() {
        var tracker = LiveSetTracker()
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 0)]
        )
        tracker.update(
            currentCode: DetectionCodes.inactive,
            lastConfident: DetectionCodes.inactive,
            events: [detection(code: DetectionCodes.inactive, at: 40)]
        )
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 50)]
        )
        tracker.closeOpenSet(at: t0.addingTimeInterval(80))
        #expect(tracker.sessionRidingDuration == 70)
    }

    @Test func closeOpenSetRecordsDuration() {
        var tracker = LiveSetTracker()
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 0)]
        )
        tracker.closeOpenSet(at: t0.addingTimeInterval(30))
        #expect(tracker.didCompleteSet)
        #expect(tracker.lastSetDuration == 30)
        #expect(tracker.sessionRidingDuration == 30)
        #expect(!tracker.isSetOngoing)
    }

    @Test func resetClearsLastRideDuration() {
        var tracker = LiveSetTracker()
        tracker.update(
            currentCode: DetectionCodes.riding,
            lastConfident: DetectionCodes.riding,
            events: [detection(code: DetectionCodes.riding, at: 0)]
        )
        tracker.update(
            currentCode: DetectionCodes.inactive,
            lastConfident: DetectionCodes.inactive,
            events: [detection(code: DetectionCodes.inactive, at: 20)]
        )
        tracker.reset()
        #expect(!tracker.didCompleteSet)
        #expect(tracker.lastSetDuration == 0)
        #expect(tracker.lastSetMeters == 0)
        #expect(tracker.sessionRidingDuration == 0)
    }
}

@Suite("LocationSpeedStats")
struct LocationSpeedStatsTests {
    @Test func peakIgnoresImplausibleSpike() {
        let locations = [
            location(at: 0, lat: 52.0, lon: 5.0, speedMps: SpeedUnits.metersPerSecond(fromKilometersPerHour: 30)),
            location(at: 1, lat: 52.0, lon: 5.0, speedMps: SpeedUnits.metersPerSecond(fromKilometersPerHour: 85)),
            location(at: 2, lat: 52.0, lon: 5.0, speedMps: SpeedUnits.metersPerSecond(fromKilometersPerHour: 28)),
        ]
        let peak = LocationSpeedStats.peakSpeedKmh(from: locations)
        #expect(peak != nil)
        #expect(abs((peak ?? 0) - 30) < 0.5)
    }

    @Test func sessionPeakUsesRideWindowsOnly() {
        let setLocations = [
            location(at: 10, lat: 52.0, lon: 5.0, speedMps: SpeedUnits.metersPerSecond(fromKilometersPerHour: 32)),
            location(at: 11, lat: 52.0, lon: 5.0, speedMps: SpeedUnits.metersPerSecond(fromKilometersPerHour: 34)),
        ]
        let inactiveSpike = location(
            at: 50,
            lat: 52.0,
            lon: 5.0,
            speedMps: SpeedUnits.metersPerSecond(fromKilometersPerHour: 44)
        )
        let all = setLocations + [inactiveSpike]
        let windows = [(start: t0.addingTimeInterval(10), end: t0.addingTimeInterval(20))]
        let sessionPeak = LocationSpeedStats.peakSpeedKmh(setWindows: windows, locations: all)
        let rawAll = LocationSpeedStats.peakSpeedKmh(from: all)
        #expect(sessionPeak != nil)
        #expect(abs((sessionPeak ?? 0) - 34) < 0.5)
        // Spike during pause is accepted by filter but outside set window → not in session peak.
        #expect(rawAll != nil)
        #expect((rawAll ?? 0) > (sessionPeak ?? 0))
    }

    @Test func averageSpeedMetersPerSecondIsDistanceOverDuration() {
        #expect(
            LocationSpeedStats.averageSpeedMetersPerSecond(distanceMeters: 1000, duration: 50) == 20
        )
        #expect(LocationSpeedStats.averageSpeedMetersPerSecond(distanceMeters: 0, duration: 50) == nil)
        #expect(LocationSpeedStats.averageSpeedMetersPerSecond(distanceMeters: 1000, duration: 0) == nil)
    }
}
