import SwiftUI
import RpplCore

/// Shown when Start is refused because a required permission is missing (Health first).
/// The rest of the Watch app stays usable; this only explains what to allow and how.
struct StartBlockedView: View {
    let kind: WatchPermissionKind
    @Bindable var session: WatchSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(String(localized: "Can't start yet"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Rppl needs access to \(kind.title) to record a session.")
                    Text(kind.whyNeeded)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text(kind.howToFix)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await tryAgain() }
                    } label: {
                        Text("Try again")
                    }
                    .disabled(session.isPromptingPermissions)
                } header: {
                    Text("How to fix")
                }
                Section {
                    Button("Close") { dismiss() }
                }
            }
            .navigationTitle(kind.title)
        }
        .onChange(of: session.permissionStates) { _, _ in
            if WatchPermissionOrder.startBlocker(states: session.permissionStates) == nil {
                session.startBlockedBy = nil
            }
        }
    }

    private func tryAgain() async {
        switch kind {
        case .health:
            await session.requestHealthPermission(force: true)
        case .location:
            await session.requestLocationPermission()
        case .motion:
            await session.requestMotionPermission()
        }
        session.refreshPermissionStatus()
        if WatchPermissionOrder.startBlocker(states: session.permissionStates) == nil {
            session.startBlockedBy = nil
        }
    }
}
