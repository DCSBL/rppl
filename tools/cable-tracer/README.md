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
  A 600 m close-up (`-detail`, 2048 px, 0.29 m/px) around the traced cables is written too, since
  the cable itself is invisible at the overview scale. This is the input for the route-proposal step (phase 2). The same export runs headless with
  `--export-training-set <dir>` (add `--all-parks` to include untraced parks, `--parks <dir>` for
  another parks folder).

## iOS simulator build

`CableTracerApp/CableTracerApp.xcodeproj` wraps the same editor as an iOS app, for a Mac where the
agent has no screen-recording permission: the simulator can be driven and screenshotted with
`simctl`. The simulator reads the host file system, so point it at the repo's parks folder:

```bash
xcodebuild -project CableTracerApp/CableTracerApp.xcodeproj -scheme CableTracerApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -derivedDataPath /tmp/ct-dd build
xcrun simctl launch booted nl.dcsbl.rppl.cable-tracer --parks "$PWD/../../RpplCore/Sources/RpplCore/Resources/Parks"
```

Saving writes straight into that folder. "Export training set" writes to the app's Documents folder
(`xcrun simctl get_app_container booted nl.dcsbl.rppl.cable-tracer data`).

## Layout

- `Sources/CableTracerCore`: pure logic, tested, builds on Linux.
- `Sources/CableTracerUI`: SwiftUI + MapKit editor, macOS and iOS.
- `Sources/CableTracer`: macOS executable (app + headless export).
- `CableTracerApp/`: iOS app project around `CableTracerUI`.
