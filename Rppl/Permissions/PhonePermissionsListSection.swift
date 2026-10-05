import SwiftUI
import UIKit
import RpplCore

/// Always-visible companion permission rows (About). Fixed Location → Health → Motion →
/// Notifications order. Notifications isn't a `WatchPermissionKind` (that enum backs the Watch
/// recording gate, where a notifications row wouldn't belong), so it's appended separately here.
/// The Notifications row only exists with `PARK_ARRIVAL_NOTIFICATIONS`: park arrival is the only
/// notification Rppl sends.
struct PhonePermissionsListSection: View {
    @Bindable var permissions: PhonePermissionsController

    var body: some View {
        Section {
            ForEach(WatchPermissionKind.allCases, id: \.self) { kind in
                NavigationLink {
                    PhonePermissionDetailView(kind: kind, permissions: permissions)
                } label: {
                    PhonePermissionRowView(
                        title: kind.phoneTitle,
                        systemImage: kind.phoneSystemImage,
                        state: permissions.permissionStates[kind] ?? .notDetermined
                    )
                }
            }
            #if PARK_ARRIVAL_NOTIFICATIONS
            NavigationLink {
                PhoneNotificationPermissionDetailView(permissions: permissions)
            } label: {
                PhonePermissionRowView(
                    title: String(localized: "Notifications"),
                    systemImage: "bell.fill",
                    state: permissions.notificationPermission
                )
            }
            #endif
        } header: {
            Text("Permissions")
        } footer: {
            Text("Rppl asks only when a feature needs it.")
        }
        .onAppear { permissions.refresh() }
    }
}

private struct PhonePermissionRowView: View {
    let title: String
    let systemImage: String
    let state: WatchPermissionState

    var body: some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            Spacer(minLength: 8)
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(state.phoneAccessibilityLabel)")
    }

    private var statusSymbol: String {
        switch state {
        case .authorized: return "checkmark.circle.fill"
        case .unavailable: return "checkmark.circle"
        case .notDetermined: return "questionmark.circle"
        case .denied: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch state {
        case .authorized: return .green
        case .unavailable: return .secondary
        case .notDetermined: return .orange
        case .denied: return .red
        }
    }
}

struct PhonePermissionDetailView: View {
    let kind: WatchPermissionKind
    @Bindable var permissions: PhonePermissionsController
    @Environment(\.openURL) private var openURL
    @State private var isRequesting = false

    private var state: WatchPermissionState {
        permissions.permissionStates[kind] ?? .notDetermined
    }

    var body: some View {
        List {
            Section {
                Label(kind.phoneTitle, systemImage: kind.phoneSystemImage)
                statusLine
                Text(kind.phoneWhyNeeded)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if state == .denied {
                Section {
                    Text(kind.phoneHowToFix)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await request(force: true) }
                    } label: {
                        Text("Try again")
                    }
                    .disabled(isRequesting)
                    Button {
                        openFixURL()
                    } label: {
                        Text(kind.phoneOpenSettingsTitle)
                    }
                } header: {
                    Text("How to fix")
                }
            }

            if state == .notDetermined {
                Section {
                    Button {
                        Task { await request(force: false) }
                    } label: {
                        if isRequesting {
                            ProgressView()
                        } else {
                            Text("Allow \(kind.phoneTitle)")
                        }
                    }
                    .disabled(isRequesting)
                }
            }
        }
        .navigationTitle(kind.phoneTitle)
        .tint(Color.rpplAccent)
    }

    private var statusLine: some View {
        switch state {
        case .authorized:
            Text("Allowed").foregroundStyle(.green)
        case .unavailable:
            Text("Not available on this device").foregroundStyle(.secondary)
        case .notDetermined:
            Text("Not decided yet").foregroundStyle(.orange)
        case .denied:
            Text("Denied").foregroundStyle(.red)
        }
    }

    private func request(force: Bool) async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        await permissions.request(kind, force: force)
    }

    private func openFixURL() {
        if let url = kind.phoneSettingsURL {
            openURL(url)
        }
    }
}

#if PARK_ARRIVAL_NOTIFICATIONS
/// Same shape as `PhonePermissionDetailView`, standalone because notifications aren't a
/// `WatchPermissionKind`. Used for the Settings permissions list row, and by the park-arrival
/// feature (its own denial message points back here).
struct PhoneNotificationPermissionDetailView: View {
    @Bindable var permissions: PhonePermissionsController
    @Environment(\.openURL) private var openURL
    @State private var isRequesting = false

    private var state: WatchPermissionState { permissions.notificationPermission }

    var body: some View {
        List {
            Section {
                Label("Notifications", systemImage: "bell.fill")
                statusLine
                Text("Notification permission is needed for the park arrival notifications feature.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ParkArrivalNotificationsSection()

            if state == .denied {
                Section {
                    Text("On iPhone, open Settings > Notifications > Rppl, then turn on Allow Notifications.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Text("Open Settings")
                    }
                } header: {
                    Text("How to fix")
                }
            }

            if state == .notDetermined {
                Section {
                    Button {
                        Task { await request() }
                    } label: {
                        if isRequesting {
                            ProgressView()
                        } else {
                            Text("Allow Notifications")
                        }
                    }
                    .disabled(isRequesting)
                }
            }
        }
        .navigationTitle("Notifications")
        .tint(Color.rpplAccent)
    }

    private var statusLine: some View {
        switch state {
        case .authorized:
            Text("Allowed").foregroundStyle(.green)
        case .unavailable:
            Text("Not available on this device").foregroundStyle(.secondary)
        case .notDetermined:
            Text("Not decided yet").foregroundStyle(.orange)
        case .denied:
            Text("Denied").foregroundStyle(.red)
        }
    }

    private func request() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        await permissions.requestNotifications()
    }
}
#endif

extension WatchPermissionKind {
    var phoneTitle: String {
        switch self {
        case .location: return String(localized: "Location")
        case .health: return String(localized: "Health")
        case .motion: return String(localized: "Motion")
        }
    }

    var phoneSystemImage: String {
        switch self {
        case .location: return "location.fill"
        case .health: return "heart.fill"
        case .motion: return "figure.walk.motion"
        }
    }

    var phoneWhyNeeded: String {
        switch self {
        case .location:
            return String(
                localized: "Shows maps for your sessions. City and spot names already come from Watch GPS saved with each session."
            )
        case .health:
            return String(
                localized: "Lets iPhone read Health for session details. Workouts are recorded on Apple Watch."
            )
        case .motion:
            return String(
                localized: "Lets iPhone use motion when you review a session."
            )
        }
    }

    var phoneHowToFix: String {
        switch self {
        case .location:
            return String(
                localized: "On iPhone, open Settings > Privacy & Security > Location Services > Rppl, then choose While Using the App."
            )
        case .health:
            return String(
                localized: "On iPhone, open Settings > Health > Data Access & Devices > Rppl, then turn on the categories you want to allow. You can also open Health from the button below."
            )
        case .motion:
            return String(
                localized: "On iPhone, open Settings > Privacy & Security > Motion & Fitness, then enable Rppl."
            )
        }
    }

    var phoneOpenSettingsTitle: String {
        switch self {
        case .health:
            return String(localized: "Open Health")
        case .location, .motion:
            return String(localized: "Open Settings")
        }
    }

    /// Deep link for the denied-state fix button. Health prefers the Health app; others use app Settings.
    var phoneSettingsURL: URL? {
        switch self {
        case .health:
            return URL(string: "x-apple-health://")
                ?? URL(string: UIApplication.openSettingsURLString)
        case .location, .motion:
            return URL(string: UIApplication.openSettingsURLString)
        }
    }
}

extension WatchPermissionState {
    var phoneAccessibilityLabel: String {
        switch self {
        case .authorized: return String(localized: "allowed")
        case .unavailable: return String(localized: "unavailable, skipped")
        case .notDetermined: return String(localized: "not decided")
        case .denied: return String(localized: "denied")
        }
    }
}
