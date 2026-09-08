import Foundation

/// Color ramp scale for a speed-colored track.
///
/// Bands are relative to the session's own speed spread (robust percentiles), not to
/// absolute km/h. A slow park day and a fast one both use the full ramp, and no display
/// constant has to be invented next to the detection thresholds.
public struct TrackSpeedScale: Equatable, Sendable {
    public var lowKmh: Double
    public var highKmh: Double
    public var bandCount: Int

    public init(lowKmh: Double, highKmh: Double, bandCount: Int) {
        self.bandCount = max(2, bandCount)
        self.lowKmh = lowKmh
        // Keep a usable spread so a near-constant track still gets mid-ramp color.
        self.highKmh = max(highKmh, lowKmh + TrackSpeedBands.minimumSpreadKmh)
    }

    /// Position of a speed on the ramp, clamped to 0…1.
    public func fraction(forSpeedKmh speedKmh: Double) -> Double {
        let span = highKmh - lowKmh
        guard span > 0 else { return 0.5 }
        return min(max((speedKmh - lowKmh) / span, 0), 1)
    }

    /// Band a speed falls into, 0 (slowest) … `bandCount - 1` (fastest).
    public func bandIndex(forSpeedKmh speedKmh: Double) -> Int {
        let scaled = fraction(forSpeedKmh: speedKmh) * Double(bandCount)
        return min(Int(scaled), bandCount - 1)
    }

    /// Mid-band ramp position, for painting a whole band one color.
    public func bandFraction(_ index: Int) -> Double {
        let clamped = min(max(index, 0), bandCount - 1)
        return (Double(clamped) + 0.5) / Double(bandCount)
    }

    public func bandLowerKmh(_ index: Int) -> Double {
        let clamped = min(max(index, 0), bandCount - 1)
        return lowKmh + (highKmh - lowKmh) * Double(clamped) / Double(bandCount)
    }
}

/// One run of consecutive track points sharing a speed band.
public struct TrackSpeedRun: Equatable, Sendable {
    public var bandIndex: Int
    public var coordinates: [MapCoordinate]

    public init(bandIndex: Int, coordinates: [MapCoordinate]) {
        self.bandIndex = bandIndex
        self.coordinates = coordinates
    }
}

/// Splits tracks into speed-banded runs so a map can stroke each run its own color.
public enum TrackSpeedBands {
    public static let defaultBandCount = 6
    /// Smallest low→high spread (km/h) a scale may report.
    public static let minimumSpreadKmh = 6.0

    /// Ramp scale across every set of a session. Nil when no usable GPS speed exists.
    public static func scale(
        forTracks tracks: [[LocationSample]],
        bandCount: Int = defaultBandCount,
        thresholds: DetectionThresholds = .default
    ) -> TrackSpeedScale? {
        var speeds: [Double?] = []
        for track in tracks {
            speeds.append(contentsOf: TrackSpeedSeries.speedsKmh(for: track, thresholds: thresholds))
        }
        guard let range = TrackSpeedSeries.percentileRangeKmh(speeds) else { return nil }
        return TrackSpeedScale(lowKmh: range.low, highKmh: range.high, bandCount: bandCount)
    }

    /// Banded runs for one track. Consecutive runs share a point so the line stays joined.
    /// Points with no usable speed inherit the previous band rather than breaking the line.
    public static func runs(
        from locations: [LocationSample],
        scale: TrackSpeedScale,
        thresholds: DetectionThresholds = .default
    ) -> [TrackSpeedRun] {
        guard locations.count >= 2 else { return [] }
        let speeds = TrackSpeedSeries.speedsKmh(for: locations, thresholds: thresholds)
        let fallbackBand = scale.bandIndex(forSpeedKmh: scale.lowKmh)

        var runs: [TrackSpeedRun] = []
        var currentBand = fallbackBand
        var currentPoints: [MapCoordinate] = []

        for index in locations.indices {
            let band = speeds[index].map { scale.bandIndex(forSpeedKmh: $0) } ?? currentBand
            let point = MapCoordinate(locations[index])

            if currentPoints.isEmpty {
                currentBand = band
                currentPoints = [point]
                continue
            }
            if band == currentBand {
                currentPoints.append(point)
                continue
            }
            // Close the run on the boundary point, then reopen from it in the new band.
            currentPoints.append(point)
            runs.append(TrackSpeedRun(bandIndex: currentBand, coordinates: currentPoints))
            currentBand = band
            currentPoints = [point]
        }

        if currentPoints.count >= 2 {
            runs.append(TrackSpeedRun(bandIndex: currentBand, coordinates: currentPoints))
        }
        return runs
    }
}
