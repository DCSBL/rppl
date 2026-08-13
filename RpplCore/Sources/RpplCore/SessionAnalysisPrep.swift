import Foundation

/// Pure helpers shared by Mac analyser UI and Core tests.
public enum SessionAnalysisPrep {
    public static let defaultWindow: TimeInterval = 10 * 60
    public static let minimumWindow: TimeInterval = 60

    public struct Segment: Equatable, Sendable, Identifiable {
        public var id: String
        public var code: String
        public var start: Date
        public var end: Date
        public var reason: String
        public var speedMps: Double?
        public var waterSubmersionState: String?
        public var motionActivity: String?

        public var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    public static func sessionSpan(
        manifest: SessionManifest,
        locations: [LocationSample],
        assumptions: [AssumptionEvent]
    ) -> ClosedRange<Date> {
        let locationTimes = locations.map(\.timestamp)
        let assumptionTimes = assumptions.map(\.timestamp)
        let lower = [
            manifest.startedAt,
            locationTimes.min(),
            assumptionTimes.min()
        ].compactMap { $0 }.min() ?? manifest.startedAt
        let upperCandidates: [Date] = [
            manifest.endedAt,
            locationTimes.max(),
            assumptionTimes.max()
        ].compactMap { $0 }
        let upper = max(
            upperCandidates.max() ?? lower.addingTimeInterval(defaultWindow),
            lower.addingTimeInterval(minimumWindow)
        )
        return lower...upper
    }

    public static func defaultSelection(span: ClosedRange<Date>) -> ClosedRange<Date> {
        let lower = span.lowerBound
        let upper = span.upperBound
        let defaultEnd = min(lower.addingTimeInterval(defaultWindow), upper)
        let end = max(defaultEnd, lower.addingTimeInterval(minimumWindow))
        return lower...end
    }

    public static func segments(
        assumptions: [AssumptionEvent],
        sessionEnd: Date
    ) -> [Segment] {
        let sorted = assumptions.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return [] }
        return sorted.enumerated().compactMap { index, event in
            let rawEnd = index + 1 < sorted.count ? sorted[index + 1].timestamp : sessionEnd
            let end = max(rawEnd, event.timestamp)
            guard end > event.timestamp else { return nil }
            return Segment(
                id: event.id.isEmpty ? "assumption-\(index)" : event.id,
                code: event.code,
                start: event.timestamp,
                end: end,
                reason: event.reason,
                speedMps: event.speedMps,
                waterSubmersionState: event.waterSubmersionState,
                motionActivity: event.motionActivity
            )
        }
    }

    public static func clippedBand(
        start: Date,
        end: Date,
        range: ClosedRange<Date>
    ) -> ClosedRange<Date>? {
        let lo = max(start, range.lowerBound)
        let hi = min(end, range.upperBound)
        guard hi > lo else { return nil }
        return lo...hi
    }
}
