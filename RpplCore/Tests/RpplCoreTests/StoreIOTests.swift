import Foundation
import Testing
@testable import RpplCore

/// `StoreIO.runOffMain` keeps imports and flushes off the main actor (a UI freeze while iOS woke
/// the phone app for a transfer could get it killed before the ack went out).
@Suite("StoreIO")
struct StoreIOTests {
    private struct Boom: Error, Equatable {}

    @Test func returnsTheWorkResult() async throws {
        let value = try await StoreIO.runOffMain { 21 * 2 }
        #expect(value == 42)
    }

    @Test func propagatesTheWorkError() async {
        await #expect(throws: Boom.self) {
            try await StoreIO.runOffMain { () throws -> Int in throw Boom() }
        }
    }

    @Test func runsOffTheMainThread() async throws {
        let onMain = try await StoreIO.runOffMain { Thread.isMainThread }
        #expect(!onMain)
    }

    @Test func doesNotBlockTheCallerWhileWorkRuns() async throws {
        // A main-actor caller must stay responsive while blocking store work runs.
        let started = Date()
        async let slow: Void = StoreIO.runOffMain { Thread.sleep(forTimeInterval: 0.3) }
        let waited = Date().timeIntervalSince(started)
        try await slow
        #expect(waited < 0.2)
    }

    @Test func manyConcurrentCallsAllComplete() async throws {
        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<50 {
                group.addTask { try await StoreIO.runOffMain { index * 2 } }
            }
            var sum = 0
            for try await value in group { sum += value }
            return sum
        }
        #expect(results == (0..<50).reduce(0) { $0 + $1 * 2 })
    }

    @Test func importOffMainWritesTheSameAsInline() async throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let store = session.store
        let id = session.sessionId
        try await StoreIO.runOffMain {
            try store.appendLocationSamples([Samples.location(0), Samples.location(1)], sessionId: id)
        }
        #expect(try store.readLocationSamples(sessionId: id).count == 2)
    }
}
