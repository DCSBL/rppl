import Charts
import SwiftUI

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
                ForEach(segments) { segment in
                    RectangleMark(
                        xStart: .value("start", max(segment.start, range.lowerBound)),
                        xEnd: .value("end", min(segment.end, range.upperBound)),
                        yStart: .value("ylo", 2),
                        yEnd: .value("yhi", 3)
                    )
                    .foregroundStyle(AssumptionColors.color(for: segment.code).opacity(selectedID == segment.id ? 1 : 0.75))

                    if let activity = segment.motionActivity, !activity.isEmpty {
                        RuleMark(x: .value("a", segment.start))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        PointMark(
                            x: .value("a", segment.start),
                            y: .value("activity", 1)
                        )
                        .symbolSize(36)
                        .annotation(position: .overlay, alignment: .leading) {
                            Text(shortActivity(activity))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let water = segment.waterSubmersionState, !water.isEmpty {
                        PointMark(
                            x: .value("w", segment.start),
                            y: .value("water", 0)
                        )
                        .foregroundStyle(water == "submerged" ? Color.cyan : Color.gray)
                        .symbolSize(40)
                        .annotation(position: .overlay, alignment: .leading) {
                            Text(shortWater(water))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
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
            .frame(minHeight: 120)
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

    private func shortActivity(_ value: String) -> String {
        String(value.prefix(4))
    }

    private func shortWater(_ value: String) -> String {
        value == "submerged" ? "sub" : "dry"
    }
}
