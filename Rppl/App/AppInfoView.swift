import SwiftUI
import RpplCore

struct AppInfoView: View {
    var isImporting: Bool
    var onImportSessionTapped: () -> Void

    @State private var permissions = PhonePermissionsController.shared
    @State private var iCloud = PhoneICloudDriveController.shared
    @Environment(\.openURL) private var openURL
    @State private var showDisableDeleteConfirm = false
    @State private var showDebug = false
    @AppStorage(AppSettingsKey.parkWaterTemperatureEnabled) private var waterTemperatureEnabled = false

    private let versionInfo = AppVersionInfo(infoDictionary: Bundle.main.infoDictionary)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Rppl logs cable-park wakeboarding sessions. Apple Watch records a full park day (sets, laps, speed, route); on iPhone you can also add a session by hand."
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.rpplMuted)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("About")
                }

                PhonePermissionsListSection(permissions: permissions)

                Section {
                    Toggle("Water temperature", isOn: $waterTemperatureEnabled)
                        .tint(Color.rpplAccent)
                } header: {
                    Text("Park water temperature")
                } footer: {
                    Text(
                        "Uses an external, official water-monitoring service on parks with a nearby source, for the park screen. The reading is an estimate."
                    )
                }

                if AppReleaseChannel.allowsDebugTools {
                    Section {
                        Button(action: onImportSessionTapped) {
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
                            "Import from iCloud Drive or a session export of raw data. Imported sessions appear in the logbook."
                        )
                    }
                }

                Section {
                    iCloudDriveRow

                    if let folderURL = iCloud.filesAppFolderURL {
                        Button {
                            openURL(folderURL)
                        } label: {
                            Label("Show folder", systemImage: "folder")
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
                        "Keeps your phone logbook in your iCloud Drive as backup, which can be restored."
                    )
                }

                Section {
                    betaRow
                }

                Section {
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
                        HiddenDebugLogo { showDebug = true }

                        VStack(spacing: 2) {
                            Text(versionInfo.headline)
                                .textSelection(.enabled)
                                .accessibilityLabel("Version \(versionInfo.headline)")
                            Link(destination: versionInfo.sourceURL) {
                                HStack(spacing: 4) {
                                    Text(versionInfo.detail)
                                    Image(systemName: "arrow.up.right")
                                        .imageScale(.small)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.rpplMuted.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .scrollContentBackground(.hidden)
            .background(RpplBackdrop())
            .navigationTitle("Rppl")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.rpplBackdropTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Color.rpplAccent)
            .navigationDestination(isPresented: $showDebug) { DebugLogView() }
            .alert(
                "Turn off iCloud Drive?",
                isPresented: $showDisableDeleteConfirm
            ) {
                Button("Delete iCloud copies", role: .destructive) {
                    beginDisableSync(deleteCopies: true)
                }
                Button("Keep iCloud copies") {
                    beginDisableSync(deleteCopies: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Stop syncing the logbook to iCloud Drive? You can delete the Drive copies now, or leave them in Files."
                )
            }
        }
    }

    /// Testers already in the beta get a share sheet to invite a friend; everyone else opens the join page.
    @ViewBuilder
    private var betaRow: some View {
        if AppReleaseChannel.isTestFlight {
            ShareLink(item: AppConstants.betaJoinURL) {
                Label("Invite someone else to the beta", systemImage: "person.badge.plus")
            }
        } else {
            Link(destination: AppConstants.betaJoinURL) {
                Label("Join the beta", systemImage: "paperplane")
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
}

#Preview {
    AppInfoView(
        isImporting: false,
        onImportSessionTapped: {}
    )
}
