import RpplCore
import SwiftUI

/// Compact wind indicator overlaid on the park map: a needle pointing where the wind blows from,
/// plus a small "N" mark so the needle reads correctly against the map's current rotation.
struct WindRoseView: View {
    let directionDegrees: Double
    let speedKmh: Double
    /// Map camera heading, so the needle and north mark stay screen-true when the rider rotates the map.
    var mapHeading: Double = 0

    private static let calmThresholdKmh = 1.0
    private static let dialSize: CGFloat = 22

    private var direction: CompassDirection8 { CompassDirection8(degrees: directionDegrees) }
    private var isCalm: Bool { speedKmh < Self.calmThresholdKmh }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(.regularMaterial)
                Text(verbatim: "N")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.primary)
                    .offset(y: -(Self.dialSize / 2 - 4))
                    .rotationEffect(.degrees(-mapHeading))
                if !isCalm {
                    WindNeedle()
                        .fill(Color.rpplAccent)
                        .frame(width: 4, height: Self.dialSize * 0.5)
                        .rotationEffect(.degrees(directionDegrees - mapHeading))
                }
            }
            .frame(width: Self.dialSize, height: Self.dialSize)
            .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1))

            if !isCalm {
                Text(DistanceFormat.kilometersPerHour(speedKmh))
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        isCalm
            ? String(localized: "Wind calm")
            : String(localized: "Wind from \(direction.name), \(DistanceFormat.kilometersPerHour(speedKmh))")
    }
}

/// A slim needle shape pointing "up" (north) at rotation 0, tapering to a point.
private struct WindNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.25))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
