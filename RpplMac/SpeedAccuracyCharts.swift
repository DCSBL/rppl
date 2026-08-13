import AppKit
import SwiftUI
import RpplCore

struct SpeedChartView: View {
    let points: [SpeedPoint]
    let range: ClosedRange<Date>
    let thresholds: AssumptionThresholds
    let highlight: AssumptionSegment?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Speed (usable km/h)")
                    .font(.headline)
                Spacer()
                Text("ride \(Int(thresholds.rideEnterSpeedKmh)) · swimMax \(Int(thresholds.swimMaxSpeedKmh))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            CGPlotView { context, size in
                Self.draw(
                    context: context,
                    size: size,
                    points: points,
                    range: range,
                    thresholds: thresholds,
                    highlight: highlight
                )
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private static func draw(
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
            let rect = CGRect(
                x: x(band.lowerBound),
                y: inset.minY,
                width: max(x(band.upperBound) - x(band.lowerBound), 1),
                height: inset.height
            )
            context.setFillColor(NSColor(AssumptionColors.color(for: highlight.code)).withAlphaComponent(0.18).cgColor)
            context.fill(rect)
        }

        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1)
        context.stroke(inset)

        drawRule(context: context, inset: inset, y: y(thresholds.rideEnterSpeedKmh), color: .systemBlue)
        drawRule(context: context, inset: inset, y: y(thresholds.swimMaxSpeedKmh), color: .systemTeal)

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

    private static func drawRule(context: CGContext, inset: CGRect, y: CGFloat, color: NSColor) {
        context.setStrokeColor(color.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.move(to: CGPoint(x: inset.minX, y: y))
        context.addLine(to: CGPoint(x: inset.maxX, y: y))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }
}

struct AccuracyChartView: View {
    let points: [AccuracyPoint]
    let range: ClosedRange<Date>
    let maxAccuracyM: Double
    let highlight: AssumptionSegment?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("GPS accuracy (m)")
                    .font(.headline)
                Spacer()
                Text("max \(Int(maxAccuracyM))m")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            CGPlotView { context, size in
                Self.draw(
                    context: context,
                    size: size,
                    points: points,
                    range: range,
                    maxAccuracyM: maxAccuracyM,
                    highlight: highlight
                )
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private static func draw(
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
            let rect = CGRect(
                x: x(band.lowerBound),
                y: inset.minY,
                width: max(x(band.upperBound) - x(band.lowerBound), 1),
                height: inset.height
            )
            context.setFillColor(NSColor(AssumptionColors.color(for: highlight.code)).withAlphaComponent(0.18).cgColor)
            context.fill(rect)
        }

        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.stroke(inset)

        context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.5).cgColor)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.move(to: CGPoint(x: inset.minX, y: y(maxAccuracyM)))
        context.addLine(to: CGPoint(x: inset.maxX, y: y(maxAccuracyM)))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

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
}
