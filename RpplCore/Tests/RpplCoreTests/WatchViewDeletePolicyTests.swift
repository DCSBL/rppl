import Foundation
import Testing
@testable import RpplCore

@Suite("WatchViewDeletePolicy")
struct WatchViewDeletePolicyTests {
    private func manifest(_ state: SessionManifest.TransferState) -> SessionManifest {
        SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch",
            systemVersion: "26.0",
            transferState: state
        )
    }

    @Test func onlyAcknowledgedMayBeDeleted() {
        #expect(WatchViewDeletePolicy.mayDelete(manifest(.acknowledged)))
        #expect(!WatchViewDeletePolicy.mayDelete(manifest(.recording)))
        #expect(!WatchViewDeletePolicy.mayDelete(manifest(.readyToTransfer)))
        #expect(!WatchViewDeletePolicy.mayDelete(manifest(.transferring)))
    }
}
