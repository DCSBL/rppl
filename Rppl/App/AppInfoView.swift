import SwiftUI

struct AppInfoView: View {
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
                Text("Rppl collects cable-park wakeboarding sessions from Apple Watch for analysis on iPhone and Mac.")
            }

            Section("Permissions") {
                Text("Health, location, and motion permissions are requested when needed for sync and viewing session data.")
                    .font(.subheadline)
                    .foregroundStyle(Color.rpplMuted)
            }

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
