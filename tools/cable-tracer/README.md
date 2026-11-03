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

## Tower labels from the app

Tracing a whole cable takes a while; judging the detector's tower guesses takes seconds, and the
verdicts are exactly the examples the tower net lacks. The Rppl app collects them behind the Debug
toggle "Review towers" (`Rppl/Parks/TowerReview/`), on the phone where the satellite imagery is:

- A request file (`tower-review-request.json`, see `RpplCore/.../CableDetection/TowerReview.swift`)
  says which parks to do; without one the app lists every park without a traced cable. The
  request for a round is kept under `tools/cable-tracer/requests/`.
- Per park, "Find towers" takes the same 600 m close-up as the detector and shows the guesses one
  by one under a crosshair: the most confident first, then always the nearest remaining one
  (threshold lowered to 30% so the doubtful ones come up). Pan the tower under the crosshair and
  press **Tower** (saved where the crosshair is), or **No tower** / **Unsure** (saved where the
  detector looked). "Add tower here" marks a tower the detector missed.
  Rings: orange = current guess, green = tower, red = no tower, grey = unsure; tap a ring to remove.
- "Share results" hands over `tower-labels.json` with every verdict on the phone. Put it at
  `tools/cable-tracer/tower-labels.json` (it is a superset of earlier shares from the same phone;
  merge by park id when several phones contribute; add a trailing newline for pre-commit) and
  commit it like park data; the exporter finds it from the parks folder, `--labels <file>` points
  elsewhere. Files from before the rename (`mast-labels.json`, verdict `mast`) still load.
- "Export training set" and `--export-training-set` include the labelled parks, with a 600 m
  close-up around the towers, so `detect/` trains on them without a traced cable.

## Automatic proposal

`detect/` holds the Python prototype of the automatic step (water, floating objects, a tower
detector and a convex loop fit with a plausibility score) and the training of the tower net. The
winner is ported to `RpplCore/Sources/RpplCore/CableDetection` and runs in the app behind the
Debug toggle "Detect cable"; see `detect/README.md` and `detect/RESULTS.md`.

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
