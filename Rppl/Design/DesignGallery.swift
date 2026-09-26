import SwiftUI
import RpplCore

/// Preview-only catalog of the tile primitives with realistic session numbers.
private struct DesignGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RpplDesign.tileSpacing) {
                totalsTile

                InfoTileGrid {
                    InfoTile("Max speed", metric: .speed) {
                        MetricValue(LogbookFormatting.speedKilometersPerHour(42.2))
                        Gauge(value: MetricDisplay.fraction(28.5, of: 42.2)) {
                            Text("Avg speed")
                        }
                        .gaugeStyle(.rpplBar(tint: MetricKind.speed.tint))
                        StatChip(
                            metric: .speed,
                            value: LogbookFormatting.speedKilometersPerHour(28.5),
                            caption: "Avg speed"
                        )
                    }

                    InfoTile("Riding", metric: .riding) {
                        Gauge(value: 0.27) {
                            Text("Riding")
                        } currentValueLabel: {
                            Text(verbatim: "27%")
                        }
                        .gaugeStyle(.rpplRing(tint: MetricKind.riding.tint))
                        .frame(maxWidth: 110)
                        .frame(maxWidth: .infinity)
                    }

                    InfoTile("Sets", metric: .sets) {
                        MetricValue("10")
                        SegmentDots(count: 10, tint: MetricKind.sets.tint)
                    }

                    InfoTile("Distance", metric: .distance) {
                        MetricValue(LogbookFormatting.distanceKilometers(14_000))
                        StatChip(metric: .duration, value: LogbookFormatting.duration(6_585))
                    }
                }

                HStack(spacing: 20) {
                    StatChip(metric: .distance, value: LogbookFormatting.distanceKilometers(14_000), caption: "Distance")
                    StatChip(metric: .sets, value: "10", caption: "Sets")
                    StatChip(metric: .laps, value: "15", caption: "Laps")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rpplTileChrome()

                SegmentDots(count: 40, tint: MetricKind.sets.tint)
                    .rpplTileChrome()
            }
            .padding(16)
        }
        .rpplBackdrop()
    }

    private var totalsTile: some View {
        InfoTile("Total", metric: .riding) {
            HStack(alignment: .firstTextBaseline) {
                totalMetric(value: "4", label: "Sessions")
                totalMetric(value: LogbookFormatting.distanceKilometers(61_000), label: "Distance")
                totalMetric(value: LogbookFormatting.speedKilometersPerHour(45), label: "Max speed")
            }
            Gauge(value: MetricDisplay.fraction(51, of: 66)) {
                Text("Sets")
            }
            .gaugeStyle(.rpplBar(tint: MetricKind.sets.tint))
            Gauge(value: 1) {
                Text("Laps")
            }
            .gaugeStyle(.rpplBar(tint: MetricKind.laps.tint))
        }
    }

    private func totalMetric(value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MetricValue(value, size: .medium)
            Text(label)
                .font(.caption)
                .foregroundStyle(RpplDesign.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Tiles — light") {
    DesignGallery()
        .preferredColorScheme(.light)
}

#Preview("Tiles — dark") {
    DesignGallery()
        .preferredColorScheme(.dark)
}

#Preview("Tiles — accessibility size") {
    DesignGallery()
        .environment(\.dynamicTypeSize, .accessibility2)
}
