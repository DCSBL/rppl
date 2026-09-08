import SwiftUI
import RpplCore

/// Appearance switcher that sits directly under the session map.
///
/// Each look needs its own controls (which set to solo, where the replay head is), so the
/// picker and those controls live in one strip instead of being scattered over the map.
struct SessionMapAppearanceControls: View {
    @Binding var appearance: SessionMapAppearance
    @Binding var soloSetIndex: Int?
    @Binding var replayProgress: Double
    @Binding var isReplaying: Bool
    @Binding var orbits: Bool

    let setTracks: [SessionSetTrack]
    let timeline: TrackPlaybackTimeline
    let speedScale: TrackSpeedScale?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            appearanceChips

            if isLoading, appearance.needsSetTracks, setTracks.isEmpty {
                Text("Loading GPS…")
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
            } else {
                contextControls
            }

            Text(appearance.caption)
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .logbookCardChrome()
    }

    // MARK: - Picker

    private var appearanceChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SessionMapAppearance.allCases) { option in
                    Button {
                        select(option)
                    } label: {
                        chipLabel(option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(appearance == option ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chipLabel(_ option: SessionMapAppearance) -> some View {
        let selected = appearance == option
        return HStack(spacing: 5) {
            Image(systemName: option.symbol)
                .font(.caption2.weight(.bold))
            Text(option.title)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(selected ? Color.white : Color.rpplText)
        .background(selected ? Color.rpplAccent : Color.rpplFill, in: Capsule())
    }

    // MARK: - Per-appearance controls

    @ViewBuilder
    private var contextControls: some View {
        switch appearance {
        case .flat:
            EmptyView()
        case .sets:
            setRampLegend
        case .flyover:
            VStack(alignment: .leading, spacing: 10) {
                setRampLegend
                Toggle("Auto-orbit camera", isOn: $orbits)
                    .font(.subheadline)
                    .tint(Color.rpplAccent)
            }
        case .speed:
            speedLegend
        case .solo:
            soloPicker
        case .replay:
            replayControls
        }
    }

    private var setRampLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule()
                .fill(SessionTrackPalette.setGradient(count: max(setTracks.count, 2)))
                .frame(height: 8)
            HStack {
                Text("First set")
                Spacer()
                Text("Last set")
            }
            .font(.caption2)
            .foregroundStyle(Color.rpplMuted)
        }
    }

    private var speedLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule()
                .fill(SessionTrackPalette.speedGradient(bandCount: TrackSpeedBands.defaultBandCount))
                .frame(height: 8)
            HStack {
                Text(speedLabel(speedScale?.lowKmh))
                Spacer()
                Text(speedLabel(speedScale?.highKmh))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Color.rpplMuted)
        }
    }

    private var soloPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    stepSolo(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.plain)
                .disabled(setTracks.isEmpty)
                .accessibilityLabel("Previous set")

                Text(soloTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.rpplText)
                    .frame(minWidth: 120, alignment: .leading)

                Spacer()

                Button {
                    stepSolo(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.plain)
                .disabled(setTracks.isEmpty)
                .accessibilityLabel("Next set")
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(setTracks.enumerated()), id: \.offset) { item in
                        let selected = soloSetIndex == item.element.setIndex
                        Button {
                            soloSetIndex = item.element.setIndex
                        } label: {
                            Text(verbatim: "\(item.element.setNumber)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .frame(minWidth: 26)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                                .foregroundStyle(selected ? Color.white : Color.rpplText)
                                .background(
                                    selected
                                        ? SessionTrackPalette.setColor(
                                            position: item.offset,
                                            of: setTracks.count
                                        )
                                        : Color.rpplFill,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var replayControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    isReplaying.toggle()
                } label: {
                    Image(systemName: isReplaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(Color.rpplAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(timeline.isEmpty)
                .accessibilityLabel(
                    isReplaying
                        ? String(localized: "Pause replay")
                        : String(localized: "Play replay")
                )

                Slider(value: $replayProgress, in: 0...1)
                    .disabled(timeline.isEmpty)
                    .accessibilityLabel("Replay position")
            }

            Text(replayReadout)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.rpplMuted)
        }
    }

    // MARK: - Labels

    private var soloTitle: String {
        guard let index = soloSetIndex,
              let position = setTracks.firstIndex(where: { $0.setIndex == index })
        else {
            return String(localized: "All sets")
        }
        let track = setTracks[position]
        return String(localized: "Set \(track.setNumber) of \(setTracks.count)")
    }

    private var replayReadout: String {
        guard let point = timeline.point(atProgress: replayProgress) else {
            return String(localized: "No GPS track")
        }
        let elapsed = LogbookFormatting.duration(point.ridingOffset)
        let total = LogbookFormatting.duration(timeline.totalRidingDuration)
        let speed = point.speedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "-"
        return String(localized: "Set \(point.setNumber) · \(elapsed) / \(total) · \(speed)")
    }

    private func speedLabel(_ kmh: Double?) -> String {
        guard let kmh else { return "-" }
        return LogbookFormatting.speedKilometersPerHour(kmh)
    }

    // MARK: - Actions

    private func select(_ option: SessionMapAppearance) {
        guard appearance != option else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            appearance = option
        }
    }

    private func stepSolo(by delta: Int) {
        guard !setTracks.isEmpty else { return }
        let current = soloSetIndex
            .flatMap { index in setTracks.firstIndex { $0.setIndex == index } } ?? 0
        let next = (current + delta + setTracks.count) % setTracks.count
        soloSetIndex = setTracks[next].setIndex
    }
}
