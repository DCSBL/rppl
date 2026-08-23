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
                Text(
                    "Apple Watch is required to record. iPhone is for viewing, maps, and export only — open Rppl on your Watch and start a cable-park session."
                )
            }

            Section("Permissions") {
                Text(
                    "The Watch app requests Health, location, and motion when you start a session. iPhone does not record workouts."
                )
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
        .tint(Color.rpplAccent)
        }
    }
}

#Preview {
    NavigationStack {
        AppInfoView()
    }
}
