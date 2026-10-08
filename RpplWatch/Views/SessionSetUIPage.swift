import SwiftUI
import RpplCore

/// Product session UI: Riding and Inactive share one fixed status block (`statusBlock`) — only
/// color/icon/label and a couple of source values differ. Both sit in the same vertical-page
/// container so fonts and spacing match; Riding has only the status page. Inactive pages vertically (`.verticalPage`, same pattern as `IdleSessionView`) between the
/// status block and a session summary page.
struct SessionSetUIPage: View {
    @Bindable var session: WatchSessionController
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Group {
            if session.isProductPaused {
                pausedView
            } else if session.lastConfidentCode == DetectionCodes.riding {
                ridingView
            } else {
                inactiveView
            }
        }
    }

    // MARK: - Product paused

    private var pausedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paused")
                    .font(.headline.bold())
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .alwaysOnSecondaryChrome(isLuminanceReduced)

                Text(SessionFormatters.elapsed(session.elapsed))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.yellow)

                Text("Timers paused")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .alwaysOnSecondaryChrome(isLuminanceReduced)

                SessionMetricRow(
                    label: "Distance",
                    metric: .distance,
                    value: SessionFormatters.distance(session.totalDistanceM)
                )
                SessionMetricRow(
                    label: "Sets",
                    metric: .sets,
                    value: "\(session.setCount)"
                )

                WatchLastSetSection(
                    duration: session.lastSetDuration,
                    distanceMeters: session.lastSetMeters,
                    lapCount: session.lastSetLapCount,
                    didCompleteSet: session.didCompleteSet
                )
                .alwaysOnSecondaryChrome(isLuminanceReduced)

                Button {
                    WakeLog.debug(.ui, "tap Resume from paused metrics")
                    session.resumeSession()
                } label: {
                    Text("Resume").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(session.isStopping)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Riding (status page only) / Inactive (vertical pages: status, then summary)

    private var ridingView: some View {
        // Same container as Inactive so both states lay out, size and space every element alike.
        TabView {
            statusBlock(isRiding: true)
        }
        .tabViewStyle(.verticalPage)
    }

    private var inactiveView: some View {
        // Same vertical-page pattern as `IdleSessionView` — proven on-device, unlike the earlier
        // `.scrollTargetBehavior(.viewAligned)` attempt, which left the summary unreachable.
        TabView {
            statusBlock(isRiding: false)
            sessionSummaryPage
        }
        .tabViewStyle(.verticalPage)
    }

    /// Shared Riding/Inactive block: wall clock, status line, hero segment/total time, then
    /// distance/speed/laps, water temp, heart rate and total calories. Identical layout for both
    /// states — only color/icon/label and the segment-time/speed source differ.
    private func statusBlock(isRiding: Bool) -> some View {
        // Riding: your own live speed. Inactive: the cable's speed from finished sets — the live
        // GPS reading at the dock is walking pace or noise.
        let speedKmh = isRiding ? session.currentSetSpeedKmh : session.cableSpeedKmh
        let lapCount = session.isSetOngoing ? session.currentSetLapCount : session.lastSetLapCount

        return VStack(alignment: .leading, spacing: 8) {
            // No wall-clock row — watchOS already shows the real time natively.
            statusLine(
                primary: isRiding ? "Riding" : "Inactive",
                color: isRiding ? .blue : .gray,
                icon: isRiding ? "play.circle.fill" : "pause.circle.fill"
            )

            heroTimeRow(isRiding: isRiding)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                metricTile(
                    value: SessionFormatters.distance(session.displaySetMeters),
                    label: "DIST",
                    metric: .distance
                )
                metricTile(
                    value: speedKmh.map { DistanceFormat.speedValue($0) } ?? "--",
                    label: DistanceFormat.speedUnitSymbol(),
                    metric: .speed,
                    caption: isRiding ? LocalizedStringKey("Current") : LocalizedStringKey("Cable")
                )
                metricTile(
                    value: "\(lapCount)",
                    label: "LAPS",
                    metric: .laps
                )
            }

            if session.waterTemperatureAvailable || session.waterTemperatureDisplay != nil {
                metricTile(
                    value: session.waterTemperatureDisplay.map {
                        SessionFormatters.waterTemp($0.celsius, isEstimate: $0.isEstimate)
                    } ?? TemperatureFormat.placeholder,
                    label: "WATER",
                    metric: .water
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                heartRateRow
                    .frame(maxWidth: .infinity)
                metricTile(
                    value: session.totalEnergyKilocalories.map { SessionFormatters.calories($0) } ?? "--",
                    label: "CAL",
                    metric: .energy
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private func heroTimeRow(isRiding: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(
                SessionFormatters.segmentDuration(
                    isRiding ? session.currentSetDuration : session.currentInactiveDuration
                )
            )
            .foregroundStyle(isRiding ? .blue : .gray)

            Text("/")
                .font(.title2)
                .foregroundStyle(.secondary)

            // Total elapsed session time — same "workout yellow" Apple's own Workout app uses
            // for its hero elapsed-time metric (also used for the Paused timer, see `pausedView`).
            Text(SessionFormatters.elapsed(session.elapsed))
                .foregroundStyle(.yellow)
        }
        .font(.system(.largeTitle, design: .rounded).bold())
        .monospacedDigit()
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .alwaysOnSupportingMetric(isLuminanceReduced)
    }

    private func metricTile(
        value: String,
        label: String,
        metric: WatchMetric,
        caption: LocalizedStringKey? = nil
    ) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).bold())
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .alwaysOnSupportingMetric(isLuminanceReduced)
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(metric.tint)
                .alwaysOnSecondaryChrome(isLuminanceReduced)
            if let caption {
                // Says which speed this is, right under the value it describes.
                Text(caption)
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .alwaysOnSecondaryChrome(isLuminanceReduced)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session summary (Inactive only; second vertical page)

    private var totalRidingDuration: TimeInterval {
        session.cumulativeRidingDuration + (session.lastConfidentCode == DetectionCodes.riding ? session.currentSetDuration : 0)
    }

    private var totalInactiveDuration: TimeInterval {
        session.cumulativeInactiveDuration
            + (session.lastConfidentCode == DetectionCodes.inactive ? session.currentInactiveDuration : 0)
    }

    private var sessionSummaryPage: some View {
        ScrollView {
            sessionSummaryContent
                .padding(.horizontal, 6)
                // Clear the rounded screen corners: the title clipped at the top and the last
                // value at the bottom.
                .padding(.top, 24)
                .padding(.bottom, 32)
        }
    }

    private var sessionSummaryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            WatchMetricCaption(label: "Session summary", metric: .sets)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .alwaysOnSecondaryChrome(isLuminanceReduced)

            SessionMetricRow(label: "Sets", metric: .sets, value: "\(session.setCount)", isLarge: true)
            SessionMetricRow(
                label: "Distance",
                metric: .distance,
                value: SessionFormatters.distance(session.totalDistanceM),
                isLarge: true
            )
            SessionMetricRow(
                label: "Duration",
                metric: .duration,
                value: SessionFormatters.elapsed(session.elapsed),
                isLarge: true
            )
            SessionMetricRow(
                label: "Riding time",
                metric: .duration,
                value: SessionFormatters.segmentDuration(totalRidingDuration),
                isLarge: true
            )
            SessionMetricRow(
                label: "Inactive time",
                metric: .inactive,
                value: SessionFormatters.segmentDuration(totalInactiveDuration),
                isLarge: true
            )
            SessionMetricRow(
                label: "Calories",
                metric: .energy,
                value: session.totalEnergyKilocalories.map { SessionFormatters.calories($0) } ?? "--",
                isLarge: true
            )
            SessionMetricRow(
                label: "Active calories",
                metric: .energy,
                value: session.activeEnergyKilocalories.map { SessionFormatters.calories($0) } ?? "--",
                isLarge: true
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func statusLine(primary: LocalizedStringKey, color: Color, icon: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(primary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
            if session.isUnsure {
                Text("Unsure")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .alwaysOnSecondaryChrome(isLuminanceReduced)
    }

    private var heartRateRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let hr = session.lastHeartRate {
                Text(String(format: "%.0f", hr))
                    .font(.system(.title3, design: .rounded).bold())
                    .monospacedDigit()
            } else {
                Text("- BPM")
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "heart.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heartRateAccessibilityLabel)
        .alwaysOnSupportingMetric(isLuminanceReduced)
    }

    private var heartRateAccessibilityLabel: String {
        if let hr = session.lastHeartRate {
            return String(format: String(localized: "Heart rate %@ beats per minute"), String(format: "%.0f", hr))
        }
        return String(localized: "Heart rate unavailable")
    }
}
