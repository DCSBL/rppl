import SwiftUI
import RpplCore

struct AppInfoView: View {
    var isImporting: Bool
    var onImportSessionTapped: () -> Void

    @State private var permissions = PhonePermissionsController.shared
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var showDisableDeleteConfirm = false
    @AppStorage(AppSettingsKey.parkWaterTemperatureEnabled) private var waterTemperatureEnabled = false

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

                #if PARK_ARRIVAL_NOTIFICATIONS
                ParkArrivalNotificationsSection()
                #endif

                Section {
                    Toggle("Water temperature", isOn: $waterTemperatureEnabled)
                        .tint(Color.rpplAccent)
                    if AppReleaseChannel.allowsDebugTools {
                        NavigationLink {
                            ParkWaterTemperatureDebugView()
                        } label: {
                            Label("Debug water temperature", systemImage: "ladybug")
                        }
                    }
                } header: {
                    Text("Park water temperature")
                } footer: {
                    #if PARK_ARRIVAL_NOTIFICATIONS
                    Text(
                        "Uses an external, official water-monitoring service on parks with a nearby source, for the park screen and the arrival notification. The reading is an estimate."
                    )
                    #else
                    Text(
                        "Uses an external, official water-monitoring service on parks with a nearby source, for the park screen. The reading is an estimate."
                    )
                    #endif
                }

                if AppReleaseChannel.allowsDebugTools {
                    Section {
                        NavigationLink {
                            DebugLogView()
                        } label: {
                            Label("Debug log", systemImage: "list.bullet.rectangle")
                        }
                    } header: {
                        Text("Debug")
                    } footer: {
                        Text("Recent warnings and failures logged across the app (sync, transfer, water temperature, …).")
                    }

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
            .background(RpplBackdrop())
            .navigationTitle("Rppl")
            .toolbarBackground(Color.rpplBackdropTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Color.rpplAccent)
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
