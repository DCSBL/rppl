import SwiftUI
import RpplCore

/// Lightweight GPS track — Canvas only (SwiftUI Map/Metal was crashing RenderBox on load).
struct SessionMapView: View {
    let locations: [LocationSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("GPS track")
                    .font(.headline)
                Spacer()
                Text("\(locations.count) pts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Group {
                if locations.count >= 2, let bounds = geoBounds {
                    Canvas { context, size in
                        var path = Path()
                        for (index, sample) in locations.enumerated() {
                            let point = project(sample, bounds: bounds, in: size)
                            if index == 0 {
                                path.move(to: point)
                            } else {
                                path.addLine(to: point)
                            }
                        }
                        context.stroke(path, with: .color(.blue), lineWidth: 2)

                        if let first = locations.first, let last = locations.last {
                            let start = project(first, bounds: bounds, in: size)
                            let end = project(last, bounds: bounds, in: size)
                            context.fill(
                                Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)),
                                with: .color(.green)
                            )
                            context.fill(
                                Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)),
                                with: .color(.red)
                            )
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                } else if let only = locations.first {
                    Text(String(format: "%.5f, %.5f", only.latitude, only.longitude))
                        .font(.body.monospacedDigit())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor))
                } else {
                    Text("No GPS in window")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var geoBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard let first = locations.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for sample in locations.dropFirst() {
            minLat = min(minLat, sample.latitude)
            maxLat = max(maxLat, sample.latitude)
            minLon = min(minLon, sample.longitude)
            maxLon = max(maxLon, sample.longitude)
        }
        // Pad tiny spans so a stationary cluster still draws.
        if maxLat - minLat < 0.0001 {
            minLat -= 0.0001
            maxLat += 0.0001
        }
        if maxLon - minLon < 0.0001 {
            minLon -= 0.0001
            maxLon += 0.0001
        }
        return (minLat, maxLat, minLon, maxLon)
    }

    private func project(
        _ sample: LocationSample,
        bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double),
        in size: CGSize
    ) -> CGPoint {
        let inset: CGFloat = 8
        let width = max(size.width - inset * 2, 1)
        let height = max(size.height - inset * 2, 1)
        let xNorm = (sample.longitude - bounds.minLon) / (bounds.maxLon - bounds.minLon)
        let yNorm = (sample.latitude - bounds.minLat) / (bounds.maxLat - bounds.minLat)
        return CGPoint(
            x: inset + CGFloat(xNorm) * width,
            y: inset + CGFloat(1 - yNorm) * height
        )
    }
}
