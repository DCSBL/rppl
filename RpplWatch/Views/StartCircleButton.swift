import SwiftUI

struct StartCircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Start")
                .font(.title2.bold())
                .frame(width: 120, height: 120)
                .background(Circle().fill(Color.green))
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start session")
    }
}
