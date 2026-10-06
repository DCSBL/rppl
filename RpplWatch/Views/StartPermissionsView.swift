import SwiftUI
import RpplCore

/// Permission checklist shown when Start needs access that is missing or still undecided.
/// Continue asks for what is undecided through the system sheets, then starts the session;
/// anything blocked stays on the list with a cross, why it is needed and how to enable it.
struct StartPermissionsView: View {
    @Bindable var session: WatchSessionController
    @Environment(\.dismiss) private var dismiss

    /// Same order the system sheets appear in.
    private let kinds: [WatchPermissionKind] = [.health, .location, .motion]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(kinds, id: \.self) { kind in
                        row(for: kind)
                    }
                } header: {
                    Text("Rppl needs")
                }
                Section {
                    Button {
                        Task { await session.continueFromPermissionChecklist() }
                    } label: {
                        if session.isPromptingPermissions {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Continue").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(session.isPromptingPermissions)
                }
            }
            .navigationTitle(String(localized: "Permissions"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
    }

    private func row(for kind: WatchPermissionKind) -> some View {
        let state = session.permissionStates[kind] ?? .notDetermined
        let isBlocked = !session.isPromptingPermissions && state == .denied
        return VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(kind.title)
            } icon: {
                icon(for: state)
            }
            if state != .authorized && state != .unavailable {
                Text(kind.whyNeeded)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if isBlocked {
                Text(kind.howToFix)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func icon(for state: WatchPermissionState) -> some View {
        switch state {
        case .authorized, .unavailable:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .notDetermined:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}
