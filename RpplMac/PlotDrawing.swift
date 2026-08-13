import AppKit
import RpplCore

enum PlotDrawing {
    static func color(for code: String) -> NSColor {
        switch code {
        case LabelCodes.waiting: return .systemGray
        case LabelCodes.riding: return .systemBlue
        case LabelCodes.swimming: return .systemTeal
        case LabelCodes.walking: return .systemOrange
        default: return .systemPurple
        }
    }

    static func drawMap(context: CGContext, size: CGSize, locations: [LocationSample]) {
        guard let first = locations.first else {
            drawCentered(context: context, size: size, text: "No GPS in window")
            return
        }
        guard locations.count >= 2, let bounds = geoBounds(locations) else {
            drawCentered(
                context: context,
                size: size,
                text: String(format: "%.5f, %.5f", first.latitude, first.longitude)
            )
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

    static func drawSpeed(
        context: CGContext,
        size: CGSize,
        points: [SpeedPoint],
        range: ClosedRange<Date>,
        thresholds: AssumptionThresholds,
        highlight: AssumptionSegment?
    ) {
        let inset = CGRect(x: 36, y: 8, width: max(size.width - 44, 1), height: max(size.height - 16, 1))
        let yMax = max(30, (points.map(\.speedKmh).filter(\.isFinite).max() ?? 20) + 5)
        let xSpan = max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
        func x(_ date: Date) -> CGFloat {
            inset.minX + CGFloat(date.timeIntervalSince(range.lowerBound) / xSpan) * inset.width
        }
        func y(_ kmh: Double) -> CGFloat {
            inset.maxY - CGFloat(kmh / yMax) * inset.height
        }
        if let highlight,
           let band = SessionAnalysisPrep.clippedBand(start: highlight.start, end: highlight.end, range: range) {
            context.setFillColor(color(for: highlight.code).withAlphaComponent(0.18).cgColor)
            context.fill(CGRect(
                x: x(band.lowerBound),
                y: inset.minY,
                width: max(x(band.upperBound) - x(band.lowerBound), 1),
                height: inset.height
            ))
        }
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.stroke(inset)
        strokeRule(context: context, inset: inset, y: y(thresholds.rideEnterSpeedKmh), color: .systemBlue)
        strokeRule(context: context, inset: inset, y: y(thresholds.swimMaxSpeedKmh), color: .systemTeal)
        guard points.count >= 2 else { return }
        context.setStrokeColor(NSColor.labelColor.cgColor)
        context.setLineWidth(1.5)
        context.beginPath()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: x(point.timestamp), y: y(point.speedKmh))
            if index == 0 { context.move(to: p) } else { context.addLine(to: p) }
        }
        context.strokePath()
    }

    static func drawAccuracy(
        context: CGContext,
        size: CGSize,
        points: [AccuracyPoint],
        range: ClosedRange<Date>,
        maxAccuracyM: Double,
        highlight: AssumptionSegment?
    ) {
        let inset = CGRect(x: 36, y: 8, width: max(size.width - 44, 1), height: max(size.height - 16, 1))
        let peak = points.map(\.horizontalAccuracy).filter(\.isFinite).max() ?? maxAccuracyM
        let yMax = max(maxAccuracyM * 1.5, peak + 5)
        let xSpan = max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
        func x(_ date: Date) -> CGFloat {
            inset.minX + CGFloat(date.timeIntervalSince(range.lowerBound) / xSpan) * inset.width
        }
        func y(_ meters: Double) -> CGFloat {
            inset.maxY - CGFloat(meters / yMax) * inset.height
        }
        if let highlight,
           let band = SessionAnalysisPrep.clippedBand(start: highlight.start, end: highlight.end, range: range) {
            context.setFillColor(color(for: highlight.code).withAlphaComponent(0.18).cgColor)
            context.fill(CGRect(
                x: x(band.lowerBound),
                y: inset.minY,
                width: max(x(band.upperBound) - x(band.lowerBound), 1),
                height: inset.height
            ))
        }
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.stroke(inset)
        strokeRule(context: context, inset: inset, y: y(maxAccuracyM), color: .systemRed)
        guard points.count >= 2 else { return }
        context.setStrokeColor(NSColor.systemOrange.cgColor)
        context.setLineWidth(1.5)
        context.beginPath()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: x(point.timestamp), y: y(point.horizontalAccuracy))
            if index == 0 { context.move(to: p) } else { context.addLine(to: p) }
        }
        context.strokePath()
    }

    static func drawEvents(
        context: CGContext,
        size: CGSize,
        segments: [AssumptionSegment],
        range: ClosedRange<Date>,
        selectedID: String?
    ) {
        let inset = CGRect(x: 36, y: 8, width: max(size.width - 44, 1), height: max(size.height - 16, 1))
        let xSpan = max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
        func x(_ date: Date) -> CGFloat {
            inset.minX + CGFloat(date.timeIntervalSince(range.lowerBound) / xSpan) * inset.width
        }
        func laneY(_ lane: CGFloat) -> CGFloat {
            inset.minY + (1 - lane / 3.5) * inset.height
        }
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.stroke(inset)
        let visible = segments.filter { $0.duration > 0 && $0.start < range.upperBound && $0.end > range.lowerBound }
        for segment in visible {
            guard let band = SessionAnalysisPrep.clippedBand(
                start: segment.start,
                end: segment.end,
                range: range
            ) else { continue }
            let y0 = laneY(3)
            let y1 = laneY(2)
            let alpha: CGFloat = selectedID == segment.id ? 1 : 0.75
            context.setFillColor(color(for: segment.code).withAlphaComponent(alpha).cgColor)
            context.fill(CGRect(
                x: x(band.lowerBound),
                y: min(y0, y1),
                width: max(x(band.upperBound) - x(band.lowerBound), 1),
                height: max(abs(y1 - y0), 1)
            ))
            if range.contains(segment.start), let activity = segment.motionActivity, !activity.isEmpty {
                let p = CGPoint(x: x(segment.start), y: laneY(1))
                context.setFillColor(NSColor.secondaryLabelColor.cgColor)
                context.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            }
            if range.contains(segment.start), let water = segment.waterSubmersionState, !water.isEmpty {
                let p = CGPoint(x: x(segment.start), y: laneY(0))
                let ns = water == "submerged" ? NSColor.systemCyan : NSColor.systemGray
                context.setFillColor(ns.cgColor)
                context.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            }
        }
    }

    private static func strokeRule(context: CGContext, inset: CGRect, y: CGFloat, color: NSColor) {
        context.setStrokeColor(color.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.move(to: CGPoint(x: inset.minX, y: y))
        context.addLine(to: CGPoint(x: inset.maxX, y: y))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
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

    private static func drawCentered(context: CGContext, size: CGSize, text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let textSize = string.size()
        string.draw(at: CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        ))
    }
}
