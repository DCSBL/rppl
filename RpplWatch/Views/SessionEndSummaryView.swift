import SwiftUI
import MapKit
import RpplCore

/// Post-stop session recap: stats, start map, sync line, Done → idle.
struct SessionEndSummaryView: View {
    let summary: EndedSessionSummary
    @Bindable var session: WatchSessionController
    @Bindable var transfer: WatchTransferService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchSessionMapPreview(
                    startCoordinate: startCoordinate,
                    mapFrame: nil
                )

                Text("Session complete")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(SessionFormatters.elapsed(summary.duration))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(Color.rpplIdlePrimary)

                SessionMetricRow(
                    label: "Distance",
                    value: SessionFormatters.distance(summary.distanceMeters)
                )
                SessionMetricRow(
                    label: "Rides",
                    value: "\(summary.rideCount)"
                )

                Divider()
                    .padding(.vertical, 2)

                WatchLastRideSection(
                    duration: summary.lastRideDuration,
                    distanceMeters: summary.lastRideMeters,
                    lapCount: summary.lastRideLapCount,
                    didCompleteRide: summary.didCompleteRide
                )

                syncLine
                    .padding(.top, 4)

                Button("Done") {
                    session.dismissSessionSummary()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.rpplIdleAccent)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .containerBackground(Color.rpplIdleBackground.gradient, for: .tabView)
        .preferredColorScheme(.dark)
        .onAppear {
            transfer.refreshPendingCount()
        }
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        guard let latitude = summary.startLatitude, let longitude = summary.startLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var syncLine: some View {
        let synced = transfer.isSessionSynced(sessionId: summary.sessionId)
        _ = transfer.syncStatusRevision
        return HStack(spacing: 6) {
            Circle()
                .fill(synced ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(synced ? String(localized: "Synced") : String(localized: "Syncing…"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            synced
                ? String(localized: "Synced to iPhone")
                : String(localized: "Syncing to iPhone")
        )
    }
}

#Preview {
    SessionEndSummaryView(
        summary: EndedSessionSummary(
            sessionId: "preview",
            duration: 3725,
            rideCount: 4,
            distanceMeters: 2840,
            lastRideDuration: 312,
            lastRideMeters: 720,
            lastRideLapCount: 2,
            didCompleteRide: true,
            startLatitude: 51.9794,
            startLongitude: 4.5740
        ),
        session: WatchSessionController.shared,
        transfer: WatchTransferService.shared
    )
}
