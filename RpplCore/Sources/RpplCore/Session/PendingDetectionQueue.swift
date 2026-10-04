import Foundation

/// Detection events that could not be written to `detections.jsonl` yet (disk full, folder
/// touched elsewhere). Events are small and sparse, so none are ever dropped: the set boundaries
/// on the phone are rebuilt from this file, so a lost event means a lost set.
public struct PendingDetectionQueue: Sendable {
    public private(set) var events: [DetectionEvent] = []

    public init() {}

    public var isEmpty: Bool { events.isEmpty }
    public var count: Int { events.count }

    /// Adds an event at the back. An event that is already queued (same id) is ignored.
    public mutating func enqueue(_ event: DetectionEvent) {
        guard !events.contains(where: { $0.id == event.id }) else { return }
        events.append(event)
    }

    /// Writes queued events oldest first and removes each one once written. Stops at the first
    /// failure and keeps that event and everything after it, so order is never changed.
    /// - Returns: how many events were written, and the error that stopped the drain (if any).
    @discardableResult
    public mutating func drain(
        using write: (DetectionEvent) throws -> Void
    ) -> (written: Int, error: Error?) {
        var written = 0
        for event in events {
            do {
                try write(event)
                written += 1
            } catch {
                events.removeFirst(written)
                return (written, error)
            }
        }
        events.removeAll()
        return (written, nil)
    }

    public mutating func removeAll() {
        events.removeAll()
    }
}
