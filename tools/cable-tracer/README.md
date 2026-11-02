# Cable Tracer

Internal macOS tool to trace and review cable routes on satellite imagery. Not part of the app
and not shipped; it edits the same park YAML files the app bundles
(`RpplCore/Sources/RpplCore/Resources/Parks`), so a reviewed route goes in as a normal park PR.

```bash
cd tools/cable-tracer
swift run cable-tracer          # opens the repo's parks folder automatically
swift test                      # CableTracerCore only; also runs on Linux
swift run cable-tracer --export-training-set /tmp/cable-training   # headless export, see below
```

## What it does

- Lists every park, with a `traced/total` cable badge and a filter for parks that still need a route.
- Shows the park on Apple Maps satellite imagery with the cables drawn on top. The selected cable's
  points are draggable; "Add points" appends points by clicking.
- "Add full size" / "Add 2.0" drops a template of the median shape learned from the already traced
  parks (`CablePrior`), rotatable in 5° steps, so a new park starts from a plausible loop instead of
  a blank map.
- Plausibility checks (`CableLint`): loop length and width, 2.0 length, sharp turns, tiny segments,
  points far from the park, self-crossing loops, a `length_m` that disagrees with the trace, a
  direction that does not match the shape.
- Save appends a history line and writes the YAML through RpplCore's encoder, like every other
  park edit.
- Reference CSVs (`park,lat,lon,…`, e.g. tower positions fitted from GPS tracks) can be overlaid
  as purple markers.
- "Export training set" writes `training-set.json` (every cable in local metres with shape
  statistics) plus a 1024 px satellite snapshot and a cable mask per park, at a fixed 1.37 m/px.
  This is the input for the route-proposal step (phase 2). The same export runs headless with
  `--export-training-set <dir>` (add `--all-parks` to include untraced parks, `--parks <dir>` for
  another parks folder).

## Layout

- `Sources/CableTracerCore`: pure logic, tested, builds on Linux.
- `Sources/CableTracer`: SwiftUI + MapKit app (macOS only).
