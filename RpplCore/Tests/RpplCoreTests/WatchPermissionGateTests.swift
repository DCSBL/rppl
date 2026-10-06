import Testing
@testable import RpplCore

struct WatchPermissionGateTests {
    @Test func areAllReadyWhenAuthorizedOrUnavailable() {
        let states: [WatchPermissionKind: WatchPermissionState] = [
            .location: .authorized,
            .health: .authorized,
            .motion: .unavailable
        ]
        #expect(WatchPermissionOrder.areAllReady(states))
        #expect(!WatchPermissionState.denied.isReady)
        #expect(WatchPermissionState.unavailable.isReady)
    }

    @Test func reducedAccuracyMakesGrantedLocationNotReady() {
        #expect(WatchPermissionState.authorized.accountingForReducedAccuracy(true) == .denied)
        #expect(!WatchPermissionState.authorized.accountingForReducedAccuracy(true).isReady)
        #expect(WatchPermissionKind.location.blocksRecording(
            when: WatchPermissionState.authorized.accountingForReducedAccuracy(true)
        ))
    }

    @Test func fullAccuracyLeavesEveryStateAlone() {
        for state in [WatchPermissionState.authorized, .notDetermined, .denied, .unavailable] {
            #expect(state.accountingForReducedAccuracy(false) == state)
        }
    }

    @Test func reducedAccuracyDoesNotChangeStatesThatAreNotGranted() {
        #expect(WatchPermissionState.notDetermined.accountingForReducedAccuracy(true) == .notDetermined)
        #expect(WatchPermissionState.denied.accountingForReducedAccuracy(true) == .denied)
        #expect(WatchPermissionState.unavailable.accountingForReducedAccuracy(true) == .unavailable)
    }

    @Test func motionNeverBlocksRecordingGate() {
        let states: [WatchPermissionKind: WatchPermissionState] = [
            .location: .authorized,
            .health: .authorized,
            .motion: .denied
        ]
        #expect(WatchPermissionOrder.areAllReady(states))
        #expect(!WatchPermissionKind.motion.blocksRecording(when: .notDetermined))
        #expect(!WatchPermissionKind.motion.blocksRecording(when: .denied))
    }

    @Test func healthDeniedBlocksGate() {
        let states: [WatchPermissionKind: WatchPermissionState] = [
            .location: .authorized,
            .health: .denied,
            .motion: .notDetermined
        ]
        #expect(!WatchPermissionOrder.areAllReady(states))
        #expect(WatchPermissionKind.health.blocksRecording(when: .notDetermined))
        #expect(WatchPermissionKind.health.blocksRecording(when: .denied))
        #expect(WatchPermissionKind.health.blocksRecording(when: .unavailable))
    }

    @Test func locationDeniedBlocksGate() {
        let states: [WatchPermissionKind: WatchPermissionState] = [
            .location: .denied,
            .health: .authorized,
            .motion: .authorized
        ]
        #expect(!WatchPermissionOrder.areAllReady(states))
        #expect(WatchPermissionKind.location.blocksRecording(when: .denied))
    }
}

struct WatchStartBlockerTests {
    private typealias States = [WatchPermissionKind: WatchPermissionState]

    @Test func healthBlocksBeforeLocation() {
        let states: States = [.health: .denied, .location: .denied, .motion: .authorized]
        #expect(WatchPermissionOrder.startBlocker(states: states) == .health)
    }

    @Test func simulatorStyleUnavailableHealthStillBlocks() {
        let states: States = [.health: .unavailable, .location: .authorized, .motion: .authorized]
        #expect(WatchPermissionOrder.startBlocker(states: states) == .health)
    }

    @Test func noBlockerWhenAllAuthorized() {
        let states: States = [.health: .authorized, .location: .authorized, .motion: .denied]
        #expect(WatchPermissionOrder.startBlocker(states: states) == nil)
    }
}

struct WatchNeedsSetupTests {
    private typealias States = [WatchPermissionKind: WatchPermissionState]

    @Test func undecidedPermissionNeedsSetup() {
        let states: States = [.health: .authorized, .location: .authorized, .motion: .notDetermined]
        #expect(WatchPermissionOrder.needsSetup(states))
    }

    @Test func missingStatesCountAsUndecided() {
        #expect(WatchPermissionOrder.needsSetup([:]))
    }

    @Test func requiredDenialNeedsSetup() {
        let states: States = [.health: .denied, .location: .authorized, .motion: .authorized]
        #expect(WatchPermissionOrder.needsSetup(states))
    }

    @Test func deniedMotionAloneSkipsSetup() {
        let states: States = [.health: .authorized, .location: .authorized, .motion: .denied]
        #expect(!WatchPermissionOrder.needsSetup(states))
    }

    @Test func allReadySkipsSetup() {
        let states: States = [.health: .authorized, .location: .authorized, .motion: .unavailable]
        #expect(!WatchPermissionOrder.needsSetup(states))
    }
}
