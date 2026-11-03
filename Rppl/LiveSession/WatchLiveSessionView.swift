import RpplCore
import SwiftUI

/// Live numbers of a session the Apple Watch records: the same figures as on the Watch. Nothing to press:
/// the Watch decides when the session ends.
struct WatchLiveSessionView: View {
    let snapshot: WatchLiveSnapshot

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RpplDesign.tileSpacing) {
                    InfoTileGrid {
                        InfoTile("Session", metric: .duration) { LiveTimer(since: snapshot.startedAt) }
                        InfoTile("Sets", metric: .sets) { MetricValue("\(snapshot.setCount)") }
                        InfoTile("Speed", metric: .speed) {
                            MetricValue(snapshot.speedKmh.map { DistanceFormat.kilometersPerHour($0) } ?? "-", size: .medium)
                        }
                        InfoTile("Heart rate", metric: .heartRate) {
                            MetricValue(snapshot.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "-", size: .medium)
                        }
                        InfoTile("Water", metric: .water) {
                            MetricValue(snapshot.waterCelsius.map { TemperatureFormat.celsius($0) } ?? "-", size: .medium)
                        }
                        InfoTile("Laps", metric: .laps) { MetricValue("\(snapshot.lapCount)") }
                    }
                    if let setStart = snapshot.setStartedAt {
                        InfoTile("Since start of set", metric: .duration) { LiveTimer(since: setStart) }
                    }
                    Text(snapshot.isPaused ? "Paused on Apple Watch." : "Recorded on Apple Watch. Stop the session there.")
                        .font(.footnote)
                        .foregroundStyle(Color.rpplMuted)
                }
                .padding(RpplDesign.tileSpacing)
            }
            .navigationTitle("Session running")
            .navigationBarTitleDisplayMode(.inline)
            .rpplBackdrop()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
