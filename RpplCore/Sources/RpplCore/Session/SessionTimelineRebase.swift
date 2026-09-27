import Foundation

/// Shifts a transfer package so session end aligns to a target instant.
/// Used by the bundled example session: open → `endedAt` is now; earlier samples stay relative.
public enum SessionTimelineRebase {
    /// Copy of `package` with every timeline date moved by `endAt − endAnchor`.
    ///
    /// End anchor is `manifest.endedAt` when set; otherwise the latest sample/event time
    /// (falling back to `manifest.startedAt`). `motionFramesZlib` is left unchanged —
    /// display loads do not use compressed motion timestamps.
    public static func package(
        _ package: SessionTransferPackage,
        soEndedAt endAt: Date
    ) -> SessionTransferPackage {
        let anchor = endAnchor(for: package)
        let delta = endAt.timeIntervalSince(anchor)
        guard delta != 0 else { return package }

        var result = package
        result.manifest.startedAt = package.manifest.startedAt.addingTimeInterval(delta)
        if let ended = package.manifest.endedAt {
            result.manifest.endedAt = ended.addingTimeInterval(delta)
        } else {
            result.manifest.endedAt = endAt
        }
        result.detections = package.detections.map { shift($0, by: delta) }
        result.locations = package.locations.map { shift($0, by: delta) }
        result.motion = package.motion.map { shift($0, by: delta) }
        result.health = package.health.map { shift($0, by: delta) }
        result.water = package.water.map { shift($0, by: delta) }
        result.battery = package.battery.map { shift($0, by: delta) }
        if let derived = package.derived {
            result.derived = DerivedSessionView(
                analyzerVersion: derived.analyzerVersion,
                stats: shift(derived.stats, by: delta),
                mapFrame: derived.mapFrame,
                cityName: derived.cityName
            )
        }
        return result
    }

    private static func endAnchor(for package: SessionTransferPackage) -> Date {
        if let ended = package.manifest.endedAt {
            return ended
        }
        var latest = package.manifest.startedAt
        for event in package.detections {
            latest = max(latest, event.timestamp)
        }
        for sample in package.locations {
            latest = max(latest, sample.timestamp)
        }
        for sample in package.motion {
            latest = max(latest, sample.timestamp)
        }
        for sample in package.health {
            latest = max(latest, sample.timestamp)
        }
        for sample in package.water {
            latest = max(latest, sample.timestamp)
        }
        for sample in package.battery {
            latest = max(latest, sample.timestamp)
        }
        if let derived = package.derived {
            latest = max(latest, derived.stats.endedAt)
        }
        return latest
    }

    private static func shift(_ event: DetectionEvent, by delta: TimeInterval) -> DetectionEvent {
        var copy = event
        copy.timestamp = event.timestamp.addingTimeInterval(delta)
        return copy
    }

    private static func shift(_ sample: LocationSample, by delta: TimeInterval) -> LocationSample {
        var copy = sample
        copy.timestamp = sample.timestamp.addingTimeInterval(delta)
        return copy
    }

    private static func shift(_ sample: MotionSample, by delta: TimeInterval) -> MotionSample {
        var copy = sample
        copy.timestamp = sample.timestamp.addingTimeInterval(delta)
        return copy
    }

    private static func shift(_ sample: HealthMetricSample, by delta: TimeInterval) -> HealthMetricSample {
        var copy = sample
        copy.timestamp = sample.timestamp.addingTimeInterval(delta)
        return copy
    }

    private static func shift(_ sample: WaterTemperatureSample, by delta: TimeInterval) -> WaterTemperatureSample {
        var copy = sample
        copy.timestamp = sample.timestamp.addingTimeInterval(delta)
        return copy
    }

    private static func shift(_ sample: BatterySample, by delta: TimeInterval) -> BatterySample {
        var copy = sample
        copy.timestamp = sample.timestamp.addingTimeInterval(delta)
        return copy
    }

    private static func shift(_ stats: SessionStats, by delta: TimeInterval) -> SessionStats {
        SessionStats(
            startedAt: stats.startedAt.addingTimeInterval(delta),
            endedAt: stats.endedAt.addingTimeInterval(delta),
            totalDuration: stats.totalDuration,
            totalDistanceMeters: stats.totalDistanceMeters,
            activeEnergyKilocalories: stats.activeEnergyKilocalories,
            totalEnergyKilocalories: stats.totalEnergyKilocalories,
            setCount: stats.setCount,
            ridingDuration: stats.ridingDuration,
            inactiveDuration: stats.inactiveDuration,
            ridingInactiveRatio: stats.ridingInactiveRatio,
            sets: stats.sets.map { shift($0, by: delta) },
            averageWaterTemperatureCelsius: stats.averageWaterTemperatureCelsius,
            waterTemperatureAvailable: stats.waterTemperatureAvailable,
            cableSpeedKmh: stats.cableSpeedKmh
        )
    }

    private static func shift(_ set: SetSegmentStats, by delta: TimeInterval) -> SetSegmentStats {
        SetSegmentStats(
            index: set.index,
            startedAt: set.startedAt.addingTimeInterval(delta),
            endedAt: set.endedAt.addingTimeInterval(delta),
            duration: set.duration,
            distanceMeters: set.distanceMeters,
            lapCount: set.lapCount,
            sustainedSpeedKmh: set.sustainedSpeedKmh,
            averageSpeedKmh: set.averageSpeedKmh,
            peakSpeedKmh: set.peakSpeedKmh,
            cableSpeedKmh: set.cableSpeedKmh,
            highlights: set.highlights
        )
    }
}
