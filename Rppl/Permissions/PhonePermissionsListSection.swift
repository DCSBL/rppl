import SwiftUI
import RpplCore

/// Always-visible companion permission rows (About). Fixed Location → Health → Motion order.
struct PhonePermissionsListSection: View {
    @Bindable var permissions: PhonePermissionsController

    var body: some View {
        Section {
            ForEach(WatchPermissionKind.allCases, id: \.self) { kind in
                NavigationLink {
                    PhonePermissionDetailView(kind: kind, permissions: permissions)
                } label: {
                    PhonePermissionRowView(
                        kind: kind,
                        state: permissions.permissionStates[kind] ?? .notDetermined
                    )
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text(
                "These permissions are requested after your first Watch sync, not when you open the app. Syncing sessions and showing city names work without them. City names come from GPS recorded on the Watch, not from the iPhone’s live location."
            )
        }
        .onAppear { permissions.refresh() }
    }
}

private struct PhonePermissionRowView: View {
    let kind: WatchPermissionKind
    let state: WatchPermissionState

    var body: some View {
        HStack {
            Label {
                Text(kind.phoneTitle)
            } icon: {
                Image(systemName: kind.phoneSystemImage)
            }
            Spacer(minLength: 8)
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.phoneTitle), \(state.phoneAccessibilityLabel)")
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

    private func request() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        await permissions.request(kind)
    }
}

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
                localized: "Optional. Lets the iPhone show map context for your sessions. City and spot names already come from Watch GPS stored with each session, so sync still works if you turn this off."
            )
        case .health:
            return String(
                localized: "Optional. Lets the iPhone read Health data for companion views. Workouts are recorded on Apple Watch, and turning this off does not block syncing sessions."
            )
        case .motion:
            return String(
                localized: "Optional. Lets the iPhone use motion data when reviewing a session. It is not required to sync sessions from the Watch."
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
                localized: "On iPhone, open Settings > Health > Data Access & Devices > Rppl, then turn on the categories you want to allow."
            )
        case .motion:
            return String(
                localized: "On iPhone, open Settings > Privacy & Security > Motion & Fitness, then enable Rppl."
            )
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
