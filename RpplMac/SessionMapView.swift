import AppKit
import SwiftUI
import RpplCore

/// GPS track via Core Graphics (no SwiftUI Map / Canvas Metal).
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
            CGPlotView { context, size in
                Self.draw(context: context, size: size, locations: locations)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private static func draw(context: CGContext, size: CGSize, locations: [LocationSample]) {
        guard let first = locations.first else {
            drawCenteredLabel(context: context, size: size, text: "No GPS in window")
            return
        }
        guard locations.count >= 2, let bounds = geoBounds(locations) else {
            let text = String(format: "%.5f, %.5f", first.latitude, first.longitude)
            drawCenteredLabel(context: context, size: size, text: text)
            return
        }

        let inset: CGFloat = 8
        let width = max(size.width - inset * 2, 1)
        let height = max(size.height - inset * 2, 1)

        func project(_ sample: LocationSample) -> CGPoint {
            let xNorm = (sample.longitude - bounds.minLon) / (bounds.maxLon - bounds.minLon)
            let yNorm = (sample.latitude - bounds.minLat) / (bounds.maxLat - bounds.minLat)
            return CGPoint(
                x: inset + CGFloat(xNorm) * width,
                y: inset + CGFloat(1 - yNorm) * height
            )
        }

        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.beginPath()
        for (index, sample) in locations.enumerated() {
            let point = project(sample)
            if index == 0 { context.move(to: point) } else { context.addLine(to: point) }
        }
        context.strokePath()

        let start = project(locations[0])
        let end = project(locations[locations.count - 1])
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fillEllipse(in: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6))
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fillEllipse(in: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6))
    }

    private static func geoBounds(
        _ locations: [LocationSample]
    ) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
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

    private static func drawCenteredLabel(context: CGContext, size: CGSize, text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let textSize = string.size()
        let origin = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        string.draw(at: origin)
    }
}
