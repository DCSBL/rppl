# Larger Text plan

Status: in progress, screen by screen. Reduce Motion, Increased Contrast and Differentiate Without Color are done (see [Design language](DesignLanguage.md#accessibility)).

Goal: the phone app and Watch stay usable at the largest Dynamic Type sizes, so Rppl can claim "Larger Text" on its App Store accessibility label. Riding screens on the Watch are the priority: a rider glances at them mid-set.

Expect layouts to break at accessibility sizes. Do this as its own work, screen by screen, not as a drive-by change.

## 1. Fixed font sizes

Done: every font is a text style or an `@ScaledMetric` (the Watch controls glyph is capped at 40 pt, because its tile fills the page and cannot grow with it). The manual session count field and the sync status dots scale too.

Rule of thumb: glyphs inside a fixed-size circle or pin scale with `@ScaledMetric` on both glyph and container; text never goes below `.caption2`.

## 1a. Shared components

Done, so every tile and card gets them:

- `StatChip` wraps its value at accessibility sizes instead of staying on one line (`NW · 12 km/h` is wider than a tile there).
- `MetricValue` puts the unit under the number at accessibility sizes; one line shrunk to 60 % is unreadable there. Its `.total` size stops at 56 pt.
- `TileHeader` gets two lines at accessibility sizes.
- `FlowLayout` wraps a chip that is wider than the row inside it.
- `rpplPopoverContent(width:maxWidth:)`: an explanation popover is a scrolling sheet at accessibility sizes.
- `AdaptiveStack`: an `HStack` that is a `VStack` at accessibility sizes (`dynamicTypeSize.isAccessibilitySize`). Use it for every row of two or more texts; `ViewThatFits` where the content is small and has a natural shorter form.

Rules for the screen work: content never truncates (`lineLimit(1)` plus `minimumScaleFactor` only on decoration and the Watch hero); a row becomes a column; decoration (gauges, timeline bars, chart axes) may go from `.accessibility3` up while its text stays; no Dynamic Type cap in the app, only in the widgets, whose frame is fixed.

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
