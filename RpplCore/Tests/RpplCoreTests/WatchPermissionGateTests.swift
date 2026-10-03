import Testing
@testable import RpplCore

struct WatchPermissionGateTests {
    @Test func initialOrderPutsAttentionBeforeReady() {
        let states: [WatchPermissionKind: WatchPermissionState] = [
            .location: .authorized,
            .health: .denied,
            .motion: .notDetermined
        ]
        #expect(
            WatchPermissionOrder.initialOrder(states: states) == [.health, .motion, .location]
        )
    }

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

    @Test func preservingOrderDoesNotMoveAcceptedDuringSession() {
        let current: [WatchPermissionKind] = [.motion, .location, .health]
        let previous: [WatchPermissionKind: WatchPermissionState] = [
            .motion: .denied,
            .location: .authorized,
            .health: .authorized
        ]
        let next: [WatchPermissionKind: WatchPermissionState] = [
            .motion: .authorized,
            .location: .authorized,
            .health: .authorized
        ]
        #expect(
            WatchPermissionOrder.orderPreserving(
                current: current,
                previous: previous,
                next: next
            ) == [.motion, .location, .health]
        )
    }

    @Test func revocationMovesRevokedToFront() {
        let current: [WatchPermissionKind] = [.location, .health, .motion]
        let previous: [WatchPermissionKind: WatchPermissionState] = [
            .location: .authorized,
            .health: .authorized,
            .motion: .authorized
        ]
        let next: [WatchPermissionKind: WatchPermissionState] = [
            .location: .authorized,
            .health: .denied,
            .motion: .authorized
        ]
        #expect(
            WatchPermissionOrder.orderPreserving(
                current: current,
                previous: previous,
                next: next
            ) == [.health, .location, .motion]
        )
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

    @Test func firstRunPromptOnlyWhileUndecided() {
        let undecided: States = [.health: .notDetermined, .location: .authorized, .motion: .authorized]
        let denied: States = [.health: .denied, .location: .authorized, .motion: .authorized]
        #expect(WatchPermissionOrder.needsFirstRunPrompt(states: undecided))
        #expect(!WatchPermissionOrder.needsFirstRunPrompt(states: denied))
    }
}
