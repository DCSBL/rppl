import Foundation
import Testing
@testable import RpplCore

@Suite("SampleRequeue")
struct SampleRequeueTests {
    @Test func failedBatchGoesInFrontOfNewSamples() {
        #expect(SampleRequeue.merge(failed: [1, 2], before: [3], cap: 10) == [1, 2, 3])
    }

    @Test func overTheCapDropsTheOldest() {
        #expect(SampleRequeue.merge(failed: [1, 2, 3], before: [4, 5], cap: 3) == [3, 4, 5])
    }

    @Test func emptyInputs() {
        #expect(SampleRequeue.merge(failed: [Int](), before: [], cap: 3).isEmpty)
        #expect(SampleRequeue.merge(failed: [1], before: [], cap: 0).isEmpty)
    }
}
