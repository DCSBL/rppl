import Foundation
import Testing
@testable import WakeTrackerCore

@Suite("SyncConnectionResolver")
struct SyncConnectionResolverTests {
    @Test func unsupported() {
        let state = SyncConnectionResolver.resolve(
            supported: false,
            activation: .activated,
            isPaired: true,
            isWatchAppInstalled: true,
            isCompanionAppInstalled: true,
            isReachable: true,
            isSimulator: false,
            platform: .phone
        )
        #expect(state == .unsupported)
    }

    @Test func phoneActivationStates() {
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .notActivated,
                isPaired: true,
                isWatchAppInstalled: true,
                isCompanionAppInstalled: true,
                isReachable: false,
                isSimulator: false,
                platform: .phone
            ) == .notActivated
        )
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .inactive,
                isPaired: true,
                isWatchAppInstalled: true,
                isCompanionAppInstalled: true,
                isReachable: false,
                isSimulator: false,
                platform: .phone
            ) == .inactive
        )
    }

    @Test func phoneNotPaired() {
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .activated,
                isPaired: false,
                isWatchAppInstalled: false,
                isCompanionAppInstalled: true,
                isReachable: false,
                isSimulator: false,
                platform: .phone
            ) == .notPaired
        )
    }

    @Test func phoneWatchAppMissingOnDevice() {
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .activated,
                isPaired: true,
                isWatchAppInstalled: false,
                isCompanionAppInstalled: true,
                isReachable: false,
                isSimulator: false,
                platform: .phone
            ) == .watchAppMissing
        )
    }

    @Test func phoneSimulatorQuirkTreatsMissingInstallAsQueued() {
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .activated,
                isPaired: true,
                isWatchAppInstalled: false,
                isCompanionAppInstalled: true,
                isReachable: false,
                isSimulator: true,
                platform: .phone
            ) == .readyQueued
        )
    }

    @Test func phoneReachableBecomesLiveEvenIfInstallFlagFalse() {
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .activated,
                isPaired: true,
                isWatchAppInstalled: false,
                isCompanionAppInstalled: true,
                isReachable: true,
                isSimulator: false,
                platform: .phone
            ) == .readyLive
        )
    }

    @Test func phoneInstalledNotReachableIsQueued() {
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .activated,
                isPaired: true,
                isWatchAppInstalled: true,
                isCompanionAppInstalled: true,
                isReachable: false,
                isSimulator: false,
                platform: .phone
            ) == .readyQueued
        )
    }

    @Test func watchCompanionMissing() {
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .activated,
                isPaired: true,
                isWatchAppInstalled: true,
                isCompanionAppInstalled: false,
                isReachable: true,
                isSimulator: false,
                platform: .watch
            ) == .companionMissing
        )
    }

    @Test func watchReadyStates() {
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .activated,
                isPaired: true,
                isWatchAppInstalled: true,
                isCompanionAppInstalled: true,
                isReachable: true,
                isSimulator: false,
                platform: .watch
            ) == .readyLive
        )
        #expect(
            SyncConnectionResolver.resolve(
                supported: true,
                activation: .activated,
                isPaired: true,
                isWatchAppInstalled: true,
                isCompanionAppInstalled: true,
                isReachable: false,
                isSimulator: false,
                platform: .watch
            ) == .readyQueued
        )
    }
}

@Suite("LabelEventFactory")
struct LabelEventFactoryTests {
    @Test func makePreservesSnapshotFields() {
        let ts = Date(timeIntervalSince1970: 1_700_000_100)
        let gps = LabelEventFactory.gpsSnapshot(
            latitude: 52.1,
            longitude: 5.2,
            altitude: 1.5,
            horizontalAccuracy: 4,
            verticalAccuracy: 6,
            speed: 2.5,
            course: 90,
            timestamp: ts
        )
        let event = LabelEventFactory.make(
            code: LabelCodes.riding,
            timestamp: ts,
            id: "fixed-id",
            gps: gps,
            waterSubmersionState: "submerged",
            waterTemperatureCelsius: 17.2,
            motionActivity: "unknown"
        )
        #expect(event.id == "fixed-id")
        #expect(event.code == LabelCodes.riding)
        #expect(event.gps?.latitude == 52.1)
        #expect(event.gps?.speed == 2.5)
        #expect(event.waterTemperatureCelsius == 17.2)
        #expect(event.motionActivity == "unknown")
    }

    @Test func gpsSnapshotDropsNegativeSpeedAndCourse() {
        let gps = LabelEventFactory.gpsSnapshot(
            latitude: 1,
            longitude: 2,
            horizontalAccuracy: 3,
            speed: -1,
            course: -1,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        #expect(gps.speed == nil)
        #expect(gps.course == nil)
    }
}

@Suite("TransferPendingFilter")
struct TransferPendingFilterTests {
    private func manifest(_ state: SessionManifest.TransferState) -> SessionManifest {
        SessionManifest(
            sessionId: UUID().uuidString,
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0",
            transferState: state
        )
    }

    @Test func filtersCorrectStates() {
        let input = [
            manifest(.recording),
            manifest(.readyToTransfer),
            manifest(.transferring),
            manifest(.acknowledged),
        ]
        let pending = TransferPendingFilter.needingTransfer(input)
        #expect(pending.map(\.transferState) == [.readyToTransfer, .transferring])
    }

    @Test func emptyInput() {
        #expect(TransferPendingFilter.needingTransfer([]).isEmpty)
    }
}

@Suite("ModelCodable")
struct ModelCodableTests {
    @Test func manifestRoundTripPreservesSchema() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = SessionManifest(
            schemaVersion: SessionSchema.currentVersion,
            sessionId: "abc",
            testerId: "tester",
            appVersion: "1.0",
            buildNumber: "9",
            watchModel: "Watch7,1",
            systemVersion: "26.2",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            transferState: .readyToTransfer
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SessionManifest.self, from: data)
        #expect(decoded == original)
        #expect(decoded.schemaVersion == SessionSchema.currentVersion)
    }

    @Test func motionSampleRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sample = MotionSample(
            timestamp: Date(timeIntervalSince1970: 50),
            userAccelX: 0.1,
            userAccelY: 0.2,
            userAccelZ: 0.3,
            rotationX: 1,
            rotationY: 2,
            rotationZ: 3,
            pitch: 0.4,
            roll: 0.5,
            yaw: 0.6
        )
        let decoded = try decoder.decode(MotionSample.self, from: try encoder.encode(sample))
        #expect(decoded == sample)
    }
}
