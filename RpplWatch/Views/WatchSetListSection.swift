import SwiftUI
import RpplCore

/// Compact per-set stats for Watch logbook detail and session overview.
struct WatchSetListSection: View {
    let sets: [SetSegmentStats]
    var emptyMessage: LocalizedStringKey = "No sets yet"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sets")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if sets.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(sets.enumerated()), id: \.element.id) { offset, set in
                    if offset > 0 {
                        Divider()
                    }
                    WatchSetRow(set: set)
                }
            }
        }
    }
}

private struct WatchSetRow: View {
    let set: SetSegmentStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set \(set.index)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            WatchSetMetricLine(
                label: "Duration",
                value: SessionFormatters.segmentDuration(set.duration)
            )
            WatchSetMetricLine(
                label: "Distance",
                value: SessionFormatters.distance(set.distanceMeters)
            )
            WatchSetMetricLine(
                label: "Laps",
                value: "\(set.lapCount)"
            )
            if let averageSpeed = set.averageSpeedKmh {
                WatchSetMetricLine(
                    label: "Avg speed",
                    value: SessionFormatters.averageSpeed(averageSpeed)
                )
            }
        }
    }
}

/// Last finished set on live session overview (Watch only tracks latest).
struct WatchLastSetSection: View {
    let duration: TimeInterval
    let distanceMeters: Double
    let lapCount: Int
    var didCompleteSet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last set")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if didCompleteSet {
                WatchSetMetricLine(
                    label: "Duration",
                    value: SessionFormatters.segmentDuration(duration)
                )
                WatchSetMetricLine(
                    label: "Distance",
                    value: SessionFormatters.distance(distanceMeters)
                )
                WatchSetMetricLine(
                    label: "Laps",
                    value: "\(lapCount)"
                )
            } else {
                Text("No sets yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WatchSetMetricLine: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }
}
