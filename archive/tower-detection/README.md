# Tower detection (parked 2026-11-09)

Experiment to find the cable towers (and from them the cable loop) on satellite imagery, with a
small CNN, and to collect tower labels on the phone as training data. **Parked, not in any build**:
nothing under `archive/` is part of the Xcode project, the `RpplCore` package or CI. The last commit
that still had it live is `133417d` (PR #634); `git show 133417d:<old path>` shows every file in
place.

## Where things are

| Archived path | Was | What it is |
|---|---|---|
| `app/TowerReview/` | `Rppl/Parks/TowerReview/` | Debug "Review towers" screens: judge guesses on the map, "Share results" zip |
| `app/CableDetectionRunner.swift` | `Rppl/Parks/Editor/` | MapKit snapshots (600 m, close-ups) and the detector call |
| `app-wiring.patch` | `Rppl/App/DebugLogView.swift`, `Rppl/Settings/AppSettings.swift`, `Rppl/Parks/Editor/CableTraceView.swift` | The edits that connected it to the app: four debug keys, two toggles, the "Detect cable" button, proposal controls and legend rows |
| `core/Sources/CableDetection/` | `RpplCore/Sources/RpplCore/CableDetection/` | Swift port: water segmenter, bright blobs, TowerNet, close-up check, wheel finder, loop fitter |
| `core/Resources/*.weights` | `RpplCore/Sources/RpplCore/Resources/` | TowerNet, TowerCloseupCheck, TowerWheelFinder weights |
| `core/Tests/` | `RpplCore/Tests/RpplCoreTests/` | Their tests (incl. `DetectionImageFrameTests`) |
| `cable-tracer/` | `tools/cable-tracer/` | The macOS/iOS cable tracer tool, Python prototype and training in `detect/`, `RESULTS.md`, review requests, `tower-labels.json` |

Not archived: the cable routes that were filled into 17 parks from confirmed towers (PR #634). They
are normal park YAML in `RpplCore/Sources/RpplCore/Resources/Parks/` and stay. Direction was assumed
counter-clockwise, so they may need a check.

## Results to know before picking this up again

- Tower net: 4-conv CNN on 64 px patches, 17,745 parameters, leave-parks-out AUC about 0.93-0.96.
- Loop proposal vs hand trace on 35 traced loops: median IoU 0.75 (22 of 35 at 0.7 or better),
  median bend error about 21 m. Details and per-park table: `cable-tracer/detect/RESULTS.md`.
- Hard cases: glint, brown water with few obstacles, two loops in one lake, beaches full of boats.
- Labels: 15 parks labelled on 2026-11-03, more in the 2026-11-04 and 2026-11-05 zips (see the project
  files archive below). More labels helped on parks like the labelled ones, not yet on loops.
- Wheel finder: guesses landed a median of 5.9 m from the wheel; the finder brought that to 0.7 m
  (81% within 2 m).
- Not reachable with labels alone: "almost no errors". The plan was "propose, user confirms".
- The cloud session has no Swift compiler, so the Swift port was only ever compiled by CI. Expect to
  fix small things after moving it back.

## Rebuilding it into the app

From the repo root, on a fresh branch off `main`:

```bash
archive/tower-detection/restore.sh
```

That reverses `app-wiring.patch` and moves every folder back to its old path (`git mv`, so
history follows). Then:

1. Add `tools/cable-tracer/.build/` to `.gitignore` again.
2. Build the `Rppl` scheme and run `cd RpplCore && swift test`. The Swift port was only ever compiled
   by CI (the cloud session has no Swift compiler), and `main` may have moved since, so expect small
   fixes. `RpplCore` needs no `Package.swift` change: the weights are plain resources under `Resources/`.
3. Delete the now empty `archive/tower-detection/` leftovers (README, patch, script) if you no longer
   want them.
4. Debug toggles come back default off: "Detect cable" (adds the button to the trace map) and
   "Review towers" (the labelling screens; the close-up check and wheel finder keys default on).

To train again, see `cable-tracer/README.md` and `cable-tracer/detect/README.md`: merge new labels
into `cable-tracer/tower-labels.json`, build a set with `detect/phone_set.py <zip> <out>`, train with
`detect/train_round.py` (JAX, runs in the cloud), compare against `detect/RESULTS.md`, then export
weights with `export_towernet.py`, `export_closeupcheck.py` and `export_wheelfind.py` into
`RpplCore/Sources/RpplCore/Resources/`. Review zips and the older training sets are in the project
files (below). Keep `core/Tests` reference logits in step with any new weights.

## Files outside the repo

Raw material lives in the project files under `archive/tower-detection/`: plans, proposal results,
label sets, the review zips with the satellite photos (about 490 MB, too big for git), the training set and
the park overview/mask images.
