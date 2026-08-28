import SwiftUI
import UniformTypeIdentifiers
import RpplCore

struct AppInfoView: View {
    @Binding var navigation: LogbookNavigationRequest
    @Binding var selectedTab: AppTab

    @State private var permissions = PhonePermissionsController.shared
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var showDisableDeleteConfirm = false
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var showImportError = false
    @State private var importErrorText: String?
    @State private var showAlreadyImportedAlert = false
    @State private var pendingDuplicateSessionId: String?

    private var versionFooter: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        let date = Bundle.main.infoDictionary?["RpplBuildDate"] as? String ?? "-"
        return "\(version) (\(build) - \(date))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Rppl records cable-park wakeboarding on Apple Watch. It tracks sets and pauses across a full park day in one session. Use iPhone to view sessions, maps, and exports."
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.rpplMuted)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("About")
                }

                PhonePermissionsListSection(permissions: permissions)

                if AppReleaseChannel.allowsDebugTools {
                    Section {
                        Button {
                            showImporter = true
                        } label: {
                            if isImporting {
                                ProgressView()
                            } else {
                                Label("Import session", systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(isImporting)
                    } header: {
                        Text("Import")
                    } footer: {
                        Text(
                            "Choose a session export JSON from Files. Imported sessions appear in the logbook. Health is not updated."
                        )
                    }
                }

                Section {
                    iCloudDriveRow

                    if let status = iCloud.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text(
                        "Keeps your phone logbook in your iCloud Drive as backup, which can be restored. Uses your Apple account, not a Rppl cloud."
                    )
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("On your devices")
                            .font(.body.weight(.semibold))
                        Text(
                            "Rppl processes your session on your Watch and iPhone. We do not upload sets to a Rppl cloud or share your data with others."
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.rpplMuted)
                        Text(
                            "With iCloud Drive on, the phone logbook lives in your iCloud Documents. Device iCloud Backup is separate and only helps after a full device restore."
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.rpplMuted)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)

                    NavigationLink {
                        LegalTermsPrivacyView()
                    } label: {
                        Text("Terms & Privacy policy")
                    }
                } header: {
                    Text("Legal")
                }

                Section {
                    VStack(spacing: 8) {
                        Image("icon-simple")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .foregroundStyle(Color.rpplMuted.opacity(0.4))
                            .accessibilityHidden(true)

                        Text(versionFooter)
                            .font(.footnote)
                            .foregroundStyle(Color.rpplMuted.opacity(0.7))
                            .accessibilityLabel("Version \(versionFooter)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .scrollContentBackground(.hidden)
            .background(Color.rpplBackground)
            .navigationTitle("Rppl")
            .toolbarBackground(Color.rpplBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Color.rpplAccent)
            .alert(
                "Turn Off iCloud Drive?",
                isPresented: $showDisableDeleteConfirm
            ) {
                Button("Delete iCloud Copies", role: .destructive) {
                    beginDisableSync(deleteCopies: true)
                }
                Button("Keep iCloud Copies") {
                    beginDisableSync(deleteCopies: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Stop syncing the logbook to iCloud Drive? You can delete the Drive copies now, or leave them in Files."
                )
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert(
                "Could not import session",
                isPresented: $showImportError,
                presenting: importErrorText
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .alert(
                "Already in logbook",
                isPresented: $showAlreadyImportedAlert
            ) {
                Button("Cancel", role: .cancel) {
                    pendingDuplicateSessionId = nil
                }
                Button("Show") {
                    if let sessionId = pendingDuplicateSessionId {
                        navigation.openSessionId = sessionId
                        navigation.highlightSessionId = sessionId
                        selectedTab = .logbook
                    }
                    pendingDuplicateSessionId = nil
                }
            } message: {
                Text("This session is already in your logbook.")
            }
        }
    }

    @ViewBuilder
    private var iCloudDriveRow: some View {
        if iCloud.isApplyingSyncChange {
            HStack {
                Text("iCloud Drive")
                Spacer()
                ProgressView()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("iCloud Drive")
            .accessibilityValue("Updating")
        } else {
            Toggle(
                "iCloud Drive",
                isOn: Binding(
                    get: { iCloud.isSyncEnabled },
                    set: { newValue in
                        if newValue {
                            iCloud.markApplyingSyncChangeForUI()
                            Task {
                                await iCloud.setSyncEnabled(true, deleteICloudCopies: false)
                            }
                        } else {
                            showDisableDeleteConfirm = true
                        }
                    }
                )
            )
            .disabled(!iCloud.isICloudAvailable && !iCloud.isSyncEnabled)
            .tint(Color.rpplAccent)
        }
    }

    private func beginDisableSync(deleteCopies: Bool) {
        showDisableDeleteConfirm = false
        iCloud.markApplyingSyncChangeForUI()
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(100))
            await iCloud.setSyncEnabled(false, deleteICloudCopies: deleteCopies)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            presentImportFailure(SessionExportImportError.detail(for: error))
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            Task {
                do {
                    let importedId = try await connectivity.importExportedSession(from: url)
                    isImporting = false
                    navigation.openSessionId = importedId
                    navigation.highlightSessionId = importedId
                    selectedTab = .logbook
                } catch let error as SessionExportImportError {
                    isImporting = false
                    switch error {
                    case .alreadyImported(let sessionId):
                        pendingDuplicateSessionId = sessionId
                        showAlreadyImportedAlert = true
                    case .unreadable(let message):
                        presentImportFailure(message)
                    }
                } catch {
                    isImporting = false
                    presentImportFailure(SessionExportImportError.detail(for: error))
                    WakeLog.error(.transfer, "export-file import: \(error.localizedDescription)")
                }
            }
        }
    }

    private func presentImportFailure(_ message: String) {
        importErrorText = message
        Task { @MainActor in
            showImportError = true
        }
    }
}

#Preview {
    AppInfoView(
        navigation: .constant(LogbookNavigationRequest()),
        selectedTab: .constant(.app)
    )
}
