import RpplCore
import SwiftUI

/// Top of the logbook while a session runs on this iPhone. Tap opens the running screen.
struct LiveSessionBanner: View {
    let controller: LiveSessionController

    var body: some View {
        if let live = controller.session {
            VStack(alignment: .leading, spacing: 10) {
                Button { controller.showsScreen = true } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Live · iPhone", systemImage: "circle.fill")
                                .font(.caption.weight(.bold))
                                .imageScale(.small)
                                .foregroundStyle(.green)
                            Spacer()
                            Text(controller.placeName ?? "")
                                .font(.caption)
                                .foregroundStyle(Color.rpplMuted)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading) {
                                Text("Session").font(.caption).foregroundStyle(Color.rpplMuted)
                                LiveTimer(since: live.startedAt)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Set \(live.setCount)").font(.caption).foregroundStyle(Color.rpplMuted)
                                LiveTimer(since: live.currentSetStart)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Button { controller.nextSet() } label: {
                    Text("Next set").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            }
            .rpplTileChrome()
            .accessibilityElement(children: .contain)
        }
    }
}

/// The same banner for a session the Apple Watch records: numbers only, nothing to press.
struct WatchLiveBanner: View {
    let snapshot: WatchLiveSnapshot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Live · Apple Watch", systemImage: "circle.fill")
                    .font(.caption.weight(.bold))
                    .imageScale(.small)
                    .foregroundStyle(.green)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text("Session").font(.caption).foregroundStyle(Color.rpplMuted)
                        LiveTimer(since: snapshot.startedAt)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Set \(snapshot.setCount)").font(.caption).foregroundStyle(Color.rpplMuted)
                        Text(snapshot.speedKmh.map { DistanceFormat.kilometersPerHour($0) } ?? "-")
                            .font(.title.bold().monospacedDigit())
                            .foregroundStyle(Color.rpplText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .rpplTileChrome()
    }
}
