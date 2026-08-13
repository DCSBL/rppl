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
        #expect(decoded.timestamp == sample.timestamp)
        #expect(decoded.userAccelX == 0.1)
        #expect(decoded.yaw == 0.6)
    }

    @Test func motionSampleDecodesLegacyVerboseKeys() throws {
        let json = Data(
            #"{"timestamp":"1970-01-01T00:00:50Z","userAccelX":0.1,"userAccelY":0.2,"userAccelZ":0.3,"rotationX":1,"rotationY":2,"rotationZ":3,"pitch":0.4,"roll":0.5,"yaw":0.6}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MotionSample.self, from: json)
        #expect(decoded.userAccelX == 0.1)
        #expect(decoded.pitch == 0.4)
    }
}
