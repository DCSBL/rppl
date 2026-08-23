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
                Text(LegalNoteFromDuco.dutch)
                    .font(.body)
                Text(LegalNoteFromDuco.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } header: {
                Text("A note from Duco")
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

/// Keep aligned with repo root `LEGAL.md` (“A note from Duco”).
private enum LegalNoteFromDuco {
    // Proofread only (spelling/grammar): abonnementen, professionele, anderen.
    static let dutch = """
        Hi! Mijn naam is Duco. Sinds dit jaar ben ik vaak bij een kabelpark te vinden om te wakeboarden. De gewone Apple Workout app is helaas te basis, waardoor ik op zoek gegaan ben naar een betere tracker. Het huidige aanbod voldeed helaas niet aan mijn verwachtingen; te complex of juist te gelimiteerd, verplichte abonnementen en de lust van het opvragen van data. Dat moest anders.

        Mijn professionele achtergrond zit in embedded software, dus het maken van een iOS app is nieuw. Hoewel ik graag zelf met de code aan de haal ga, is deze app vrijwel volledig met behulp van AI tot stand gekomen. Na meerdere testsessies durf ik deze app openbaar te maken, in de hoop dat anderen er wat aan hebben!

        Ik hoop dat je net als ik veel plezier hebt met het bijhouden van je sessies!

        -- Duco
        """

    static let english = """
        Hi! My name is Duco. Since this year I’ve often been at a cable park to wakeboard. The regular Apple Workout app is unfortunately too basic, so I went looking for a better tracker. The current offering unfortunately didn’t meet my expectations; too complex or too limited, mandatory subscriptions and a hunger for requesting data. That had to be different.

        My professional background is in embedded software, so making an iOS app is new. Although I like to dig into the code myself, this app was created almost entirely with the help of AI. After several test sessions I dare to make this app public, in the hope that others get something out of it!

        I hope that, like me, you enjoy tracking your sessions!

        -- Duco
        """
}

#Preview {
    NavigationStack {
        LegalTermsPrivacyView()
    }
}
