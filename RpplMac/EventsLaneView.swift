import Charts
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

            Chart {
                ForEach(visibleSegments) { segment in
                    if let band = clippedBand(for: segment) {
                        RectangleMark(
                            xStart: .value("start", band.lowerBound),
                            xEnd: .value("end", band.upperBound),
                            yStart: .value("ylo", 2),
                            yEnd: .value("yhi", 3)
                        )
                        .foregroundStyle(
                            AssumptionColors.color(for: segment.code)
                                .opacity(selectedID == segment.id ? 1 : 0.75)
                        )
                    }

                    if range.contains(segment.start),
                       let activity = segment.motionActivity,
                       !activity.isEmpty {
                        PointMark(
                            x: .value("a", segment.start),
                            y: .value("activity", 1)
                        )
                        .foregroundStyle(.secondary)
                        .symbolSize(28)
                    }

                    if range.contains(segment.start),
                       let water = segment.waterSubmersionState,
                       !water.isEmpty {
                        PointMark(
                            x: .value("w", segment.start),
                            y: .value("water", 0)
                        )
                        .foregroundStyle(water == "submerged" ? Color.cyan : Color.gray)
                        .symbolSize(28)
                    }
                }
            }
            .chartXScale(domain: range.lowerBound...range.upperBound)
            .chartYScale(domain: -0.5...3.5)
            .chartYAxis {
                AxisMarks(values: [0, 1, 2.5]) { value in
                    AxisValueLabel {
                        if let y = value.as(Double.self) {
                            switch y {
                            case 0: Text("water")
                            case 1: Text("activity")
                            case 2.5: Text("code")
                            default: EmptyView()
                            }
                        }
                    }
                }
            }
            .frame(height: 120)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geo[plotFrame].origin.x
                            if let date: Date = proxy.value(atX: x) {
                                onSelect(date)
                            }
                        }
                }
            }

            legend
        }
    }

    private var visibleSegments: [AssumptionSegment] {
        segments.filter { $0.duration > 0 && $0.start < range.upperBound && $0.end > range.lowerBound }
    }

    private func clippedBand(for segment: AssumptionSegment) -> ClosedRange<Date>? {
        SessionAnalysisPrep.clippedBand(start: segment.start, end: segment.end, range: range)
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
}
