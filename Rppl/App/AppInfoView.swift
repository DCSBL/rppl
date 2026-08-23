import SwiftUI
import UniformTypeIdentifiers
import RpplCore

struct AppInfoView: View {
    @State private var permissions = PhonePermissionsController.shared
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var showImportError = false
    @State private var importErrorText: String?
    @State private var showImportSuccess = false

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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("On your devices")
                            .font(.body.weight(.semibold))
                        Text(
                            "Rppl processes your session on your Watch and iPhone. We do not upload rides to a Rppl cloud or share your data with others."
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.rpplMuted)
                        Text(
                            "Data stays on your device, in the Health app (when allowed), and in your iCloud backup if you back up that device."
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
            .navigationTitle("rppl")
            .toolbarBackground(Color.rpplBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Color.rpplAccent)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert(
                "Could Not Import Session",
                isPresented: $showImportError,
                presenting: importErrorText
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .alert("Session Imported", isPresented: $showImportSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The session is in your logbook. It was not written to Health.")
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
                    try await connectivity.importExportedSession(from: url)
                    isImporting = false
                    showImportSuccess = true
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
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            return String(localized: "Something went wrong while importing the session.")
        }
        return description
    }
}

#Preview {
    NavigationStack {
        AppInfoView()
    }
}
