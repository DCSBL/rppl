import Foundation
import Testing
@testable import RpplCore

/// On the Watch the flush loop, detection writes, the transfer builder and the UI all use one
/// store at once. Every append must land whole and every concurrent read must see valid data.
@Suite("SessionFileStore concurrency", .serialized)
struct SessionStoreConcurrencyTests {
    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private var errors: [String] = []
        func record(_ error: Error) {
            lock.lock(); defer { lock.unlock() }
            errors.append(String(describing: error))
        }
        var all: [String] {
            lock.lock(); defer { lock.unlock() }
            return errors
        }
    }

    @Test func concurrentAppendersNeverLoseOrCorruptALine() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let store = session.store
        let id = session.sessionId
        let tally = Tally()

        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for index in 0..<100 {
                do {
                    try store.appendHealthSamples([Samples.health(worker * 100 + index)], sessionId: id)
                    try store.appendDetection(
                        Samples.detection(DetectionCodes.inactive, second: worker * 100 + index),
                        sessionId: id
                    )
                } catch {
                    tally.record(error)
                }
            }
        }

        #expect(tally.all.isEmpty, "\(tally.all.prefix(3))")
        let health = try store.readHealthSamples(sessionId: id)
        #expect(health.count == 800)
        #expect(Set(health.map(\.timestamp)).count == 800)
        #expect(try store.readDetections(sessionId: id).count == 800)
    }

    @Test func buildingATransferPackageWhileRecordingNeverFailsOrSeesAHalfLine() throws {
        let session = try TempSession.make(endedAt: Samples.time(1), state: .readyToTransfer)
        defer { session.cleanup() }
        let store = session.store
        let id = session.sessionId
        let tally = Tally()
        let counts = CountLog()

        DispatchQueue.concurrentPerform(iterations: 2) { role in
            if role == 0 {
                for second in 0..<400 {
                    do {
                        try store.appendLocationSamples([Samples.location(second)], sessionId: id)
                        try store.appendMotionSamples([Samples.motion(second)], sessionId: id)
                    } catch {
                        tally.record(error)
                    }
                }
            } else {
                for _ in 0..<40 {
                    do {
                        counts.add(try store.buildTransferPackage(sessionId: id).locations.count)
                    } catch {
                        tally.record(error)
                    }
                }
            }
        }

        #expect(tally.all.isEmpty, "\(tally.all.prefix(3))")
        // Each package is a prefix of the final stream: counts only ever go up.
        #expect(counts.values == counts.values.sorted())
        #expect(try store.readLocationSamples(sessionId: id).count == 400)
        #expect(try store.readMotionSamples(sessionId: id).count == 400)
    }

    private final class CountLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Int] = []
        func add(_ value: Int) {
            lock.lock(); defer { lock.unlock() }
            storage.append(value)
        }
        var values: [Int] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
    }
}
