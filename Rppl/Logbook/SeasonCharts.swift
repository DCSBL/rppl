import Charts
import RpplCore
import SwiftUI

/// Season tiles under "Total": one bar per session (days without a session never show up), plus
/// water and air temperature per day. The caller only shows this once `SeasonStats.showsCharts`.
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
                height: 110,
                identifier: showsDuration ? "season-duration-chart" : "season-distance-chart",
                axisLabel: showsDuration ? { DurationFormat.total($0) } : { DistanceFormat.kilometers($0) }
            )
        }
    }

    private var lapsTile: some View {
        InfoTile("Laps", metric: .laps) {
            barsTile(season.laps, identifier: "season-laps-chart", tint: MetricKind.laps.tint) { String(Int($0.rounded())) }
        }
    }

    private var energyTile: some View {
        InfoTile("Calories", metric: .energy) {
            barsTile(season.kilocalories, identifier: "season-calories-chart", tint: MetricKind.energy.tint) { EnergyFormat.kilocalories($0) }
        }
    }

    @ViewBuilder
    private func barsTile(
        _ points: [SeasonStats.Point],
        identifier: String,
        tint: Color,
        format: @escaping (Double) -> String
    ) -> some View {
        if let mean = Self.mean(points) {
            MetricValue(format(mean), size: .large, caption: "Average per session")
        }
        SeasonBarChart(
            points: points, tint: tint, showsMonths: false, height: 70, identifier: identifier, axisLabel: format
        )
    }

    @ViewBuilder
    private var temperatureTile: some View {
        if !season.days.isEmpty {
            InfoTile("Water and air", metric: .water) {
                SeasonTemperatureChart(days: season.days)
                    .accessibilityIdentifier("season-temperature-chart")
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
    let identifier: String
    let axisLabel: (Double) -> String

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
            // Explicit rectangle: a `BarMark` ratio width collapses to nothing on a numeric x axis.
            RectangleMark(
                xStart: .value("Start", Double(index) - 0.4),
                xEnd: .value("End", Double(index) + 0.4),
                yStart: .value("Base", 0),
                yEnd: .value("Value", point.value)
            )
            .cornerRadius(2)
                .foregroundStyle(tint)
        }
        .chartXScale(domain: -1...Double(points.count))
        .chartYScale(domain: 0...(points.map(\.value).max() ?? 1))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.rpplMuted.opacity(0.15))
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(verbatim: axisLabel(number)) }
                }
            }
        }
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
        .accessibilityIdentifier(identifier)
    }
}

private struct SeasonTemperatureChart: View {
    let days: [SeasonStats.Day]

    private struct Reading: Identifiable {
        let id: String
        let name: String
        let date: Date
        let celsius: Double
    }

    private static let water = String(localized: "Water")
    private static let air = String(localized: "Air")

    private var readings: [Reading] {
        days.flatMap { day -> [Reading] in
            var rows: [Reading] = []
            if let water = day.waterCelsius {
                rows.append(Reading(id: "w\(day.start)", name: Self.water, date: day.start, celsius: water))
            }
            if let air = day.airCelsius {
                rows.append(Reading(id: "a\(day.start)", name: Self.air, date: day.start, celsius: air))
            }
            return rows
        }
    }

    var body: some View {
        Chart(readings) { reading in
            LineMark(
                x: .value("Day", reading.date, unit: .day),
                y: .value("Temperature", reading.celsius),
                series: .value("Series", reading.name)
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .foregroundStyle(by: .value("Series", reading.name))
            PointMark(
                x: .value("Day", reading.date, unit: .day),
                y: .value("Temperature", reading.celsius)
            )
            .symbolSize(24)
            .symbol(by: .value("Series", reading.name))
            .foregroundStyle(by: .value("Series", reading.name))
        }
        .chartForegroundStyleScale([
            Self.water: MetricKind.water.tint,
            Self.air: MetricKind.air.tint,
        ])
        // Distinct shapes so the two series don't rely on color alone.
        .chartSymbolScale([
            Self.water: BasicChartSymbolShape.circle,
            Self.air: BasicChartSymbolShape.square,
        ])
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
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
