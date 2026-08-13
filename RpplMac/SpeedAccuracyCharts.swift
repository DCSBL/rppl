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
            HStack {
                Text("Speed (usable km/h)")
                    .font(.headline)
                Spacer()
                Text("ride \(Int(thresholds.rideEnterSpeedKmh)) · swimMax \(Int(thresholds.swimMaxSpeedKmh))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("km/h", point.speedKmh)
                    )
                    .interpolationMethod(.linear)
                }

                RuleMark(y: .value("rideEnter", thresholds.rideEnterSpeedKmh))
                    .foregroundStyle(.blue.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                RuleMark(y: .value("swimMax", thresholds.swimMaxSpeedKmh))
                    .foregroundStyle(.teal.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                if let highlight, let band = highlightBand(for: highlight) {
                    RectangleMark(
                        xStart: .value("hs", band.lowerBound),
                        xEnd: .value("he", band.upperBound)
                    )
                    .foregroundStyle(AssumptionColors.color(for: highlight.code).opacity(0.18))
                }
            }
            .chartXScale(domain: range.lowerBound...range.upperBound)
            .chartYScale(domain: 0...yMax)
            .frame(height: 140)
        }
    }

    private var yMax: Double {
        let peak = points.map(\.speedKmh).filter(\.isFinite).max() ?? 20
        return max(30, peak + 5)
    }

    private func highlightBand(for highlight: AssumptionSegment) -> ClosedRange<Date>? {
        SessionAnalysisPrep.clippedBand(start: highlight.start, end: highlight.end, range: range)
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
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                if let highlight, let band = highlightBand(for: highlight) {
                    RectangleMark(
                        xStart: .value("hs", band.lowerBound),
                        xEnd: .value("he", band.upperBound)
                    )
                    .foregroundStyle(AssumptionColors.color(for: highlight.code).opacity(0.18))
                }
            }
            .chartXScale(domain: range.lowerBound...range.upperBound)
            .chartYScale(domain: 0...yMax)
            .frame(height: 110)
        }
    }

    private var yMax: Double {
        let peak = points.map(\.horizontalAccuracy).filter(\.isFinite).max() ?? maxAccuracyM
        let candidate = max(maxAccuracyM * 1.5, peak + 5)
        return candidate.isFinite ? candidate : maxAccuracyM * 1.5
    }

    private func highlightBand(for highlight: AssumptionSegment) -> ClosedRange<Date>? {
        SessionAnalysisPrep.clippedBand(start: highlight.start, end: highlight.end, range: range)
    }
}
