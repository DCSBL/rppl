import RpplCore
import SwiftUI

/// Wind-rose badge overlaid on the park map: a flower of static petals with the one matching
/// the current wind direction lit up. Deliberately not compass-shaped — no cardinal ring, no
/// spinning needle — so it doesn't read as a instrument the rider has to interpret.
struct WindRoseView: View {
    let directionDegrees: Double
    let speedKmh: Double
    /// Map camera heading, so petals stay screen-true when the rider rotates the map.
    var mapHeading: Double = 0

    private static let petalCount = 8
    private static let calmThresholdKmh = 1.0

    private var direction: CompassDirection8 { CompassDirection8(degrees: directionDegrees) }
    private var isCalm: Bool { speedKmh < Self.calmThresholdKmh }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                ForEach(0..<Self.petalCount, id: \.self) { index in
                    petal(index: index)
                }
                Image(systemName: "wind")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.rpplMuted)
            }
            .frame(width: 50, height: 50)
            .overlay(Circle().strokeBorder(Color.rpplText.opacity(0.08), lineWidth: 1))

            if isCalm {
                Text(String(localized: "Calm"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.rpplText)
            } else {
                Text(direction.abbreviation)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.rpplText)
                Text(DistanceFormat.kilometersPerHour(speedKmh))
                    .font(.caption2)
                    .foregroundStyle(Color.rpplMuted)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func petal(index: Int) -> some View {
        let isActive = !isCalm && index == direction.rawValue
        let length: CGFloat = isActive ? 20 : 10
        return WindRosePetal()
            .fill(isActive ? Color.rpplAccent : Color.rpplMuted.opacity(0.3))
            .frame(width: isActive ? 7 : 4, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(Double(index) * 45 - mapHeading))
    }

    private var accessibilityText: String {
        isCalm
            ? String(localized: "Wind calm")
            : String(localized: "Wind from \(direction.name), \(DistanceFormat.kilometersPerHour(speedKmh))")
    }
}

/// A single wind-rose petal: a leaf shape tapering from a wide base to a point, in contrast to
/// a compass needle's straight line.
private struct WindRosePetal: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.midY))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
