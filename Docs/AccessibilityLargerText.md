# Larger Text plan

Status: planned, not started. Reduce Motion, Increased Contrast and Differentiate Without Color are done (see [Design language](DesignLanguage.md#accessibility)).

Goal: the phone app and Watch stay usable at the largest Dynamic Type sizes, so Rppl can claim "Larger Text" on its App Store accessibility label. Riding screens on the Watch are the priority: a rider glances at them mid-set.

Expect layouts to break at accessibility sizes. Do this as its own work, screen by screen, not as a drive-by change.

## 1. Fixed font sizes

These do not scale with Dynamic Type today. Move each to a text style or `@ScaledMetric`, and cap where a fixed container makes scaling unsafe.

| File | Size | Use |
|------|------|-----|
| `RpplWatch/Views/SessionControlsPage.swift` | 28 pt | Controls glyph |
| `RpplWatch/Views/SessionSetUIPage.swift` | 9 pt | Riding view caption |
| `Rppl/Logbook/SessionMapView.swift` | 9 pt | Start/End annotation glyph (inside a fixed 20 pt circle) |
| `Rppl/Parks/ParkDetailView.swift` | 9 pt | Map pin glyph (inside a fixed circle) |
| `Rppl/Parks/ParksView.swift` | 15 pt (x2) | Map style / recenter buttons (fixed 34 pt frame) |
| `Rppl/Parks/WindRoseView.swift` | 6 pt | Compass letters |
| `Rppl/Parks/Editor/ParkEditorView.swift` | 44 pt | Decorative icon |
| `Rppl/Parks/Editor/CableTraceView.swift` | 8 pt | Start flag in the point marker |

Rule of thumb: glyphs inside a fixed-size circle or pin scale with `@ScaledMetric` on both glyph and container; text never goes below `.caption2`.

## 2. Layout audit

Check each at `.accessibility3` and `.accessibility5` (previews in `DesignGallery.swift`), light and dark:

- `.lineLimit(1)` and `.fixedSize` call sites (56 hits for fixed sizes, line limits and fixed size across 23 files): decide per call site whether truncating is acceptable or the row should wrap.
- `MetricValue` shrinks to 60 %; confirm the stacked layout takes over before the value becomes unreadable.
- `InfoTileGrid` already goes to one column at accessibility sizes. Check other grids and `HStack` rows that should switch to `VStack` (use `ViewThatFits` or `dynamicTypeSize.isAccessibilitySize`).
- Logbook list rows, park cards, chips (`ParkChip`, `HighlightChip`), `SetFlagBadge` wrapping.
- Charts: axis label count and legend wrapping.
- Widgets (`RpplWidgets`): they scale with the system size; check each family.
- Watch: the riding view must still fit without scrolling on the smallest supported case, or the primary metrics (time, laps, speed) must stay on the first screen with the rest below.

## 3. Verification

- Add Dynamic Type variants to the design gallery previews.
- Add an XCUITest launch argument pass (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`) over the main tabs once layouts hold. UI tests are not in the push gate (see AGENTS.md), so run them as a separate workflow.
- Manual pass on a real Watch at the largest size before claiming the label.

## Out of scope

- Redesigning tiles for a new layout. Prefer wrapping and stacking over new components.
