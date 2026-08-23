import SwiftUI
import RpplCore

struct ActivityStartPage: View {
    let code: String
    var isStarting: Bool
    var enabled: Bool
    let action: () -> Void

    var body: some View {
        GeometryReader { geo in
            let chevronSide = min(max(min(geo.size.width, geo.size.height) * 0.22, 36), 52)
            let showClock = geo.size.height >= 200

            Button(action: action) {
                cardStack(chevronSide: chevronSide, showClock: showClock)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(!enabled && !isStarting)
            .accessibilityLabel(ActivityCodes.localizedTitle(for: code))
            .accessibilityHint(String(localized: "Starts a session"))
        }
        .containerBackground(Color.rpplIdleBackground.gradient, for: .tabView)
    }

    private func cardStack(chevronSide: CGFloat, showClock: Bool) -> some View {
        VStack(spacing: 6) {
            if showClock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, style: .time)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.rpplIdlePrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text(ActivityCodes.localizedTitle(for: code))
                .font(.headline)
                .foregroundStyle(Color.rpplIdlePrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)

            Spacer(minLength: 0)

            startControl(side: chevronSide)
        }
    }

    @ViewBuilder
    private func startControl(side: CGFloat) -> some View {
        if isStarting {
            ProgressView()
                .tint(Color.rpplIdleAccent)
                .frame(width: side, height: side)
        } else {
            Image(systemName: "chevron.right")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.rpplIdleAccentForeground)
                .frame(width: side, height: side)
                .background(Circle().fill(Color.rpplIdleAccent))
        }
    }
}
