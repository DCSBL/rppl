import SwiftUI

/// Combined Terms of Use and Privacy Policy (single document).
/// Keep body copy aligned with repo root `LEGAL.md`.
struct LegalTermsPrivacyView: View {
    var body: some View {
        List {
            Section {
                Text(
                    "Rppl is a hobby project by Duco Sebel (the Netherlands). No money is earned from the app today. Using Rppl is entirely your own choice."
                )
                Text(
                    "These Terms & Privacy Policy are one document. Written in English; Dutch and EU law apply. The developer is based in the Netherlands."
                )
            } header: {
                Text("About")
            }

            Section {
                labeledBullet(
                    title: "Privacy first",
                    detail: "Session data is processed on your Apple Watch and iPhone to run the activity. We do not operate a Rppl cloud that receives your rides."
                )
                labeledBullet(
                    title: "Stays on your side",
                    detail: "Data is stored on your devices, in the Apple Health app when you allow Health access, and in your iCloud backup if you back up that device."
                )
                labeledBullet(
                    title: "Never shared by us",
                    detail: "Your data remains yours. We do not sell, rent, or share it with third parties unless you explicitly choose to — for example by exporting/sharing a session yourself, or by using a connection to another service that you enable."
                )
            } header: {
                Text("Privacy")
            } footer: {
                Text(
                    "Apple HealthKit data is used only to support health and fitness features (workout recording and related metrics), not for advertising or data brokering."
                )
            }

            Section {
                Text("Collected only to process your cable-park activity on your devices:")
                bullet("GPS location (routes, speed, ride detection)")
                bullet("Accelerometer and gyroscope / device motion")
                bullet("Heart rate and energy estimates (via HealthKit when allowed)")
                bullet("Air weather at the session location (temperature, humidity, condition)")
                bullet("Water temperature (Apple Watch Ultra, when available)")
                bullet("Automatic ride / inactive detections derived from the sensors above")
                bullet("An anonymous on-device tester identifier (not a name or account)")
            } header: {
                Text("What the app collects")
            } footer: {
                Text(
                    "We do not upload this information to a Rppl server. Transfer between Watch and iPhone uses Apple Watch Connectivity on your devices."
                )
            }

            Section {
                Text(
                    "Wakeboarding and water sports can be dangerous. Rppl must not be used to make unsafe or unwise decisions. You remain solely responsible for your safety, judgment, and equipment."
                )
                Text(
                    "By using this app you take your (expensive) Apple Watch on the water. That risk is yours alone. We are not liable for loss, damage, injury, or data loss arising from use of the app or from taking a Watch into a wet environment."
                )
                Text(
                    "The app is provided as-is, without warranties. To the fullest extent permitted under Dutch and EU law, liability is limited accordingly."
                )
            } header: {
                Text("Your responsibility")
            }

            Section {
                Text(
                    "We may change, pause, or remove features, or stop offering the app, at any time."
                )
                Text(
                    "We do not plan to monetize heavily, but we may add paid features, make existing features paid, or ask for donations — only to cover possible costs of running and distributing the app (for example Apple fees, tooling, or infrastructure)."
                )
                Text(
                    "Continued use after changes means you accept the updated terms. Material privacy changes will be reflected in this document."
                )
            } header: {
                Text("Service changes & costs")
            }

            Section {
                Text(
                    "These terms and the processing described here are governed by the laws of the Netherlands, and where applicable by EU law (including the GDPR for personal data)."
                )
                Text(
                    "Depending on your situation you may have rights of access, rectification, erasure, restriction, and objection. Because processing is local on your devices, exercise those rights mainly via your device controls, Health permissions, and deleting sessions or the app. Contact us if you need help."
                )
            } header: {
                Text("Law & your rights")
            }

            Section {
                Text("Questions about privacy or these terms:")
                if let mailURL = URL(string: "mailto:rppl@dcsbl.nl") {
                    Link("rppl@dcsbl.nl", destination: mailURL)
                } else {
                    Text("rppl@dcsbl.nl")
                }
                Text("Duco Sebel · Netherlands")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Contact")
            }

            Section {
                // Placeholder — replace with Duco’s personal copy when ready.
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("A note from Duco — text coming soon")
            } header: {
                Text("A note from Duco")
            } footer: {
                Text("Personal message from the developer — text will be added here.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.rpplBackground)
        .navigationTitle("Terms & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.rpplBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Color.rpplAccent)
    }

    @ViewBuilder
    private func labeledBullet(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func bullet(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(Color.rpplAccent)
        }
    }
}

#Preview {
    NavigationStack {
        LegalTermsPrivacyView()
    }
}
