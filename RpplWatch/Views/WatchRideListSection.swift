import SwiftUI
import RpplCore

/// Compact per-ride stats for Watch logbook detail and session overview.
struct WatchRideListSection: View {
    let rides: [RideSegmentStats]
    var emptyMessage: LocalizedStringKey = "No rides yet"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rides")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if rides.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rides.enumerated()), id: \.element.id) { offset, ride in
                    if offset > 0 {
                        Divider()
                    }
                    WatchRideRow(ride: ride)
                }
            }
        }
    }
}

private struct WatchRideRow: View {
    let ride: RideSegmentStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ride \(ride.index + 1)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            WatchRideMetricLine(
                label: "Duration",
                value: SessionFormatters.rideDuration(ride.duration)
            )
            WatchRideMetricLine(
                label: "Distance",
                value: SessionFormatters.distance(ride.distanceMeters)
            )
            WatchRideMetricLine(
                label: "Laps",
                value: "\(ride.lapCount)"
            )
            if let averageSpeed = ride.averageSpeedKmh {
                WatchRideMetricLine(
                    label: "Avg speed",
                    value: SessionFormatters.averageSpeed(averageSpeed)
                )
            }
        }
    }
}

/// Last finished ride on live session overview (Watch only tracks latest).
struct WatchLastRideSection: View {
    let duration: TimeInterval
    let distanceMeters: Double
    let lapCount: Int
    var didCompleteRide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last ride")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if didCompleteRide {
                WatchRideMetricLine(
                    label: "Duration",
                    value: SessionFormatters.rideDuration(duration)
                )
                WatchRideMetricLine(
                    label: "Distance",
                    value: SessionFormatters.distance(distanceMeters)
                )
                WatchRideMetricLine(
                    label: "Laps",
                    value: "\(lapCount)"
                )
            } else {
                Text("No rides yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WatchRideMetricLine: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
