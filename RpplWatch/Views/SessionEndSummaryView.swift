import SwiftUI
import MapKit
import RpplCore

/// Post-stop session recap: stats, start map, sync line, Done → idle.
struct SessionEndSummaryView: View {
    let summary: EndedSessionSummary
    @Bindable var session: WatchSessionController
    @Bindable var transfer: WatchTransferService

    private static let store = SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)

    @State private var mapTracks: SessionMapTrackData?
    @State private var mapFrame: MapTrackFrame?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchSessionMapPreview(
                    mapTracks: mapTracks,
                    startCoordinate: startCoordinate,
                    mapFrame: mapFrame
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
                    metric: .distance,
                    value: SessionFormatters.distance(summary.distanceMeters)
                )
                SessionMetricRow(
                    label: "Sets",
                    metric: .sets,
                    value: "\(summary.setCount)"
                )

                Divider()
                    .padding(.vertical, 2)

                WatchLastSetSection(
                    duration: summary.lastSetDuration,
                    distanceMeters: summary.lastSetMeters,
                    lapCount: summary.lastSetLapCount,
                    didCompleteSet: summary.didCompleteSet
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
        .task {
            await loadMapTracks()
        }
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        if let mapTracks {
            return CLLocationCoordinate2D(
                latitude: mapTracks.start.latitude,
                longitude: mapTracks.start.longitude
            )
        }
        guard let latitude = summary.startLatitude, let longitude = summary.startLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func loadMapTracks() async {
        let store = Self.store
        if let derived = try? await StoreIO.runOffMain({
            try store.readDerivedView(sessionId: summary.sessionId)
        }) {
            mapFrame = derived.mapFrame
            if let tracks = derived.mapTracks {
                mapTracks = tracks
                return
            }
        }

        guard store.hasRawStreams(sessionId: summary.sessionId) else { return }
        let built = try? await StoreIO.runOffMain { () -> (SessionMapTrackData?, MapTrackFrame?) in
            let locations = try store.readLocationSamples(sessionId: summary.sessionId)
            let detections = try store.readDetections(sessionId: summary.sessionId)
            let manifest = try store.readManifest(sessionId: summary.sessionId)
            let stats = SessionStatsBuilder.build(
                manifest: manifest,
                detections: detections,
                locations: locations,
                health: [],
                water: []
            )
            let coords = locations.map { (latitude: $0.latitude, longitude: $0.longitude) }
            let frame = MapTrackFitter.frame(locations: coords)
            let tracks = SessionMapTrackBuilder.build(locations: locations, sets: stats.sets)
            return (tracks, frame)
        }
        if let built {
            mapTracks = built.0
            mapFrame = built.1
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

#Preview {
    SessionEndSummaryView(
        summary: EndedSessionSummary(
            sessionId: "preview",
            duration: 3725,
            setCount: 4,
            distanceMeters: 2840,
            lastSetDuration: 312,
            lastSetMeters: 720,
            lastSetLapCount: 2,
            didCompleteSet: true,
            startLatitude: 51.9794,
            startLongitude: 4.5740
        ),
        session: WatchSessionController.shared,
        transfer: WatchTransferService.shared
    )
}
