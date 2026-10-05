import Foundation

/// Precompiles the bundled empty-state example session.
///
/// A raw Share export is ~20 MB (GPS, health, motion). Decoding and analyzing it on every open
/// of the example took most of a second on a Mac and far more on a Watch. The compiled form keeps
/// only what the logbook detail draws: stats computed once and stored in `derived`, plus the GPS
/// inside each set at the set card's map budget.
///
/// Regenerate the bundled file with `scripts/prepare-example-session.sh` whenever
/// `SessionAnalyzer.version` changes (a Core test fails until you do).
public enum ExampleSessionCompiler {
    /// Most GPS points kept per set; matches the budget the set card's map draws.
    public static let setPointBudget = 200

    /// Raw export → display-only package with current-analyzer stats in `derived`.
    ///
    /// `mapFrame` and `cityName` stay nil, as when the example was analyzed on open.
    public static func compile(_ package: SessionTransferPackage) -> SessionTransferPackage {
        let stats = SessionStatsBuilder.build(
            manifest: package.manifest,
            detections: package.detections,
            locations: package.locations,
            health: package.health,
            water: package.water
        )
        let sorted = package.locations.sorted { $0.timestamp < $1.timestamp }
        let locations = stats.sets.flatMap { set in
            LocationSampleDownsampler.downsample(
                SetLocationFilter.trackSamples(in: sorted, from: set.startedAt, to: set.endedAt),
                maxCount: setPointBudget
            )
        }
        return SessionTransferPackage(
            manifest: package.manifest,
            detections: package.detections,
            locations: locations,
            health: [],
            derived: DerivedSessionView(stats: stats)
        )
    }
}
