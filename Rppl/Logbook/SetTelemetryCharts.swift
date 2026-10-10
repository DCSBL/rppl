import Charts
import RpplCore
import SwiftUI

/// Debug-only demo: speed, altitude and g-force curves under a set card. Not linked to the map.
struct SetTelemetryCharts: View {
    let telemetry: SetTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            chart(
                title: "Speed", metric: .speed, points: telemetry.speedKmh,
                unit: "km/h", style: .line, includeZero: true
            )
            chart(
                title: "Altitude", systemImage: "mountain.2", tint: MetricKind.distance.tint,
                points: telemetry.altitudeMeters, unit: "m", style: .line, includeZero: false
            )
            chart(
                title: "G-force", systemImage: "waveform.path.ecg", tint: MetricKind.energy.tint,
                points: telemetry.gForce, unit: "g", style: .bars, includeZero: true
            )
        }
    }

    private enum Style { case line, bars }

    @ViewBuilder
    private func chart(
        title: LocalizedStringKey,
        metric: MetricKind? = nil,
        systemImage: String? = nil,
        tint: Color? = nil,
        points: [SetTelemetry.Point],
        unit: String,
        style: Style,
        includeZero: Bool
    ) -> some View {
        let color = tint ?? metric?.tint ?? Color.rpplAccent
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    TileHeader(
                        title: title,
                        systemImage: systemImage ?? metric?.systemImage ?? "chart.xyaxis.line",
                        tint: color,
                        metric: metric
                    )
                    Spacer()
                    if let peak = points.max(by: { $0.value < $1.value }) {
                        Text(verbatim: "max \(peak.value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.rpplMuted)
                    }
                }
                plot(points: points, color: color, style: style, includeZero: includeZero)
                    .frame(height: 96)
            }
        }
    }

    private func plot(
        points: [SetTelemetry.Point],
        color: Color,
        style: Style,
        includeZero: Bool
    ) -> some View {
        Chart(points, id: \.offset) { point in
            switch style {
            case .line:
                AreaMark(x: .value("Time", point.offset), y: .value("Value", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                LineMark(x: .value("Time", point.offset), y: .value("Value", point.value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(color)
            case .bars:
                BarMark(
                    x: .value("Time", point.offset),
                    y: .value("Value", point.value),
                    width: .fixed(2)
                )
                .cornerRadius(1)
                .foregroundStyle(color.opacity(0.4 + 0.6 * min(point.value / 3, 1)))
            }
        }
        .chartYScale(domain: .automatic(includesZero: includeZero))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.rpplMuted.opacity(0.15))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(verbatim: Self.clock(seconds))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.rpplMuted.opacity(0.15))
                AxisValueLabel()
            }
        }
        .chartPlotStyle { $0.clipped() }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
