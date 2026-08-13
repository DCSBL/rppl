# Phase 3 — Auto-detection roadmap

Library UML (Assumer filter / holds / rules): [../RpplCore/DESIGN.md](../RpplCore/DESIGN.md). System assumption sequence: [DESIGN.md](DESIGN.md).

## Goal

Propose segment labels from GPS speed + Ultra water submersion (+ weak CMMotionActivity). Labels stay opaque strings (`waiting`, `riding`, `swimming`, `walking`, …). Manual labeling and Action Button integration are removed; Assumer is the live writer.

## Assumption stream (live now)

During a Watch session:

| Stream | Source | File |
|--------|--------|------|
| Auto assumptions | `SegmentAssumer` transitions | `assumptions.jsonl` |
| Legacy manual labels | Older builds only | `labels.jsonl` (empty on new sessions) |

- Assumer starts with `waiting` + `reason=session_start`.
- Writes **only on code change** (no heartbeats).
- Each `AssumptionEvent` has a `reason` string with rule id + speeds in **km/h**.
- Watch UI: assumed code primary.
- Phone: list assumptions; Share JSON includes `assumptions` array.

Pure FSM: `RpplCore` (`SegmentAssumer`, `AssumptionThresholds`, `SpeedUnits`). Covered by `swift test`.

## ASSUMPTION thresholds (v0, km/h)

| Constant | Value | Notes |
|----------|-------|-------|
| Ride enter | ≥15 km/h × 2.0 s | Below typical cable >22; above walk/swim ceiling 10 |
| Swim (Ultra) | `submerged` AND ≤10 km/h (or nil speed) | No speed-only swim |
| Failed start | Ride age <5 s, ≤4 km/h, not submerged → `waiting` | |
| Long stop | Ride age ≥5 s, ≤4 km/h × 3 s, not submerged → `waiting` | End-of-run without fall |
| Walk | activity `walking` OR 2–10 km/h × 3 s | |
| Wait settle | ≤1.5 km/h × 5 s, activity ≠ walking | |
| GPS accuracy gate | >25 m skips speed transitions | Water→swim still OK |

Non-Ultra auto-swim deferred. Knots/mph later for display only.

## Input

iPhone Share export is pretty-printed `SessionTransferPackage` JSON (`manifest`, `labels`, `assumptions`, `locations`, plus motion/health when present).

- `LocationSample` / `GPSSnapshot.speed` — meters per second (nil when invalid).
- `LabelEvent` — legacy manual events (may be empty).
- `AssumptionEvent` — auto proposal + `reason`.
- Streams detail: [DataCollection.md](DataCollection.md). Hypotheses: [Ideas.md](Ideas.md).

## Order

```mermaid
flowchart LR
  collect[Phase2 collect sensors]
  assume[Live Assumer assumptions]
  docs[Docs idea book plus Phase3 plan]
  viz[Mac timeline viz]
  core[Core rule detector plus tests]
  live[Watch assumed face plus optional override]
  collect --> docs
  docs --> assume
  assume --> viz
  viz --> core
  core --> live
```

**Done this slice:** Core Assumer + live Watch writer + phone list/export. Assumed code is primary Watch UI.

**Next:** Mac timeline viz with assumed lane and threshold scrubbers. Then tighten constants / optional live override UX.

## Step A — Mac timeline viz (next code)

New macOS app/target in this repo (or SPM tool + SwiftUI Mac).

- Open exported session JSON or dropped session folder.
- Timeline: speed vs time, **assumed** markers (plus legacy manual markers when present), map track.
- Editable threshold scrubbers.
- Keep chart/data-prep separable for Core / iOS reuse.

## Step B — Synth / real fixtures

- Synth ticks already in `RpplCoreTests` (`SegmentAssumerTests`).
- **Real exports:** drop into `Exports/` (gitignored). Do not commit private park GPS without consent.

## Step C — Core detector

`SegmentAssumer` shipped as v0. Expand fixtures as park days land. Opaque string codes only.

## Step D — Live Watch (shipped)

Feed Assumer from live GPS + water-edge ticks. Assumed code on face is the primary Watch label. Optional “override wins / fewer presses” UX still later.

## Non-goals (Phase 3)

- Park profiles / dock geofence hardcoding ([Ideas.md](Ideas.md) Deferred)
- Trick detection / full taxonomy
- CloudKit
- Phone label editor
- Manual / Action Button labeling
- ML models
- Non-Ultra speed-only auto-`swimming`
