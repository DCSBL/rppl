import Foundation

/// GPS for one detected set, kept paired with the set it came from.
///
/// `SetLocationFilter.tracks(from:sets:)` drops sets without a usable track, so its
/// output can no longer be indexed against `stats.sets`. Map layers that label or
/// color per set need that pairing, so it travels with the samples here.
public struct SessionSetTrack: Equatable, Sendable {
    /// Position in the `sets` array the track was built from.
    public var setIndex: Int
    /// Display number from `SetSegmentStats.index`.
    public var setNumber: Int
    public var samples: [LocationSample]

    public init(setIndex: Int, setNumber: Int, samples: [LocationSample]) {
        self.setIndex = setIndex
        self.setNumber = setNumber
        self.samples = samples
    }

    public var isRenderable: Bool { samples.count >= 2 }
}

public enum SessionSetTrackBuilder {
    /// Total points across all sets a map layer should carry.
    public static let defaultPointBudget = 900
    /// Floor per set so a short set still draws as a line.
    public static let minimumPointsPerSet = 24

    /// One downsampled track per set with GPS, in set order.
    public static func tracks(
        locations: [LocationSample],
        sets: [SetSegmentStats],
        pointBudget: Int = defaultPointBudget
    ) -> [SessionSetTrack] {
        guard !locations.isEmpty, !sets.isEmpty else { return [] }
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        let perSetBudget = max(minimumPointsPerSet, pointBudget / max(sets.count, 1))

        var tracks: [SessionSetTrack] = []
        for (offset, set) in sets.enumerated() {
            let samples = SetLocationFilter.samples(in: sorted, from: set.startedAt, to: set.endedAt)
            guard samples.count >= 2 else { continue }
            tracks.append(
                SessionSetTrack(
                    setIndex: offset,
                    setNumber: set.index,
                    samples: LocationSampleDownsampler.downsample(samples, maxCount: perSetBudget)
                )
            )
        }
        return tracks
    }
}
