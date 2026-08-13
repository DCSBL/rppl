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

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SpeedPoint: Identifiable, Equatable {
    var id: Int
    var timestamp: Date
    var speedKmh: Double
}

struct AccuracyPoint: Identifiable, Equatable {
    var id: Int
    var timestamp: Date
    var horizontalAccuracy: Double
}

@Observable
@MainActor
final class SessionAnalysisModel {
    static let defaultWindow: TimeInterval = 10 * 60
    static let minimumWindow: TimeInterval = 60

    private(set) var package: AnalysisPackage?
    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var sessionSpan: ClosedRange<Date>?
    private(set) var segments: [AssumptionSegment] = []

    var rangeStart: Date = .now
    var rangeEnd: Date = .now
    var selectedSegmentID: String?

    var selectedRange: ClosedRange<Date> {
        let end = max(rangeStart, rangeEnd)
        return rangeStart...end
    }

    var selectedSegment: AssumptionSegment? {
        guard let selectedSegmentID else { return nil }
        return segments.first { $0.id == selectedSegmentID }
    }

    /// Selection only when it overlaps the visible window (avoids inverted chart marks).
    var visibleHighlight: AssumptionSegment? {
        guard let selectedSegment else { return nil }
        let range = selectedRange
        guard selectedSegment.start < range.upperBound, selectedSegment.end > range.lowerBound else {
            return nil
        }
        return selectedSegment
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
        let seconds = max(0, rangeEnd.timeIntervalSince(rangeStart))
        let minutes = Int(seconds / 60)
        let rem = Int(seconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, rem)
    }

    func load(url: URL) {
        loadError = nil
        selectedSegmentID = nil
        isLoading = true
        package = nil
        segments = []
        sessionSpan = nil

        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try await Task.detached(priority: .userInitiated) {
                    try SessionExportLoader.load(from: data)
                }.value
                apply(package: decoded)
            } catch {
                package = nil
                segments = []
                sessionSpan = nil
                loadError = error.localizedDescription
            }
            isLoading = false
        }
    }

    func reportLoadFailure(_ message: String) {
        loadError = message
        isLoading = false
    }

    func setRangeStart(_ date: Date) {
        guard let sessionSpan else { return }
        let spanLength = sessionSpan.upperBound.timeIntervalSince(sessionSpan.lowerBound)
        guard spanLength >= Self.minimumWindow else { return }
        let maxStart = sessionSpan.upperBound.addingTimeInterval(-Self.minimumWindow)
        let clamped = min(max(date, sessionSpan.lowerBound), maxStart)
        rangeStart = clamped
        if rangeEnd.timeIntervalSince(rangeStart) < Self.minimumWindow {
            rangeEnd = min(rangeStart.addingTimeInterval(Self.minimumWindow), sessionSpan.upperBound)
        }
    }

    func setRangeEnd(_ date: Date) {
        guard let sessionSpan else { return }
        let spanLength = sessionSpan.upperBound.timeIntervalSince(sessionSpan.lowerBound)
        guard spanLength >= Self.minimumWindow else { return }
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
        return package.locations.filter {
            range.contains($0.timestamp)
                && $0.latitude.isFinite
                && $0.longitude.isFinite
        }
    }

    func windowSpeedPoints() -> [SpeedPoint] {
        guard let package else { return [] }
        let range = selectedRange
        let filter = AssumerSignalFilter(thresholds: .default)
        var previousUsable: Double?
        var points: [SpeedPoint] = []

        for sample in package.locations where range.contains(sample.timestamp) {
            let speed = sample.speed
            let usableInput: Double? = {
                guard let speed, speed.isFinite, speed >= 0 else { return nil }
                return speed
            }()
            let accuracy: Double? = sample.horizontalAccuracy.isFinite ? sample.horizontalAccuracy : nil
            let tick = AssumerTick(
                timestamp: sample.timestamp,
                speedMps: usableInput,
                horizontalAccuracy: accuracy
            )
            let outcome = filter.evaluate(tick, previousUsableSpeedMps: previousUsable)
            if let usable = outcome.usableSpeedMps {
                previousUsable = usable
                let kmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: usable)
                guard kmh.isFinite else { continue }
                points.append(SpeedPoint(id: points.count, timestamp: sample.timestamp, speedKmh: kmh))
            }
        }
        return downsample(points, limit: 2_000)
    }

    func windowAccuracyPoints() -> [AccuracyPoint] {
        guard let package else { return [] }
        let range = selectedRange
        var points: [AccuracyPoint] = []
        for sample in package.locations where range.contains(sample.timestamp) {
            let accuracy = sample.horizontalAccuracy
            guard accuracy.isFinite else { continue }
            points.append(
                AccuracyPoint(id: points.count, timestamp: sample.timestamp, horizontalAccuracy: accuracy)
            )
        }
        return downsample(points, limit: 2_000)
    }

    func windowSegments() -> [AssumptionSegment] {
        let range = selectedRange
        return segments.filter {
            $0.duration > 0
                && $0.start < range.upperBound
                && $0.end > range.lowerBound
        }
    }

    private func apply(package: AnalysisPackage) {
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
        let upper = max(
            upperCandidates.max() ?? lower.addingTimeInterval(Self.defaultWindow),
            lower.addingTimeInterval(Self.minimumWindow)
        )
        sessionSpan = lower...upper
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
        return sorted.enumerated().compactMap { index, event in
            let rawEnd = index + 1 < sorted.count ? sorted[index + 1].timestamp : sessionEnd
            let end = max(rawEnd, event.timestamp)
            // Skip zero-length (duplicate timestamps) — Charts traps on xStart==xEnd marks.
            guard end > event.timestamp else { return nil }
            return AssumptionSegment(
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

    private func downsample<T>(_ points: [T], limit: Int) -> [T] {
        guard points.count > limit, limit > 1 else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { index in
            points[min(points.count - 1, Int((Double(index) * step).rounded()))]
        }
    }
}
