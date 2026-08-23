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
                "Asked after the first Watch sync — not at launch. Sync and city names work without these; city uses session GPS from the Watch, not live iPhone location."
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
            }

            Section("Why needed") {
                Text(kind.phoneWhyNeeded)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if state == .denied {
                Section("How to fix") {
                    Text(kind.phoneHowToFix)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            Text("Not available — skipped").foregroundStyle(.secondary)
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
                localized: "Placeholder: Optional for map context. City/spot names use Watch session GPS already on disk — not a live iPhone location fix."
            )
        case .health:
            return String(
                localized: "Placeholder: Optional Health read for companion views. Workouts are recorded on Apple Watch; denying Health here does not block sync."
            )
        case .motion:
            return String(
                localized: "Placeholder: Optional Motion access for future review tools. Not required to sync sessions from Watch."
            )
        }
    }

    var phoneHowToFix: String {
        switch self {
        case .location:
            return String(
                localized: "Placeholder: Settings › Privacy & Security › Location Services › Rppl › While Using."
            )
        case .health:
            return String(
                localized: "Placeholder: Settings › Health › Data Access & Devices › Rppl."
            )
        case .motion:
            return String(
                localized: "Placeholder: Settings › Privacy & Security › Motion & Fitness › Rppl."
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
