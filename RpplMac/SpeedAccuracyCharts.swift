import Charts
import SwiftUI
import RpplCore

struct SpeedChartView: View {
    let points: [SpeedPoint]
    let range: ClosedRange<Date>
    let thresholds: AssumptionThresholds
    let highlight: AssumptionSegment?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Speed (usable km/h)")
                .font(.headline)
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("km/h", point.speedKmh)
                    )
                    .interpolationMethod(.linear)
                }

                RuleMark(y: .value("rideEnter", thresholds.rideEnterSpeedKmh))
                    .foregroundStyle(.blue.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("ride \(Int(thresholds.rideEnterSpeedKmh))")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                RuleMark(y: .value("swimMax", thresholds.swimMaxSpeedKmh))
                    .foregroundStyle(.teal.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("swimMax \(Int(thresholds.swimMaxSpeedKmh))")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                    }

                if let highlight {
                    RectangleMark(
                        xStart: .value("hs", max(highlight.start, range.lowerBound)),
                        xEnd: .value("he", min(highlight.end, range.upperBound))
                    )
                    .foregroundStyle(AssumptionColors.color(for: highlight.code).opacity(0.18))
                }
            }
            .chartXScale(domain: range.lowerBound...range.upperBound)
            .chartYScale(domain: 0...max(30, (points.map(\.speedKmh).max() ?? 20) + 5))
            .frame(minHeight: 140)
        }
    }
}

struct AccuracyChartView: View {
    let points: [AccuracyPoint]
    let range: ClosedRange<Date>
    let maxAccuracyM: Double
    let highlight: AssumptionSegment?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GPS accuracy (m)")
                .font(.headline)
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("m", point.horizontalAccuracy)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(.orange)
                }

                RuleMark(y: .value("max", maxAccuracyM))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("max \(Int(maxAccuracyM))m")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                if let highlight {
                    RectangleMark(
                        xStart: .value("hs", max(highlight.start, range.lowerBound)),
                        xEnd: .value("he", min(highlight.end, range.upperBound))
                    )
                    .foregroundStyle(AssumptionColors.color(for: highlight.code).opacity(0.18))
                }
            }
            .chartXScale(domain: range.lowerBound...range.upperBound)
            .chartYScale(domain: 0...max(maxAccuracyM * 1.5, (points.map(\.horizontalAccuracy).max() ?? maxAccuracyM) + 5))
            .frame(minHeight: 110)
        }
    }
}
