import SwiftUI

struct StartCircleButton: View {
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Start")
                .font(.title2.bold())
                .frame(width: 120, height: 120)
                .background(Circle().fill(enabled ? Color.green : Color.green.opacity(0.4)))
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Start session")
    }
}
