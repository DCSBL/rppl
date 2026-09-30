import Foundation
import Testing
@testable import RpplCore

@Suite("Deadline")
struct DeadlineTests {
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
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { continuation.resume() }
                }
                return 1
            }
            Issue.record("expected Deadline.Expired")
        } catch let expired as Deadline.Expired {
            #expect(expired.label == "stuck")
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(Date().timeIntervalSince(started) < 2)
    }
}
