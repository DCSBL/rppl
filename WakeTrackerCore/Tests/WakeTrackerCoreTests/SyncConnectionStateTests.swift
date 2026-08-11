import Foundation
import Testing
@testable import WakeTrackerCore

@Suite("SyncConnectionState")
struct SyncConnectionStateTests {
    @Test func readyStatesAreSyncCapable() {
        #expect(SyncConnectionState.readyLive.isReadyToSync)
        #expect(SyncConnectionState.readyQueued.isReadyToSync)
        #expect(!SyncConnectionState.notPaired.isReadyToSync)
        #expect(!SyncConnectionState.watchAppMissing.isReadyToSync)
    }

    @Test func titlesAreNonEmpty() {
        for state in [
            SyncConnectionState.unsupported,
            .notActivated,
            .inactive,
            .notPaired,
            .watchAppMissing,
            .companionMissing,
            .readyQueued,
            .readyLive,
        ] {
            #expect(!state.title.isEmpty)
            #expect(!state.detail.isEmpty)
        }
    }
}
