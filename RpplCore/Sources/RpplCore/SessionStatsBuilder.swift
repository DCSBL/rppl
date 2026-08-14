import Foundation

/// Builds derived session stats from on-disk streams (not persisted).
public enum SessionStatsBuilder {
    public static func build(
        manifest: SessionManifest,
        detections: [DetectionEvent],
        locations: [LocationSample],
        health: [HealthMetricSample],
        maxHorizontalAccuracyM: Double = DetectionThresholds.default.maxHorizontalAccuracyM
    ) -> SessionStats {
        let sessionStart = manifest.startedAt
        let sessionEnd = manifest.endedAt ?? inferSessionEnd(
            manifest: manifest,
            detections: detections,
            locations: locations,
            health: health
        )

        let effective = Self.effectiveEvents(detections)
        let phases = Self.buildAttributedPhases(
            effectiveEvents: effective,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )

        let ridingDuration = phases
            .filter { $0.attributedCode == DetectionCodes.riding }
            .reduce(0) { $0 + $1.duration }
        let pausedDuration = phases
            .filter { $0.attributedCode == DetectionCodes.paused }
            .reduce(0) { $0 + $1.duration }
        let activeDuration = ridingDuration + pausedDuration
        let ratio = activeDuration > 0 ? ridingDuration / activeDuration : 0

        let rideWindows = Self.rideWindows(from: phases)
        let sortedLocations = locations.sorted { $0.timestamp < $1.timestamp }
        var rides: [RideSegmentStats] = []
        var totalDistance = 0.0

        for (index, window) in rideWindows.enumerated() {
            let distance = Self.distanceMeters(
                locations: sortedLocations,
                from: window.start,
                to: window.end,
                maxHorizontalAccuracyM: maxHorizontalAccuracyM
            )
            let duration = window.end.timeIntervalSince(window.start)
            rides.append(
                RideSegmentStats(
                    index: index + 1,
                    startedAt: window.start,
                    endedAt: window.end,
                    duration: max(0, duration),
                    distanceMeters: distance
                )
            )
            totalDistance += distance
        }

        let calories = health.compactMap(\.activeEnergyKilocalories).max()

        return SessionStats(
            startedAt: sessionStart,
            endedAt: sessionEnd,
            totalDuration: max(0, sessionEnd.timeIntervalSince(sessionStart)),
            totalDistanceMeters: totalDistance,
            activeEnergyKilocalories: calories,
            rideCount: rides.count,
            ridingDuration: ridingDuration,
            pausedDuration: pausedDuration,
            ridingPausedRatio: ratio,
            rides: rides
        )
    }

    // MARK: - Detection timeline

    struct AttributedPhase: Equatable {
        var attributedCode: String
        var start: Date
        var end: Date

        var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }

    struct TimeWindow: Equatable {
        var start: Date
        var end: Date
    }

    static func effectiveEvents(_ events: [DetectionEvent]) -> [DetectionEvent] {
        let superseded = Set(events.compactMap(\.supersedesId))
        return events
            .filter { !superseded.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    static func buildAttributedPhases(
        effectiveEvents: [DetectionEvent],
        sessionStart: Date,
        sessionEnd: Date
    ) -> [AttributedPhase] {
        var phases: [AttributedPhase] = []
        var currentCode = DetectionCodes.paused
        var lastConfident = DetectionCodes.paused
        var intervalStart = sessionStart

        for event in effectiveEvents {
            let end = min(event.timestamp, sessionEnd)
            if end > intervalStart {
                phases.append(
                    AttributedPhase(
                        attributedCode: attributed(currentCode, lastConfident: lastConfident),
                        start: intervalStart,
                        end: end
                    )
                )
            }
            currentCode = event.code
            if DetectionCodes.isConfident(event.code) {
                lastConfident = event.code
            }
            intervalStart = max(event.timestamp, sessionStart)
        }

        if sessionEnd > intervalStart {
            phases.append(
                AttributedPhase(
                    attributedCode: attributed(currentCode, lastConfident: lastConfident),
                    start: intervalStart,
                    end: sessionEnd
                )
            )
        }

        return mergeAdjacentPhases(phases)
    }

    static func attributed(_ code: String, lastConfident: String) -> String {
        code == DetectionCodes.unsure ? lastConfident : code
    }

    static func mergeAdjacentPhases(_ phases: [AttributedPhase]) -> [AttributedPhase] {
        var merged: [AttributedPhase] = []
        for phase in phases {
            guard phase.duration > 0 else { continue }
            if var last = merged.popLast() {
                if last.attributedCode == phase.attributedCode, last.end == phase.start {
                    last.end = phase.end
                    merged.append(last)
                } else {
                    merged.append(last)
                    merged.append(phase)
                }
            } else {
                merged.append(phase)
            }
        }
        return merged
    }

    static func rideWindows(from phases: [AttributedPhase]) -> [TimeWindow] {
        phases
            .filter { $0.attributedCode == DetectionCodes.riding }
            .map { TimeWindow(start: $0.start, end: $0.end) }
    }

    // MARK: - Distance

    static func distanceMeters(
        locations: [LocationSample],
        from windowStart: Date,
        to windowEnd: Date,
        maxHorizontalAccuracyM: Double
    ) -> Double {
        let inWindow = locations.filter { sample in
            sample.timestamp >= windowStart && sample.timestamp <= windowEnd
        }
        guard inWindow.count >= 2 else { return 0 }

        var total = 0.0
        var previous: LocationSample?
        for sample in inWindow {
            defer { previous = sample }
            guard let from = previous else { continue }
            guard GeoDistance.acceptsStep(from: from, to: sample, maxHorizontalAccuracyM: maxHorizontalAccuracyM)
            else {
                continue
            }
            total += GeoDistance.meters(
                fromLat: from.latitude,
                fromLon: from.longitude,
                toLat: sample.latitude,
                toLon: sample.longitude
            )
        }
        return total
    }

    static func inferSessionEnd(
        manifest: SessionManifest,
        detections: [DetectionEvent],
        locations: [LocationSample],
        health: [HealthMetricSample]
    ) -> Date {
        var candidates = [manifest.startedAt]
        if let ended = manifest.endedAt {
            candidates.append(ended)
        }
        candidates.append(contentsOf: detections.map(\.timestamp))
        candidates.append(contentsOf: locations.map(\.timestamp))
        candidates.append(contentsOf: health.map(\.timestamp))
        return candidates.max() ?? manifest.startedAt
    }
}
