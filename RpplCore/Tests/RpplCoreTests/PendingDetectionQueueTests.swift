import Foundation
import Testing
@testable import RpplCore

@Suite("PendingDetectionQueue")
struct PendingDetectionQueueTests {
    private struct DiskFull: Error {}

    private func event(_ code: String, second: Int) -> DetectionEvent {
        Samples.detection(code, second: second)
    }

    @Test func drainWritesEveryEventOldestFirstAndEmptiesTheQueue() {
        var queue = PendingDetectionQueue()
        let events = [event("riding", second: 1), event("inactive", second: 2), event("riding", second: 3)]
        events.forEach { queue.enqueue($0) }

        var written: [DetectionEvent] = []
        let result = queue.drain { written.append($0) }

        #expect(written == events)
        #expect(result.written == 3)
        #expect(result.error == nil)
        #expect(queue.isEmpty)
    }

    @Test func aFailureKeepsTheFailedEventAndEverythingAfterIt() {
        var queue = PendingDetectionQueue()
        let events = [event("riding", second: 1), event("inactive", second: 2), event("riding", second: 3)]
        events.forEach { queue.enqueue($0) }

        var written: [DetectionEvent] = []
        let result = queue.drain { event in
            if event == events[1] { throw DiskFull() }
            written.append(event)
        }

        #expect(written == [events[0]])
        #expect(result.written == 1)
        #expect(result.error is DiskFull)
        #expect(queue.events == [events[1], events[2]])
    }

    @Test func aLaterDrainRetriesTheKeptEventsInOrder() {
        var queue = PendingDetectionQueue()
        let events = [event("riding", second: 1), event("inactive", second: 2)]
        events.forEach { queue.enqueue($0) }
        queue.drain { _ in throw DiskFull() }

        queue.enqueue(event("riding", second: 3))
        var written: [DetectionEvent] = []
        queue.drain { written.append($0) }

        #expect(written.map(\.timestamp) == [Samples.time(1), Samples.time(2), Samples.time(3)])
        #expect(queue.isEmpty)
    }

    @Test func theSameEventIsNeverQueuedTwice() {
        var queue = PendingDetectionQueue()
        let one = event("riding", second: 1)
        queue.enqueue(one)
        queue.enqueue(one)

        #expect(queue.count == 1)
    }

    @Test func removeAllClearsTheQueue() {
        var queue = PendingDetectionQueue()
        queue.enqueue(event("riding", second: 1))
        queue.removeAll()

        #expect(queue.isEmpty)
    }
}
