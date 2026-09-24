import SwiftUI
import RpplCore

/// Session map looks the rider can switch between under the map.
///
/// Kept as a picker rather than one chosen design: a park day stacks every set on the
/// same few hundred metres of water, and which encoding reads best depends on the day
/// (two long sets vs twenty short ones, standard basemap vs satellite).
enum SessionMapAppearance: String, CaseIterable, Identifiable {
    /// Today's look: one color, every set stroked flat on top of the last.
    case flat
    /// Per-set color ramp — cool early sets, warm late sets.
    case sets
    /// Track colored by GPS speed, relative to the session's own spread.
    case speed
    /// One set at full strength, the rest ghosted, with direction and finish markers.
    case solo
    /// Scrubbable / playable ride-back on a riding-only clock.
    case replay
    /// Pitched satellite with terrain.
    case flyover

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .flat: "Flat"
        case .sets: "Sets"
        case .speed: "Speed"
        case .solo: "Solo"
        case .replay: "Replay"
        case .flyover: "3D"
        }
    }

    var symbol: String {
        switch self {
        case .flat: "scribble"
        case .sets: "square.stack.3d.down.right"
        case .speed: "speedometer"
        case .solo: "scope"
        case .replay: "play.circle"
        case .flyover: "mountain.2"
        }
    }

    var caption: LocalizedStringKey {
        switch self {
        case .flat: "One color, every set stacked."
        case .sets: "Cool colors early in the day, warm late."
        case .speed: "Colored by GPS speed across this session."
        case .solo: "One set at a time, the rest ghosted."
        case .replay: "Scrub or play the ride back, dock time skipped."
        case .flyover: "Pitched satellite with terrain."
        }
    }

    /// Needs per-set GPS samples, so it falls back to `flat` until the track loads.
    var needsSetTracks: Bool { self != .flat }

    /// Whether the picker should expose this look on a single-set map (set cards).
    var suitsSingleSet: Bool {
        switch self {
        case .flat, .sets, .speed: true
        case .solo, .replay, .flyover: false
        }
    }
}

/// Everything a `SessionMapView` needs beyond the raw polylines to draw an appearance.
struct SessionMapRendering {
    var appearance: SessionMapAppearance = .flat
    /// Per-set GPS paired with set numbers. Empty falls back to `flat`.
    var setTracks: [SessionSetTrack] = []
    var timeline: TrackPlaybackTimeline = .empty
    /// Shared across the session map and the set cards so colors mean the same thing.
    var speedScale: TrackSpeedScale?
    /// `SessionSetTrack.setIndex` to isolate in `solo`; nil shows every set.
    var soloSetIndex: Int?
    var replayProgress: Double = 1
    /// Slow camera orbit in `flyover` (non-interactive maps only).
    var orbits: Bool = false

    static let flat = SessionMapRendering()

    static func singleSet(appearance: SessionMapAppearance, speedScale: TrackSpeedScale?) -> SessionMapRendering {
        SessionMapRendering(
            appearance: appearance.suitsSingleSet ? appearance : .flat,
            speedScale: speedScale
        )
    }
}
