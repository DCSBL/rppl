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
                            Text(controller.park?.compactName ?? "")
                                .font(.caption)
                                .foregroundStyle(Color.rpplMuted)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading) {
                                Text("Session").font(.caption).foregroundStyle(Color.rpplMuted)
                                LiveTimer(since: live.startedAt)
                            }
                            Spacer()
                            if let start = live.currentSetStart {
                                VStack(alignment: .trailing) {
                                    Text("Set \(live.setCount)").font(.caption).foregroundStyle(Color.rpplMuted)
                                    LiveTimer(since: start)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                if live.mode == .setsAndTime {
                    Button { controller.nextSet() } label: {
                        Text(live.setCount == 0 ? "First set" : "Next set").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                }
            }
            .rpplTileChrome()
            .accessibilityElement(children: .contain)
        }
    }
}
