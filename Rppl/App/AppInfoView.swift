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
                        "Rppl records cable-park wakeboarding on Apple Watch. It tracks rides and pauses across a full park day in one session. Use iPhone to view sessions, maps, and exports."
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
                    HStack {
                        Toggle(
                            "iCloud Drive",
                            isOn: Binding(
                                get: { iCloud.isSyncEnabled },
                                set: { newValue in
                                if newValue {
                                    Task {
                                        await iCloud.setSyncEnabled(true, deleteICloudCopies: false)
                                    }
                                } else {
                                        showDisableDeleteConfirm = true
                                    }
                                }
                            )
                        )
                        .disabled(
                            iCloud.isApplyingSyncChange
                                || (!iCloud.isICloudAvailable && !iCloud.isSyncEnabled)
                        )
                        .tint(Color.rpplAccent)

                        if iCloud.isApplyingSyncChange {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let status = iCloud.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text(
                        "Keeps your phone logbook in your iCloud Drive so sessions can survive deleting the app. Uses your Apple account — not a Rppl cloud. Default on."
                    )
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("On your devices")
                            .font(.body.weight(.semibold))
                        Text(
                            "Rppl processes your session on your Watch and iPhone. We do not upload rides to a Rppl cloud or share your data with others."
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
            .confirmationDialog(
                "Turn Off iCloud Drive?",
                isPresented: $showDisableDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete iCloud Copies", role: .destructive) {
                    Task {
                        await iCloud.setSyncEnabled(false, deleteICloudCopies: true)
                    }
                }
                Button("Keep iCloud Copies") {
                    Task {
                        await iCloud.setSyncEnabled(false, deleteICloudCopies: false)
                    }
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

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            presentImportFailure(error.localizedDescription)
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
                    presentImportFailure(Self.userFacingMessage(for: error))
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

    private static func userFacingMessage(for error: Error) -> String {
        if let decoding = error as? DecodingError {
            return SessionExportImportError.message(for: decoding)
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            return String(localized: "Something went wrong while importing the session.")
        }
        return description
    }
}

#Preview {
    AppInfoView(
        navigation: .constant(LogbookNavigationRequest()),
        selectedTab: .constant(.app)
    )
}
