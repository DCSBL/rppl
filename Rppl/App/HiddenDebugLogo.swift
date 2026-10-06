import SwiftUI

/// About-page logo that opens the debug screen on a hold: 1 s of nothing, then a 2 s ring fills.
/// Taps and short holds do nothing visible.
struct HiddenDebugLogo: View {
    var onUnlock: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        Image("icon-simple")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 48, height: 48)
            .foregroundStyle(Color.rpplMuted.opacity(0.4 + 0.6 * progress))
            .overlay {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.rpplAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-8)
                    .opacity(progress > 0 ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 3, perform: {
                progress = 0
                onUnlock()
            }, onPressingChanged: { pressing in
                if pressing {
                    withAnimation(.linear(duration: 2).delay(1)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            })
            .accessibilityHidden(true)
    }
}
