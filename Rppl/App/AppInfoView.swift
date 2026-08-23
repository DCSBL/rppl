import SwiftUI
import RpplCore

struct AppInfoView: View {
    @State private var permissions = PhonePermissionsController.shared

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Platform", value: "iPhone")
                } header: {
                    Text("About")
                } footer: {
                    Text(
                        "Apple Watch is required to record. iPhone is for viewing, maps, and export only — open Rppl on your Watch and start a cable-park session."
                    )
                }

                PhonePermissionsListSection(permissions: permissions)

                Section {
                    Text(
                        """
                        Rppl does not upload session data to the cloud. Recordings stay on your Watch and iPhone until you choose to export them.

                        Export exists so you can share raw, unfiltered session data for analysis. An export includes session metadata (with a random tester ID), ride/pause detections, GPS locations (precise coordinates — not anonymized), device motion, heart rate and energy, water temperature when available, and derived stats.

                        A unique random tester ID is created on first app launch and stored on this device. Reinstalling the app generates a new ID.

                        If you share an export (AirDrop, Files, email, or any other channel), you are responsible for who receives it and how it is used. We may ask for a copy when analytics look wrong — sending one is always your choice.
                        """
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.rpplMuted)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Privacy & export")
                }

                Section("Terms") {
                    Text("Internal alpha testing only. Not a consumer product release.")
                        .font(.footnote)
                        .foregroundStyle(Color.rpplMuted)
                }

                Section {
                    Image("icon-simple")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(Color.rpplMuted.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                        .accessibilityHidden(true)
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
        }
    }
}

#Preview {
    NavigationStack {
        AppInfoView()
    }
}
