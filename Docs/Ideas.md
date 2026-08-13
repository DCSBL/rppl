# Idea book

Short backlog for later phases. Not a design doc. Do not implement items marked **Deferred** until product decision unlocks them.

## Deferred

- **Park profiles** — Per-park metadata: orientation, dock/start location, obstacles, cable layout. Used later to geofence “waiting” / failed starts near the dock, hardcode or learn a start point, and give detectors park-specific priors. Out of scope until after detector v1. Do not build profile files, editors, or geofence hardcoding yet.
- **Non-Ultra auto-swim** — Speed-only fall→`swimming` without `CMWaterSubmersionManager`. v0 requires Ultra `submerged`.
- **Knots / mph display** — Thresholds authored in km/h; convert at GPS edge to m/s. Extra unit labels later for Mac viz only.
- **Manual / Action Button labeling** — Removed from alpha. Optional live override UX later if product asks.

## Detection hypotheses (v0 shipped in Core)

Assumer writes opaque segment codes to `assumptions.jsonl`. Legacy packages may still carry `labels.jsonl`. GPS samples store m/s; Assumer thresholds + `reason` strings use **km/h**.

| Signal | Proposed label | v0 notes |
|--------|----------------|----------|
| ≥15 km/h sustained 2 s while `waiting`/`swimming` | `riding` | Below typical cable >22; gap above walk/swim ceiling 10 |
| Ride age <5 s, ≤4 km/h, not submerged | `waiting` | Failed start |
| Ride age ≥5 s, ≤4 km/h × 3 s, not submerged | `waiting` | Long stop / end-of-run without fall |
| `submerged` + ≤10 km/h (or nil speed) while `riding` | `swimming` | Ultra only; no speed-only swim |
| Speed returns ≥15 km/h × 2 s while `swimming` | `riding` | Water start; wet OK |
| `notSubmerged` + (`walking` activity OR 2–10 km/h × 3 s) | `walking` | Weak; either signal |
| ≤1.5 km/h × 5 s, activity ≠ walking while `walking` | `waiting` | Dock settle |
| Near start geo + stopped | `waiting` | Needs park profiles later |

## Other notes

- Temporary wrong auto-labels OK if `reason` makes tuning obvious.
- Optional live “override wins” UX later — not wired today.
- Trick detection, ML models, CloudKit, and phone label editing stay out until Phase 4 / explicit ask.
