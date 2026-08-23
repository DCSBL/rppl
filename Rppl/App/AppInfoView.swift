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

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Privacy first")
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
