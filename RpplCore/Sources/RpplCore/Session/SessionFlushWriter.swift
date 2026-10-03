import Foundation

/// The JSONL streams the Watch buffers in memory and flushes together. Motion is separate: it is
/// written once per frame interval and its failure never costs these.
public enum FlushStream: String, Sendable, CaseIterable {
    case locations, health, water, battery
}

public struct FlushOutcome: Sendable, Equatable {
    public var failed: Set<FlushStream>
    /// Message of the last failure; the streams that failed are in `failed`.
    public var error: String?
    /// On-disk size of the session package after the flush; nil when it could not be read.
    public var byteSize: Int64?

    public init(failed: Set<FlushStream> = [], error: String? = nil, byteSize: Int64? = nil) {
        self.failed = failed
        self.error = error
        self.byteSize = byteSize
    }
}

public enum SessionFlushWriter {
    /// Append each non-empty stream on its own and report which ones failed. One failing stream
    /// (full disk, unwritable file) must not cost the others; the caller puts only the failed
    /// batches back in its buffers (`SampleRequeue`) and retries them on the next flush.
    public static func write(
        locations: [LocationSample],
        health: [HealthMetricSample],
        water: [WaterTemperatureSample],
        battery: [BatterySample],
        store: SessionFileStore,
        sessionId: String
    ) -> FlushOutcome {
        var outcome = FlushOutcome()
        func attempt(_ stream: FlushStream, _ write: () throws -> Void) {
            do {
                try write()
            } catch {
                outcome.failed.insert(stream)
                outcome.error = error.localizedDescription
            }
        }
        if !locations.isEmpty {
            attempt(.locations) { try store.appendLocationSamples(locations, sessionId: sessionId) }
        }
        if !health.isEmpty {
            attempt(.health) { try store.appendHealthSamples(health, sessionId: sessionId) }
        }
        if !water.isEmpty {
            attempt(.water) { try store.appendWaterTemperatureSamples(water, sessionId: sessionId) }
        }
        if !battery.isEmpty {
            attempt(.battery) { try store.appendBatterySamples(battery, sessionId: sessionId) }
        }
        outcome.byteSize = try? store.sessionByteSize(sessionId: sessionId)
        return outcome
    }
}
