import SwiftUI
import MapKit
import RpplCore

/// Post-stop session recap: stats, start map, sync line, Done → idle.
struct SessionEndSummaryView: View {
    let summary: EndedSessionSummary
    @Bindable var session: WatchSessionController
    @Bindable var transfer: WatchTransferService

    private static let mapHeight: CGFloat = 96
    private static let startMapDistanceMeters: CLLocationDistance = 500

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    startMapStrip

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

                    HStack(alignment: .top, spacing: 12) {
                        SessionMetricRow(
                            label: "Distance",
                            value: SessionFormatters.distance(summary.distanceMeters)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        SessionMetricRow(
                            label: "Rides",
                            value: "\(summary.rideCount)"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    Text("Last ride")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if summary.didCompleteRide {
                        SessionMetricRow(
                            label: "Duration",
                            value: SessionFormatters.segmentDuration(summary.lastRideDuration)
                        )
                        SessionMetricRow(
                            label: "Distance",
                            value: SessionFormatters.distance(summary.lastRideMeters)
                        )
                        SessionMetricRow(
                            label: "Laps",
                            value: "\(summary.lastRideLapCount)"
                        )
                    } else {
                        Text("No rides yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
            .navigationDestination(for: StartMapCoordinate.self) { coordinate in
                SessionStartMapFullscreenView(
                    coordinate: coordinate.coordinate,
                    distanceMeters: Self.startMapDistanceMeters
                )
            }
        }
        .containerBackground(Color.rpplIdleBackground.gradient, for: .tabView)
        .preferredColorScheme(.dark)
        .onAppear {
            transfer.refreshPendingCount()
        }
    }

    @ViewBuilder
    private var startMapStrip: some View {
        if let latitude = summary.startLatitude, let longitude = summary.startLongitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            ZStack {
                Map(initialPosition: .camera(MapCamera(
                    centerCoordinate: coordinate,
                    distance: Self.startMapDistanceMeters,
                    heading: 0,
                    pitch: 0
                )), interactionModes: []) {
                    Marker("Start", coordinate: coordinate)
                }
                .mapStyle(.standard)
                .allowsHitTesting(false)

                NavigationLink(value: StartMapCoordinate(latitude: latitude, longitude: longitude)) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: Self.mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(String(localized: "Session start location"))
            .accessibilityHint(String(localized: "Shows full-screen map"))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(height: Self.mapHeight)
                .overlay {
                    Label("No GPS", systemImage: "location.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: "No GPS start location"))
        }
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

/// Hashable wrapper so NavigationLink can push the start-map coordinate.
private struct StartMapCoordinate: Hashable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Full-screen interactive start map (pan / zoom); system Back dismisses.
private struct SessionStartMapFullscreenView: View {
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance

    var body: some View {
        Map(initialPosition: .camera(MapCamera(
            centerCoordinate: coordinate,
            distance: distanceMeters,
            heading: 0,
            pitch: 0
        ))) {
            Marker("Start", coordinate: coordinate)
        }
        .mapStyle(.standard)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(Color.rpplIdleBackground.gradient, for: .navigation)
        .accessibilityLabel(String(localized: "Session start location map"))
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
