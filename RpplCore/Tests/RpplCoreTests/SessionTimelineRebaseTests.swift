import Foundation
import Testing
@testable import RpplCore

@Suite("SessionTimelineRebase")
struct SessionTimelineRebaseTests {
    @Test func packageShiftsEndToNowKeepingRelativeGaps() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let mid = start.addingTimeInterval(3_600)
        let end = start.addingTimeInterval(7_200)
        let now = Date(timeIntervalSince1970: 2_000_000)

        let package = SessionTransferPackage(
            manifest: SessionManifest(
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "Watch7,1",
                systemVersion: "26.0",
                startedAt: start,
                endedAt: end,
                activityCode: "Example session"
            ),
            detections: [
                DetectionEvent(
                    code: DetectionCodes.inactive,
                    timestamp: start,
                    reason: "session_start",
                    detectorId: "session_start"
                ),
                DetectionEvent(
                    code: DetectionCodes.riding,
                    timestamp: mid,
                    reason: "ride_enter",
                    detectorId: "ride_enter"
                ),
            ],
            locations: [
                LocationSample(
                    timestamp: start,
                    latitude: 1,
                    longitude: 2,
                    horizontalAccuracy: 5
                ),
                LocationSample(
                    timestamp: end,
                    latitude: 1.1,
                    longitude: 2.1,
                    horizontalAccuracy: 5
                ),
            ],
            health: [
                HealthMetricSample(timestamp: mid, heartRateBPM: 120),
            ],
            water: [
                WaterTemperatureSample(timestamp: mid, celsius: 18),
            ],
            battery: [
                BatterySample(timestamp: mid, level: 0.87, state: BatteryStateCodes.unplugged),
            ]
        )

        let shifted = SessionTimelineRebase.package(package, soEndedAt: now)

        #expect(shifted.manifest.endedAt == now)
        #expect(shifted.manifest.startedAt == now.addingTimeInterval(-7_200))
        #expect(shifted.detections[0].timestamp == now.addingTimeInterval(-7_200))
        #expect(shifted.detections[1].timestamp == now.addingTimeInterval(-3_600))
        #expect(shifted.locations[0].timestamp == now.addingTimeInterval(-7_200))
        #expect(shifted.locations[1].timestamp == now)
        #expect(shifted.health[0].timestamp == now.addingTimeInterval(-3_600))
        #expect(shifted.water[0].timestamp == now.addingTimeInterval(-3_600))
        #expect(shifted.battery[0].timestamp == now.addingTimeInterval(-3_600))
        // Non-time fields untouched.
        #expect(shifted.locations[0].latitude == 1)
        #expect(shifted.locations[0].longitude == 2)
        #expect(shifted.health[0].heartRateBPM == 120)
        #expect(shifted.water[0].celsius == 18)
        #expect(shifted.battery[0].level == 0.87)
        #expect(shifted.battery[0].state == BatteryStateCodes.unplugged)
        #expect(shifted.manifest.activityCode == "Example session")
    }

    @Test func zeroDeltaReturnsIdenticalPackage() {
        let end = Date(timeIntervalSince1970: 5_000)
        let package = SessionTransferPackage(
            manifest: SessionManifest(
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "Watch7,1",
                systemVersion: "26.0",
                startedAt: end.addingTimeInterval(-60),
                endedAt: end
            ),
            locations: [],
            health: []
        )
        let shifted = SessionTimelineRebase.package(package, soEndedAt: end)
        #expect(shifted == package)
    }

    @Test func missingEndedAtUsesLatestSampleAsAnchor() {
        let start = Date(timeIntervalSince1970: 100)
        let lastFix = start.addingTimeInterval(500)
        let now = Date(timeIntervalSince1970: 10_000)
        let package = SessionTransferPackage(
            manifest: SessionManifest(
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "Watch7,1",
                systemVersion: "26.0",
                startedAt: start,
                endedAt: nil
            ),
            locations: [
                LocationSample(
                    timestamp: lastFix,
                    latitude: 0,
                    longitude: 0,
                    horizontalAccuracy: 5
                ),
            ],
            health: []
        )
        let shifted = SessionTimelineRebase.package(package, soEndedAt: now)
        #expect(shifted.manifest.endedAt == now)
        #expect(shifted.manifest.startedAt == now.addingTimeInterval(-500))
        #expect(shifted.locations[0].timestamp == now)
    }

    /// Regression: the rebased copy of a derived set must keep `fallDetected` — an earlier version
    /// of `shift(_ set:by:)` rebuilt `SetSegmentStats` without threading it through, silently
    /// resetting every set to `false` on rebase.
    @Test func rebasePreservesFallDetectedOnDerivedSets() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(600)
        let now = Date(timeIntervalSince1970: 2_000_000)

        let flaggedSet = SetSegmentStats(
            index: 1,
            startedAt: start,
            endedAt: end,
            duration: 600,
            distanceMeters: 400,
            fallDetected: true
        )
        let stats = SessionStats(
            startedAt: start,
            endedAt: end,
            totalDuration: 600,
            totalDistanceMeters: 400,
            activeEnergyKilocalories: nil,
            setCount: 1,
            ridingDuration: 600,
            inactiveDuration: 0,
            ridingInactiveRatio: 1,
            sets: [flaggedSet]
        )
        let package = SessionTransferPackage(
            manifest: SessionManifest(
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "Watch7,1",
                systemVersion: "26.0",
                startedAt: start,
                endedAt: end
            ),
            locations: [],
            health: [],
            derived: DerivedSessionView(stats: stats)
        )

        let shifted = SessionTimelineRebase.package(package, soEndedAt: now)

        #expect(shifted.derived?.stats.sets.first?.fallDetected == true)
        #expect(shifted.derived?.stats.sets.first?.startedAt == now.addingTimeInterval(-600))
    }

    @Test func loadExampleRebasesBeforeBuildingStats() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(3_600)
        let now = Date(timeIntervalSince1970: 9_000)
        let package = SessionTransferPackage(
            manifest: SessionManifest(
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "Watch7,1",
                systemVersion: "26.0",
                startedAt: start,
                endedAt: end,
                activityCode: "Example session"
            ),
            detections: [
                DetectionEvent(
                    code: DetectionCodes.inactive,
                    timestamp: start,
                    reason: "session_start",
                    detectorId: "session_start"
                ),
            ],
            locations: [],
            health: []
        )

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExampleRebase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("example.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(package).write(to: url)

        let bundle = try SessionLoader.loadExample(packageURL: url, now: now)
        #expect(bundle.manifest.endedAt == now)
        #expect(bundle.manifest.startedAt == now.addingTimeInterval(-3_600))
        #expect(bundle.stats.endedAt == now)
        #expect(bundle.stats.startedAt == now.addingTimeInterval(-3_600))
        #expect(bundle.detections[0].timestamp == now.addingTimeInterval(-3_600))
    }
}
