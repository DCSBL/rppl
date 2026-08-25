import SwiftUI
import WatchKit
import RpplCore

struct PermissionsOnboardingView: View {
    @Bindable var session: WatchSessionController
    @State private var rowOrder: [WatchPermissionKind] = []
    @State private var frozenStates: [WatchPermissionKind: WatchPermissionState] = [:]
    @State private var didStartAutoPrompt = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rowOrder, id: \.self) { kind in
                        NavigationLink {
                            PermissionDetailView(kind: kind, session: session)
                        } label: {
                            PermissionRowView(
                                kind: kind,
                                state: session.permissionStates[kind] ?? .notDetermined
                            )
                        }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle("Rppl")
        }
        .onAppear {
            session.refreshPermissionStatus()
            bootstrapOrderIfNeeded()
            startAutoPromptIfNeeded()
        }
        .onChange(of: session.locationPermission) { _, _ in
            handleStateChange()
        }
        .onChange(of: session.healthPermission) { _, _ in
            handleStateChange()
        }
        .onChange(of: session.motionPermission) { _, _ in
            handleStateChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.didBecomeActiveNotification)) { _ in
            session.refreshPermissionStatus()
            handleStateChange()
        }
    }

    private var footerText: String {
        if session.isPromptingPermissions {
            return String(
                localized: "Waiting for system permission popups. This can take a few seconds on first launch."
            )
        }
        return String(
            localized: "Allow each permission so Rppl can record your park session on Apple Watch."
        )
    }

    private func bootstrapOrderIfNeeded() {
        let states = session.permissionStates
        if rowOrder.isEmpty {
            rowOrder = WatchPermissionOrder.initialOrder(states: states)
            frozenStates = states
            return
        }
        handleStateChange()
    }

    private func handleStateChange() {
        let next = session.permissionStates
        guard !rowOrder.isEmpty else {
            rowOrder = WatchPermissionOrder.initialOrder(states: next)
            frozenStates = next
            return
        }
        rowOrder = WatchPermissionOrder.orderPreserving(
            current: rowOrder,
            previous: frozenStates,
            next: next
        )
        frozenStates = next
    }

    /// First boot: fire system sheets from the list — no row tap required.
    private func startAutoPromptIfNeeded() {
        guard !didStartAutoPrompt else { return }
        didStartAutoPrompt = true
        Task {
            await session.promptUndeterminedPermissionsInOrder()
        }
    }
}

private struct PermissionRowView: View {
    let kind: WatchPermissionKind
    let state: WatchPermissionState

    var body: some View {
        HStack {
            Label {
                Text(kind.title)
            } icon: {
                Image(systemName: kind.systemImage)
            }
            Spacer(minLength: 8)
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title), \(state.accessibilityLabel)")
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

struct PermissionDetailView: View {
    let kind: WatchPermissionKind
    @Bindable var session: WatchSessionController

    private var state: WatchPermissionState {
        session.permissionStates[kind] ?? .notDetermined
    }

    var body: some View {
        List {
            Section {
                Label(kind.title, systemImage: kind.systemImage)
                statusLine
                Text(kind.whyNeeded)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if state == .denied {
                Section {
                    Text(kind.howToFix)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await request(force: true) }
                    } label: {
                        Text("Try Again")
                    }
                    .disabled(session.isPromptingPermissions)
                } header: {
                    Text("How to fix")
                }
            }

            if state == .notDetermined {
                Section {
                    Button {
                        Task { await request(force: false) }
                    } label: {
                        Text("Allow \(kind.title)")
                    }
                    .disabled(session.isPromptingPermissions)
                    if session.isPromptingPermissions {
                        Text("Waiting for the system popup…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(kind.title)
    }

    private var statusLine: some View {
        switch state {
        case .authorized:
            Text("Allowed")
                .foregroundStyle(.green)
        case .unavailable:
            Text("Not available on this Watch")
                .foregroundStyle(.secondary)
        case .notDetermined:
            Text("Not decided yet")
                .foregroundStyle(.orange)
        case .denied:
            Text("Denied")
                .foregroundStyle(.red)
        }
    }

    private func request(force: Bool) async {
        switch kind {
        case .location:
            await session.requestLocationPermission()
        case .health:
            await session.requestHealthPermission(force: force)
        case .motion:
            await session.requestMotionPermission()
        }
    }
}

extension WatchPermissionKind {
    var title: String {
        switch self {
        case .location: return String(localized: "Location")
        case .health: return String(localized: "Health")
        case .motion: return String(localized: "Motion")
        }
    }

    var systemImage: String {
        switch self {
        case .location: return "location.fill"
        case .health: return "heart.fill"
        case .motion: return "figure.walk.motion"
        }
    }

    var whyNeeded: String {
        switch self {
        case .location:
            return String(localized: "Required to record GPS during your park session so Rppl can track rides and distance.")
        case .health:
            return String(localized: "Required to save the workout to Fitness and record heart rate while you ride.")
        case .motion:
            return String(localized: "Helps tell when you are riding versus resting at the dock.")
        }
    }

    var howToFix: String {
        switch self {
        case .location:
            return String(
                localized: "On iPhone, open Settings > Privacy & Security > Location Services > Rppl and allow While Using the App."
            )
        case .health:
            return String(
                localized: "On iPhone, open the Health app > Sharing > Apps > Rppl and turn on workout access. Or: Settings > Health > Data Access & Devices > Rppl."
            )
        case .motion:
            return String(
                localized: "On iPhone, open Settings > Privacy & Security > Motion & Fitness and enable Rppl."
            )
        }
    }
}

extension WatchPermissionState {
    var accessibilityLabel: String {
        switch self {
        case .authorized: return String(localized: "allowed")
        case .unavailable: return String(localized: "unavailable, skipped")
        case .notDetermined: return String(localized: "not decided")
        case .denied: return String(localized: "denied")
        }
    }
}
