import SwiftUI

/// Shown once, the first time a park-arrival notification is tapped: what just happened and why.
struct ParkArrivalExplainerView: View {
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.rpplAccent)

                Text("Why did I get this?")
                    .font(.title2.bold())
                    .foregroundStyle(Color.rpplText)

                Text(
                    "Your iPhone keeps a small on-device list of park locations and quietly watches for you crossing into one — no Rppl server, no tracking in between."
                )
                Text(
                    "Once you're clearly at a park (not just passing by), Rppl sends this one local notification, then stays quiet about that park for the rest of the day."
                )
                Text(
                    "This needs Rppl to still be running in the background, so if you haven't opened it in a while, reopen it once to keep the notifications coming."
                )
                Text(
                    "Turn this off anytime in Rppl settings."
                )
            }
            .font(.subheadline)
            .foregroundStyle(Color.rpplMuted)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RpplBackdrop())
            .safeAreaInset(edge: .bottom) {
                Button("Got it", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.rpplAccent)
                    .padding()
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ParkArrivalExplainerView(onDismiss: {})
}
