import SwiftUI
import RpplCore

/// The park-arrival toggle, debug link, and explanation. Shown in the main Settings screen and,
/// mirrored, on the Notifications permission detail screen — turning the feature on needs
/// notification access, so riders can enable it from either place.
struct ParkArrivalNotificationsSection: View {
    @State private var parkArrival = ParkArrivalController.shared
    @State private var isTogglingParkArrival = false

    var body: some View {
        Section {
            row

            if AppReleaseChannel.allowsDebugTools {
                NavigationLink {
                    ParkArrivalDebugView()
                } label: {
                    Label("Debug park arrival", systemImage: "ladybug")
                }
            }
        } header: {
            Text("Park arrival notifications")
        } footer: {
            Text(
                "When on, Rppl watches for you crossing into your favorite and nearby parks on your device and sends one local \"Welcome to…\" notification per visit. Uses When In Use location, so this only fires while Rppl is still running in the background; if you haven't opened it in a while, or force-quit it, reopen Rppl once to pick monitoring back up."
            )
        }
    }

    @ViewBuilder
    private var row: some View {
        if isTogglingParkArrival {
            HStack {
                Text("Notify on arrival")
                Spacer()
                ProgressView()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Notify on arrival")
            .accessibilityValue("Updating")
        } else {
            Toggle(
                "Notify on arrival",
                isOn: Binding(
                    get: { parkArrival.isEnabled },
                    set: { newValue in
                        isTogglingParkArrival = true
                        Task {
                            if newValue {
                                await parkArrival.enable()
                            } else {
                                parkArrival.disable()
                            }
                            isTogglingParkArrival = false
                        }
                    }
                )
            )
            .tint(Color.rpplAccent)
            if parkArrival.permissionDenied {
                Text(
                    "Location or notification access was denied, so this stayed off. Allow both location and notifications in Settings, then try again."
                )
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
            }
        }
    }
}
