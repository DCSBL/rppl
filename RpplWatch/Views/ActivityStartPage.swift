import SwiftUI
import RpplCore

struct ActivityStartPage: View {
    let code: String
    var isStarting: Bool
    var enabled: Bool
    var needsSetup = false
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geo in
            let chevronSide = min(max(min(geo.size.width, geo.size.height) * 0.22, 36), 52)
            // The system shows the time anyway; at accessibility sizes the title needs the room.
            let showClock = geo.size.height >= 200 && !dynamicTypeSize.isAccessibilitySize

            Button(action: action) {
                cardStack(chevronSide: chevronSide, showClock: showClock, showIcon: geo.size.height >= 170,
                          iconHeight: min(max(geo.size.height * 0.2, 30), 46))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(!enabled && !isStarting)
            .accessibilityLabel(ActivityCodes.localizedTitle(for: code))
            .accessibilityHint(needsSetup
                ? String(localized: "Sets up permissions, then starts a session")
                : String(localized: "Starts a session"))
        }
        .containerBackground(Color.rpplIdleBackground.gradient, for: .tabView)
    }

    /// Template glyph per picker code; unknown codes fall back to the generic one.
    private static func iconAssetName(for code: String) -> String {
        ActivityCodes.pickerCodes.contains(code) ? "activity-\(code)" : "activity-other"
    }

    private func cardStack(chevronSide: CGFloat, showClock: Bool, showIcon: Bool, iconHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            if showClock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, style: .time)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.rpplIdlePrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if showIcon {
                Image(Self.iconAssetName(for: code))
                    .resizable()
                    .scaledToFit()
                    .frame(height: iconHeight)
                    .foregroundStyle(Color.rpplIdlePrimary)
                    .accessibilityHidden(true)
            }

            Text(ActivityCodes.localizedTitle(for: code))
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.rpplIdlePrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 6)

            Spacer(minLength: 8)

            startControl(side: chevronSide)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func startControl(side: CGFloat) -> some View {
        if isStarting {
            ProgressView()
                .tint(Color.rpplIdleAccent)
                .frame(width: side, height: side)
        } else if needsSetup {
            Text("Configure")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.rpplIdleAccentForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .frame(height: side)
                .background(Capsule().fill(Color.rpplIdleAccent))
        } else {
            Image(systemName: "chevron.right")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.rpplIdleAccentForeground)
                .frame(width: side, height: side)
                .background(Circle().fill(Color.rpplIdleAccent))
        }
    }
}
