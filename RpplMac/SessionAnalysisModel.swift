import Foundation
import RpplCore
import Observation

struct AssumptionSegment: Identifiable, Equatable {
    var id: String
    var code: String
    var start: Date
    var end: Date
    var reason: String
    var speedMps: Double?
    var waterSubmersionState: String?
    var motionActivity: String?
}

struct SpeedPoint: Identifiable, Equatable {
    var id: Date { timestamp }
    var timestamp: Date
    var speedKmh: Double
}

struct AccuracyPoint: Identifiable, Equatable {
    var id: Date { timestamp }
    var timestamp: Date
    var horizontalAccuracy: Double
}

@Observable
@MainActor
final class SessionAnalysisModel {
    static let defaultWindow: TimeInterval = 10 * 60
    static let minimumWindow: TimeInterval = 60

    private(set) var package: SessionTransferPackage?
    private(set) var loadError: String?
    private(set) var sessionSpan: ClosedRange<Date>?
    private(set) var segments: [AssumptionSegment] = []

    var rangeStart: Date = .now
    var rangeEnd: Date = .now
    var selectedSegmentID: String?

    var selectedRange: ClosedRange<Date> {
        rangeStart...max(rangeStart, rangeEnd)
    }

    var selectedSegment: AssumptionSegment? {
        guard let selectedSegmentID else { return nil }
        return segments.first { $0.id == selectedSegmentID }
    }

    var sessionTitle: String {
        guard let package else { return "No session" }
        return package.manifest.sessionId
    }

    var durationLabel: String {
        guard let sessionSpan else { return "—" }
        let seconds = sessionSpan.upperBound.timeIntervalSince(sessionSpan.lowerBound)
        let minutes = Int(seconds / 60)
        let rem = Int(seconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, rem)
    }

    var windowDurationLabel: String {
        let seconds = rangeEnd.timeIntervalSince(rangeStart)
        let minutes = Int(seconds / 60)
        let rem = Int(seconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, rem)
    }

    func load(url: URL) {
        loadError = nil
        selectedSegmentID = nil
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(SessionTransferPackage.self, from: data)
            apply(package: decoded)
        } catch {
            package = nil
            segments = []
            sessionSpan = nil
            loadError = error.localizedDescription
        }
    }

    func reportLoadFailure(_ message: String) {
        loadError = message
    }

    func setRangeStart(_ date: Date) {
        guard let sessionSpan else { return }
        let maxStart = sessionSpan.upperBound.addingTimeInterval(-Self.minimumWindow)
        let clamped = min(max(date, sessionSpan.lowerBound), maxStart)
        rangeStart = clamped
        if rangeEnd.timeIntervalSince(rangeStart) < Self.minimumWindow {
            rangeEnd = min(rangeStart.addingTimeInterval(Self.minimumWindow), sessionSpan.upperBound)
        }
    }

    func setRangeEnd(_ date: Date) {
        guard let sessionSpan else { return }
        let minEnd = sessionSpan.lowerBound.addingTimeInterval(Self.minimumWindow)
        let clamped = max(min(date, sessionSpan.upperBound), minEnd)
        rangeEnd = clamped
        if rangeEnd.timeIntervalSince(rangeStart) < Self.minimumWindow {
            rangeStart = max(rangeEnd.addingTimeInterval(-Self.minimumWindow), sessionSpan.lowerBound)
        }
    }

    func selectAssumption(at date: Date) {
        selectedSegmentID = segments.first { $0.start <= date && date < $0.end }?.id
    }

    func windowLocations() -> [LocationSample] {
        guard let package else { return [] }
        let range = selectedRange
        return package.locations.filter { range.contains($0.timestamp) }
    }

    func windowSpeedPoints() -> [SpeedPoint] {
        guard let package else { return [] }
        let range = selectedRange
        let thresholds = AssumptionThresholds.default
        let filter = AssumerSignalFilter(thresholds: thresholds)
        var previousUsable: Double?
        var points: [SpeedPoint] = []

        for sample in package.locations where range.contains(sample.timestamp) {
            let speed = sample.speed
            let tick = AssumerTick(
                timestamp: sample.timestamp,
                speedMps: (speed != nil && speed! >= 0) ? speed : nil,
                horizontalAccuracy: sample.horizontalAccuracy
            )
            let outcome = filter.evaluate(tick, previousUsableSpeedMps: previousUsable)
            if let usable = outcome.usableSpeedMps {
                previousUsable = usable
                points.append(
                    SpeedPoint(
                        timestamp: sample.timestamp,
                        speedKmh: SpeedUnits.kilometersPerHour(fromMetersPerSecond: usable)
                    )
                )
            }
        }
        return downsample(points, limit: 2_000)
    }

    func windowAccuracyPoints() -> [AccuracyPoint] {
        guard let package else { return [] }
        let range = selectedRange
        let points = package.locations
            .filter { range.contains($0.timestamp) }
            .map {
                AccuracyPoint(timestamp: $0.timestamp, horizontalAccuracy: $0.horizontalAccuracy)
            }
        return downsample(points, limit: 2_000)
    }

    func windowSegments() -> [AssumptionSegment] {
        let range = selectedRange
        return segments.filter { $0.start < range.upperBound && $0.end > range.lowerBound }
    }

    private func apply(package: SessionTransferPackage) {
        self.package = package
        let manifest = package.manifest
        let locationTimes = package.locations.map(\.timestamp)
        let assumptionTimes = package.assumptions.map(\.timestamp)
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
        let upper = max(upperCandidates.max() ?? lower.addingTimeInterval(Self.defaultWindow), lower.addingTimeInterval(Self.minimumWindow))
        let span = lower...upper
        sessionSpan = span
        segments = Self.buildSegments(assumptions: package.assumptions, sessionEnd: upper)

        let defaultEnd = min(lower.addingTimeInterval(Self.defaultWindow), upper)
        rangeStart = lower
        rangeEnd = max(defaultEnd, lower.addingTimeInterval(Self.minimumWindow))
    }

    private static func buildSegments(
        assumptions: [AssumptionEvent],
        sessionEnd: Date
    ) -> [AssumptionSegment] {
        let sorted = assumptions.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return [] }
        return sorted.enumerated().map { index, event in
            let end = index + 1 < sorted.count ? sorted[index + 1].timestamp : sessionEnd
            return AssumptionSegment(
                id: event.id,
                code: event.code,
                start: event.timestamp,
                end: max(end, event.timestamp),
                reason: event.reason,
                speedMps: event.speedMps,
                waterSubmersionState: event.waterSubmersionState,
                motionActivity: event.motionActivity
            )
        }
    }

    private func downsample<T>(_ points: [T], limit: Int) -> [T] {
        guard points.count > limit, limit > 1 else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { index in
            points[min(points.count - 1, Int((Double(index) * step).rounded()))]
        }
    }
}
