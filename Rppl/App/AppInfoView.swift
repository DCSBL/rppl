import SwiftUI

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

                Section("Legal") {
                    LabeledContent("Privacy") {
                        Text("Alpha — no cloud upload")
                            .foregroundStyle(Color.rpplMuted)
                    }
                    LabeledContent("Terms") {
                        Text("Internal testing only")
                            .foregroundStyle(Color.rpplMuted)
                    }
                }
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
