import Foundation
import Testing
@testable import RpplCore

@Suite("Deadline")
struct DeadlineTests {
    /// Wall-clock slack for a 0.2 s deadline. Synchronous tests can hold every cooperative thread of a
    /// small CI runner for seconds, delaying the timer. The stuck work below runs 30 s, so a caller
    /// that is wrongly held for the work still fails this bound.
    private static let maxElapsed: TimeInterval = 15

    @Test func returnsResultWhenWorkIsFast() async throws {
        let value = try await Deadline.run(5, label: "fast") { 42 }
        #expect(value == 42)
    }

    @Test func passesThroughErrors() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await Deadline.run(5, label: "boom") { () async throws -> Int in throw Boom() }
        }
    }

    /// The case task-group timeouts get wrong: work that ignores cancellation and never returns
    /// in time must not hold the caller.
    @Test func expiresOnTimeWhenWorkIgnoresCancellation() async {
        let started = Date()
        do {
            _ = try await Deadline.run(0.2, label: "stuck") { () async -> Int in
                // Uncancellable wait, like a callback from a hung daemon.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 30) { continuation.resume() }
                }
                return 1
            }
            Issue.record("expected Deadline.Expired")
        } catch let expired as Deadline.Expired {
            #expect(expired.label == "stuck")
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(Date().timeIntervalSince(started) < Self.maxElapsed)
    }

    /// Awaiting an unstructured task that never finishes (the route-insert shape): `Task.value`
    /// does not return on cancellation, so a task-group timeout would hang here.
    @Test func expiresWhenAwaitingNeverFinishingUnstructuredTask() async {
        let inFlight = Task<Void, Never> {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }
        let started = Date()
        await #expect(throws: Deadline.Expired.self) {
            try await Deadline.run(0.2, label: "routeInsert") { await inFlight.value }
        }
        #expect(Date().timeIntervalSince(started) < Self.maxElapsed)
    }
}
