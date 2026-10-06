import SwiftUI
import WatchKit
import RpplCore

/// Permission checklist: shown when Start needs access that is missing or still undecided, and
/// from the Permissions page. Continue asks for what is undecided through the system sheets
/// (then starts the pending session, if any); blocked items stay on the list with a cross, why
/// they are needed and how to enable them. Rows are information only, never buttons.
struct StartPermissionsView: View {
    @Bindable var session: WatchSessionController
    @Environment(\.dismiss) private var dismiss

    /// Same order the system sheets appear in.
    private let kinds: [WatchPermissionKind] = [.health, .location, .motion]

    private var isBlocked: Bool {
        WatchPermissionOrder.startBlocker(states: session.permissionStates) != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(kinds, id: \.self) { kind in
                        row(for: kind)
                    }
                } header: {
                    Text("Needed for your session")
                }
            }
            .navigationTitle(String(localized: "Permissions"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await session.continueFromPermissionChecklist() }
                    } label: {
                        if session.isPromptingPermissions {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(actionTitle).frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(session.isPromptingPermissions || isBlocked)
                }
            }
        }
        // Silent status read each time the list shows; never presents a system sheet.
        .onAppear { session.refreshPermissionStatus() }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.didBecomeActiveNotification)) { _ in
            session.refreshPermissionStatus()
        }
    }

    private var actionTitle: String {
        if session.pendingStartActivityCode == nil, !session.needsPermissionSetup {
            return String(localized: "Done")
        }
        return String(localized: "Continue")
    }

    private func row(for kind: WatchPermissionKind) -> some View {
        let state = session.permissionStates[kind] ?? .notDetermined
        return VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(kind.title)
            } icon: {
                icon(for: state)
            }
            switch state {
            case .authorized, .unavailable:
                EmptyView()
            case .notDetermined:
                Text(kind.whyNeeded)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Asked when you continue")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .denied:
                Text(kind.whyNeeded)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(kind.howToFix)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Plain glyphs, no circles: a ringed icon reads as a button.
    @ViewBuilder
    private func icon(for state: WatchPermissionState) -> some View {
        switch state {
        case .authorized, .unavailable:
            Image(systemName: "checkmark").foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark").foregroundStyle(.red)
        case .notDetermined:
            Image(systemName: "ellipsis").foregroundStyle(.secondary)
        }
    }
}
