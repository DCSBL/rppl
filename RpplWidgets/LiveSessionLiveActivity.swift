import ActivityKit
import AppIntents
import RpplCore
import SwiftUI
import WidgetKit

/// Lock screen and Dynamic Island for a session tracked on iPhone: system timers, a big green
/// "Next set" and a small red "Stop" that opens the app on its confirmation.
struct LiveSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSessionActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color("RpplBackdropBottom"))
                .opacity(context.isStale ? 0.6 : 1)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.setCount)", systemImage: "flag.checkered")
                        .foregroundStyle(Color("RpplMetricSets"))
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StopwatchText(since: context.state.setStartedAt ?? context.attributes.startedAt)
                        .font(.title2.bold().monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.parkName ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let watch = context.state.watch {
                        WatchNumbersView(state: context.state, watch: watch)
                    } else {
                        Buttons(state: context.state)
                    }
                }
            } compactLeading: {
                Label("\(context.state.setCount)", systemImage: "flag.checkered")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color("RpplMetricSets"))
            } compactTrailing: {
                StopwatchText(since: context.state.setStartedAt ?? context.attributes.startedAt)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "flag.checkered").foregroundStyle(Color("RpplMetricSets"))
            }
            .widgetURL(URL(string: "rppl://live"))
        }
    }
}

private struct LockScreenView: View {
    let attributes: LiveSessionActivityAttributes
    let state: LiveSessionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(attributes.parkName ?? String(localized: state.watch == nil ? "Session" : "Apple Watch")).font(.subheadline.bold())
                Spacer()
                StopwatchText(since: attributes.startedAt)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
            if let watch = state.watch {
                WatchNumbersView(state: state, watch: watch)
            } else if !state.timeOnly {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(state.setCount == 0 ? "No set yet" : "Set \(state.setCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let started = state.setStartedAt {
                            StopwatchText(since: started)
                                .font(.largeTitle.bold().monospacedDigit())
                                .frame(maxWidth: 160, alignment: .leading)
                        }
                    }
                    Spacer()
                }
            }
            if state.watch == nil { Buttons(state: state) }
        }
    }
}

/// Sets, speed, heart rate, water and laps of a session the Watch records. Nothing to press here.
private struct WatchNumbersView: View {
    let state: LiveSessionActivityAttributes.ContentState
    let watch: LiveSessionActivityAttributes.ContentState.WatchNumbers

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            number("\(state.setCount)", label: "Sets")
            number(watch.speedKmh.map { "\(Int($0.rounded()))" } ?? "-", label: "km/h")
            number(watch.heartRate.map { "\(Int($0.rounded()))" } ?? "-", label: "bpm")
            number(watch.waterCelsius.map { "\(Int($0.rounded()))°" } ?? "-", label: "Water")
            number("\(watch.lapCount)", label: "Laps")
        }
    }

    private func number(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct Buttons: View {
    let state: LiveSessionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if !state.timeOnly {
                Button(intent: NextSetIntent()) {
                    Text(state.setCount == 0 ? "First set" : "Next set")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
            }
            Link(destination: URL(string: "rppl://live") ?? URL(fileURLWithPath: "/")) {
                Text("Stop")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.18), in: Capsule())
            }
        }
    }
}

/// A count-up the system keeps running (`timerInterval`), so the app never updates it.
private struct StopwatchText: View {
    let since: Date

    var body: some View {
        Text(timerInterval: since...since.addingTimeInterval(24 * 3_600), countsDown: false)
    }
}
