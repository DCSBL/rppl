import Charts
import RpplCore
import SwiftUI

/// Season tiles under "Total": one bar per session (days without a session never show up), plus
/// monthly water and air temperature. The caller only shows this once `SeasonStats.showsCharts`.
struct SeasonCharts: View {
    let season: SeasonStats
    @State private var showsDuration = false

    var body: some View {
        VStack(spacing: RpplDesign.tileSpacing) {
            distanceTile
            InfoTileGrid {
                lapsTile
                energyTile
            }
            temperatureTile
        }
    }

    private var distanceTile: some View {
        let points = showsDuration ? season.duration : season.distanceMeters
        return InfoTile(
            showsDuration ? "Duration per session" : "Distance per session",
            metric: showsDuration ? .duration : .distance
        ) {
            Picker("Distance & duration", selection: $showsDuration) {
                Text("Distance").tag(false)
                Text("Duration").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if let mean = Self.mean(points) {
                MetricValue(
                    showsDuration ? DurationFormat.total(mean) : DistanceFormat.kilometers(mean),
                    size: .large,
                    caption: "Average per session"
                )
            }
            SeasonBarChart(
                points: points,
                tint: (showsDuration ? MetricKind.duration : .distance).tint,
                showsMonths: true,
                height: 110
            )
        }
    }

    private var lapsTile: some View {
        InfoTile("Laps", metric: .laps) {
            barsTile(season.laps, tint: MetricKind.laps.tint) { String(Int($0.rounded())) }
        }
    }

    private var energyTile: some View {
        InfoTile("Calories", metric: .energy) {
            barsTile(season.kilocalories, tint: MetricKind.energy.tint) { EnergyFormat.kilocalories($0) }
        }
    }

    @ViewBuilder
    private func barsTile(
        _ points: [SeasonStats.Point],
        tint: Color,
        format: (Double) -> String
    ) -> some View {
        if let mean = Self.mean(points) {
            MetricValue(format(mean), size: .large, caption: "Average per session")
        }
        SeasonBarChart(points: points, tint: tint, showsMonths: false, height: 70)
    }

    @ViewBuilder
    private var temperatureTile: some View {
        if !season.months.isEmpty {
            InfoTile("Water and air", metric: .water) {
                SeasonTemperatureChart(months: season.months)
            }
        }
    }

    private static func mean(_ points: [SeasonStats.Point]) -> Double? {
        points.isEmpty ? nil : points.reduce(0) { $0 + $1.value } / Double(points.count)
    }
}

private struct SeasonBarChart: View {
    let points: [SeasonStats.Point]
    let tint: Color
    let showsMonths: Bool
    let height: CGFloat

    /// Index of the first session of each month, where the axis gets its month label.
    private var monthStarts: [Int] {
        let calendar = Calendar.current
        return points.indices.filter { index in
            index == 0
                || !calendar.isDate(points[index].date, equalTo: points[index - 1].date, toGranularity: .month)
        }
    }

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { index, point in
            BarMark(x: .value("Session", index), y: .value("Value", point.value), width: .ratio(0.8))
                .cornerRadius(2)
                .foregroundStyle(tint)
        }
        .chartXScale(domain: -1...points.count)
        .chartYAxis(.hidden)
        .chartXAxis {
            if showsMonths {
                AxisMarks(values: monthStarts) { value in
                    AxisValueLabel(anchor: .topLeading) {
                        if let index = value.as(Int.self), points.indices.contains(index) {
                            Text(points[index].date, format: .dateTime.month(.abbreviated))
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sessions"))
        .accessibilityValue(Text("\(points.count)"))
    }
}

private struct SeasonTemperatureChart: View {
    let months: [SeasonStats.Month]

    private struct Reading: Identifiable {
        let id: String
        let name: String
        let date: Date
        let celsius: Double
    }

    private static let water = String(localized: "Water")
    private static let air = String(localized: "Air")

    private var readings: [Reading] {
        months.flatMap { month -> [Reading] in
            var rows: [Reading] = []
            if let water = month.waterCelsius {
                rows.append(Reading(id: "w\(month.start)", name: Self.water, date: month.start, celsius: water))
            }
            if let air = month.airCelsius {
                rows.append(Reading(id: "a\(month.start)", name: Self.air, date: month.start, celsius: air))
            }
            return rows
        }
    }

    var body: some View {
        Chart(readings) { reading in
            LineMark(
                x: .value("Month", reading.date, unit: .month),
                y: .value("Temperature", reading.celsius),
                series: .value("Series", reading.name)
            )
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .foregroundStyle(by: .value("Series", reading.name))
            PointMark(
                x: .value("Month", reading.date, unit: .month),
                y: .value("Temperature", reading.celsius)
            )
            .foregroundStyle(by: .value("Series", reading.name))
        }
        .chartForegroundStyleScale([
            Self.water: MetricKind.water.tint,
            Self.air: MetricKind.air.tint,
        ])
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.rpplMuted.opacity(0.15))
                AxisValueLabel {
                    if let celsius = value.as(Double.self) {
                        Text(verbatim: TemperatureFormat.celsius(celsius))
                    }
                }
            }
        }
        .frame(height: 150)
    }
}
