import SwiftUI
import RpplCore

struct AppInfoView: View {
    var isImporting: Bool
    var onImportSessionTapped: () -> Void

    @State private var permissions = PhonePermissionsController.shared
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var parkArrival = ParkArrivalController.shared
    @State private var showDisableDeleteConfirm = false
    @State private var isTogglingParkArrival = false
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

                Section {
                    parkArrivalRow

                    if AppReleaseChannel.allowsDebugTools {
                        NavigationLink {
                            ParkArrivalDebugView()
                        } label: {
                            Label("Debug park arrival", systemImage: "ladybug")
                        }
                    }
                } header: {
                    Text("Park arrival notifications")
                } footer: {
                    Text(
                        "When on, Rppl watches for you crossing into your favorite and nearby parks on your device (no server, no continuous tracking) and sends one local \"Welcome to…\" notification per visit. Uses When In Use location, so this only fires while Rppl is still running in the background; if you haven't opened it in a while, or force-quit it, reopen Rppl once to pick monitoring back up."
                    )
                }

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
                    Text(
                        "Uses an external, official government service (Rijkswaterstaat) on parks that have a nearby source, for the park screen and the arrival notification. The reading is an estimate."
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
                            "Import from iCloud Drive or a session export JSON file. Imported sessions appear in the logbook. Health is not updated."
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

    @ViewBuilder
    private var parkArrivalRow: some View {
        if isTogglingParkArrival {
            HStack {
                Text("Notify on arrival")
                Spacer()
                ProgressView()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Notify on arrival")
            .accessibilityValue("Updating")
        } else {
            Toggle(
                "Notify on arrival",
                isOn: Binding(
                    get: { parkArrival.isEnabled },
                    set: { newValue in
                        isTogglingParkArrival = true
                        Task {
                            if newValue {
                                await parkArrival.enable()
                            } else {
                                parkArrival.disable()
                            }
                            isTogglingParkArrival = false
                        }
                    }
                )
            )
            .tint(Color.rpplAccent)
            if parkArrival.permissionDenied {
                Text(
                    "Location or notification access was denied, so this stayed off. Allow both location and notifications in Settings, then try again."
                )
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
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
