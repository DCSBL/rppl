import AppKit
import SwiftUI
import RpplCore

struct EventsLaneView: View {
    let segments: [AssumptionSegment]
    let range: ClosedRange<Date>
    let selectedID: String?
    let onSelect: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assumptions / activity / water")
                .font(.headline)
            GeometryReader { geo in
                ZStack {
                    CGPlotView { context, size in
                        Self.draw(
                            context: context,
                            size: size,
                            segments: segments,
                            range: range,
                            selectedID: selectedID
                        )
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    onSelect(date(atX: value.location.x, width: geo.size.width))
                                }
                        )
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            legend
        }
    }

    private func date(atX x: CGFloat, width: CGFloat) -> Date {
        let insetX: CGFloat = 36
        let plotWidth = max(width - 44, 1)
        let clamped = min(max(x - insetX, 0), plotWidth)
        let t = Double(clamped / plotWidth)
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        return range.lowerBound.addingTimeInterval(t * span)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("waiting", .gray)
            legendItem("riding", .blue)
            legendItem("swimming", .teal)
            legendItem("walking", .orange)
            legendItem("other", .purple)
        }
        .font(.caption2)
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
        }
    }

    private static func draw(
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
            let rect = CGRect(
                x: x(band.lowerBound),
                y: min(y0, y1),
                width: max(x(band.upperBound) - x(band.lowerBound), 1),
                height: max(abs(y1 - y0), 1)
            )
            let alpha: CGFloat = selectedID == segment.id ? 1 : 0.75
            context.setFillColor(NSColor(AssumptionColors.color(for: segment.code)).withAlphaComponent(alpha).cgColor)
            context.fill(rect)

            if range.contains(segment.start),
               let activity = segment.motionActivity,
               !activity.isEmpty {
                let p = CGPoint(x: x(segment.start), y: laneY(1))
                context.setFillColor(NSColor.secondaryLabelColor.cgColor)
                context.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            }
            if range.contains(segment.start),
               let water = segment.waterSubmersionState,
               !water.isEmpty {
                let p = CGPoint(x: x(segment.start), y: laneY(0))
                let color = water == "submerged" ? NSColor.systemCyan : NSColor.systemGray
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            }
        }
    }
}
