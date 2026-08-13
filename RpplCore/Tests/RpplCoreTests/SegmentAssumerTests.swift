import Foundation
import Testing
@testable import RpplCore

@Suite("SpeedUnits")
struct SpeedUnitsTests {
    @Test func kmhMpsRoundTrip() {
        let mps = SpeedUnits.metersPerSecond(fromKilometersPerHour: 15)
        #expect(abs(mps - (15 / 3.6)) < 0.0001)
        #expect(abs(SpeedUnits.kilometersPerHour(fromMetersPerSecond: mps) - 15) < 0.0001)
    }

    @Test func reasonFormatsKmh() {
        #expect(SpeedUnits.reasonKilometersPerHour(fromMetersPerSecond: nil) == "nil")
        #expect(SpeedUnits.reasonKilometersPerHour(fromMetersPerSecond: 15 / 3.6) == "15.0km/h")
    }
}

@Suite("SegmentAssumer")
struct SegmentAssumerTests {
    private let accuracyOK: Double = 5

    private func tick(
        at seconds: TimeInterval,
        speedKmh: Double?,
        water: String? = "notSubmerged",
        activity: String? = "stationary",
        accuracy: Double? = 5
    ) -> AssumerTick {
        AssumerTick(
            timestamp: Date(timeIntervalSince1970: seconds),
            speedMps: speedKmh.map { SpeedUnits.metersPerSecond(fromKilometersPerHour: $0) },
            horizontalAccuracy: accuracy,
            waterSubmersionState: water,
            motionActivity: activity
        )
    }

    @Test func sessionStartWritesWaiting() {
        var assumer = SegmentAssumer()
        let event = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))
        #expect(event.code == LabelCodes.waiting)
        #expect(event.reason == "session_start")
        #expect(assumer.currentCode == LabelCodes.waiting)
    }

    @Test func rideStartAfterSustainedSpeed() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))

        #expect(assumer.process(tick(at: 1, speedKmh: 16)) == nil)
        let event = assumer.process(tick(at: 3.1, speedKmh: 16))
        #expect(event?.code == LabelCodes.riding)
        #expect(event?.reason.contains("ride_start") == true)
        #expect(event?.reason.contains("km/h") == true)
        #expect(assumer.currentCode == LabelCodes.riding)
    }

    @Test func failedStartReturnsWaitingWithoutSubmersion() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))
        #expect(assumer.process(tick(at: 1, speedKmh: 16)) == nil)
        #expect(assumer.process(tick(at: 3.1, speedKmh: 16))?.code == LabelCodes.riding)

        let failed = assumer.process(tick(at: 5, speedKmh: 2, water: "notSubmerged"))
        #expect(failed?.code == LabelCodes.waiting)
        #expect(failed?.reason.contains("failed_start") == true)
    }

    @Test func fallRequiresSubmerged_noSpeedOnlySwim() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))
        #expect(assumer.process(tick(at: 1, speedKmh: 16)) == nil)
        #expect(assumer.process(tick(at: 3.1, speedKmh: 16))?.code == LabelCodes.riding)

        // Long stop path — still not swimming without submerged
        #expect(assumer.process(tick(at: 10, speedKmh: 2, water: "notSubmerged")) == nil)
        let longStop = assumer.process(tick(at: 13.1, speedKmh: 2, water: "notSubmerged"))
        #expect(longStop?.code == LabelCodes.waiting)
        #expect(longStop?.reason.contains("long_stop") == true)
        #expect(assumer.currentCode != LabelCodes.swimming)
    }

    @Test func fallSwimWhenSubmergedAndSlow() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))
        #expect(assumer.process(tick(at: 1, speedKmh: 16)) == nil)
        #expect(assumer.process(tick(at: 3.1, speedKmh: 16))?.code == LabelCodes.riding)

        let swim = assumer.process(tick(at: 8, speedKmh: 3, water: "submerged"))
        #expect(swim?.code == LabelCodes.swimming)
        #expect(swim?.reason.contains("fall_swim") == true)
    }

    @Test func fallSwimAllowsNilSpeedWhenSubmerged() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))
        #expect(assumer.process(tick(at: 1, speedKmh: 16)) == nil)
        #expect(assumer.process(tick(at: 3.1, speedKmh: 16))?.code == LabelCodes.riding)

        let swim = assumer.process(tick(at: 8, speedKmh: nil, water: "submerged", accuracy: nil))
        #expect(swim?.code == LabelCodes.swimming)
    }

    @Test func waterStartFromSwim() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))
        #expect(assumer.process(tick(at: 1, speedKmh: 16)) == nil)
        #expect(assumer.process(tick(at: 3.1, speedKmh: 16))?.code == LabelCodes.riding)
        #expect(assumer.process(tick(at: 8, speedKmh: 3, water: "submerged"))?.code == LabelCodes.swimming)

        #expect(assumer.process(tick(at: 10, speedKmh: 16, water: "submerged")) == nil)
        let ride = assumer.process(tick(at: 12.1, speedKmh: 16, water: "submerged"))
        #expect(ride?.code == LabelCodes.riding)
        #expect(ride?.reason.contains("water_start") == true)
    }

    @Test func walkFromSwimViaActivity() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))
        #expect(assumer.process(tick(at: 1, speedKmh: 16)) == nil)
        #expect(assumer.process(tick(at: 3.1, speedKmh: 16))?.code == LabelCodes.riding)
        #expect(assumer.process(tick(at: 8, speedKmh: 3, water: "submerged"))?.code == LabelCodes.swimming)

        let walk = assumer.process(
            tick(at: 12, speedKmh: 0, water: "notSubmerged", activity: "walking")
        )
        #expect(walk?.code == LabelCodes.walking)
        #expect(walk?.reason.contains("activity=walking") == true)
    }

    @Test func walkFromWaitingViaSpeedBand() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))

        #expect(assumer.process(tick(at: 1, speedKmh: 5, activity: "unknown")) == nil)
        let walk = assumer.process(tick(at: 4.1, speedKmh: 5, activity: "unknown"))
        #expect(walk?.code == LabelCodes.walking)
        #expect(walk?.reason.contains("walk speed=") == true)
    }

    @Test func waitSettleFromWalking() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))
        #expect(assumer.process(tick(at: 1, speedKmh: 5, activity: "unknown")) == nil)
        #expect(assumer.process(tick(at: 4.1, speedKmh: 5, activity: "unknown"))?.code == LabelCodes.walking)

        #expect(assumer.process(tick(at: 6, speedKmh: 1, activity: "stationary")) == nil)
        let wait = assumer.process(tick(at: 11.1, speedKmh: 1, activity: "stationary"))
        #expect(wait?.code == LabelCodes.waiting)
        #expect(wait?.reason.contains("wait_settle") == true)
    }

    @Test func poorAccuracySkipsSpeedTransitionsButAllowsWaterSwim() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))

        #expect(assumer.process(tick(at: 1, speedKmh: 16, accuracy: 40)) == nil)
        #expect(assumer.process(tick(at: 4, speedKmh: 16, accuracy: 40)) == nil)

        // Enter riding with good accuracy first
        #expect(assumer.process(tick(at: 5, speedKmh: 16, accuracy: accuracyOK)) == nil)
        #expect(assumer.process(tick(at: 7.1, speedKmh: 16, accuracy: accuracyOK))?.code == LabelCodes.riding)

        let swim = assumer.process(
            tick(at: 10, speedKmh: 3, water: "submerged", accuracy: 50)
        )
        #expect(swim?.code == LabelCodes.swimming)
    }
}

@Suite("AssumptionStore")
struct AssumptionStoreTests {
    @Test func assumptionsRoundTripInTransferPackage() throws {
        let watchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-assume-\(UUID().uuidString)", isDirectory: true)
        let phoneRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("phone-assume-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: watchRoot)
            try? FileManager.default.removeItem(at: phoneRoot)
        }

        let watchStore = SessionFileStore(rootURL: watchRoot)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        _ = try watchStore.createSession(manifest: manifest)
        try watchStore.appendAssumption(
            AssumptionEvent(code: LabelCodes.waiting, reason: "session_start"),
            sessionId: manifest.sessionId
        )
        try watchStore.appendAssumption(
            AssumptionEvent(
                code: LabelCodes.riding,
                reason: "ride_start speed=16.0km/h>=15 for 2.1s from=waiting",
                speedMps: 16 / 3.6,
                waterSubmersionState: "notSubmerged"
            ),
            sessionId: manifest.sessionId
        )

        let package = try watchStore.buildTransferPackage(sessionId: manifest.sessionId)
        #expect(package.assumptions.count == 2)
        try watchStore.importTransferPackage(package, intoPhoneStore: phoneRoot)

        let phoneStore = SessionFileStore(rootURL: phoneRoot)
        let loaded = try phoneStore.readAssumptions(sessionId: manifest.sessionId)
        #expect(loaded.count == 2)
        #expect(loaded[0].reason == "session_start")
        #expect(loaded[1].code == LabelCodes.riding)
    }

    @Test func legacyTransferPackageDecodesWithoutAssumptionsKey() throws {
        let json = """
        {
          "health": [],
          "labels": [],
          "locations": [],
          "manifest": {
            "appVersion": "1.0",
            "buildNumber": "1",
            "schemaVersion": 1,
            "sessionId": "legacy",
            "startedAt": "2024-01-01T00:00:00Z",
            "systemVersion": "26.0",
            "testerId": "t",
            "transferState": "acknowledged",
            "watchModel": "Ultra2"
          },
          "motion": []
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(SessionTransferPackage.self, from: data)
        #expect(package.assumptions.isEmpty)
        #expect(package.manifest.sessionId == "legacy")
    }
}
