import Foundation
import Testing
@testable import RpplCore

/// The phone sends this text back to the Watch when an import fails; it is what ends up in
/// `lastTransferError`. It is how a failed sync gets diagnosed, so it must stay informative.
@Suite("SessionImportFailure")
struct SessionImportFailureTests {
    private struct Odd: LocalizedError {
        var errorDescription: String? { "odd failure" }
    }

    @Test func storeErrorsNameTheCase() {
        let reason = SessionImportFailure.reason(for: SessionStoreError.sessionNotFound("ABC"))
        #expect(reason == #"store: sessionNotFound("ABC")"#)
    }

    @Test func motionFrameErrorsAreTaggedAsMotion() {
        #expect(SessionImportFailure.reason(for: CompressedJSONLFrameError.truncatedFrame) == "motion: truncatedFrame")
    }

    @Test func decodingErrorsAreTaggedAsDecode() throws {
        let error = try #require(
            { () -> Error? in
                do {
                    _ = try JSONDecoder().decode(SessionManifest.self, from: Data("{}".utf8))
                    return nil
                } catch {
                    return error
                }
            }()
        )
        #expect(SessionImportFailure.reason(for: error).hasPrefix("decode: "))
    }

    @Test func otherErrorsUseTheirDescription() {
        #expect(SessionImportFailure.reason(for: Odd()) == "odd failure")
    }

    @Test func longReasonsAreCutSoTheNackStaysSmall() {
        let detail = String(repeating: "x", count: 5_000)
        let reason = SessionImportFailure.reason(for: SessionStoreError.importLimitExceeded(detail))
        #expect(reason.count == SessionImportFailure.maxReasonLength)
        #expect(reason.hasPrefix("store: importLimitExceeded("))
    }

    @Test func everyStoreErrorProducesANonEmptyTaggedReason() {
        let errors: [SessionStoreError] = [
            .sessionNotFound("a"), .invalidManifest, .invalidSessionId("b"), .importTooLarge(1),
            .importLimitExceeded("c"), .ioFailure("d"), .notTransferable("e")
        ]
        for error in errors {
            #expect(SessionImportFailure.reason(for: error).hasPrefix("store: "))
        }
    }
}
