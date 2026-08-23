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
