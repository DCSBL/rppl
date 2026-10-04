import Foundation
import Testing
@testable import RpplCore

@Suite("DanglingWorkoutEnd")
struct DanglingWorkoutEndTests {
    private let hkStart = Date(timeIntervalSince1970: 1_000)
    private let lastSample = Date(timeIntervalSince1970: 5_000)
    private let now = Date(timeIntervalSince1970: 90_000)

    @Test func withoutAnOrphanTheWorkoutEndsNow() {
        #expect(DanglingWorkoutEnd.date(orphanLastSample: nil, hkStart: hkStart, now: now) == now)
    }

    @Test func aLateRelaunchEndsAtTheLastSampleNotAtNow() {
        #expect(DanglingWorkoutEnd.date(orphanLastSample: lastSample, hkStart: hkStart, now: now) == lastSample)
    }

    @Test func neverEndsBeforeTheWorkoutStarted() {
        let early = Date(timeIntervalSince1970: 10)
        #expect(DanglingWorkoutEnd.date(orphanLastSample: early, hkStart: hkStart, now: now) == hkStart)
    }

    @Test func neverEndsInTheFuture() {
        let future = now.addingTimeInterval(3_600)
        #expect(DanglingWorkoutEnd.date(orphanLastSample: future, hkStart: hkStart, now: now) == now)
    }

    @Test func anUnknownStartStillEndsAtTheLastSample() {
        #expect(DanglingWorkoutEnd.date(orphanLastSample: lastSample, hkStart: nil, now: now) == lastSample)
    }
}
