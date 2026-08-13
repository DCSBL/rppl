# Idea book

Short backlog for later phases. Not a design doc. Do not implement items marked **Deferred** until product decision unlocks them.

## Deferred

- **Park profiles** — Per-park metadata: orientation, dock/start location, obstacles, cable layout. Used later to geofence “waiting” / failed starts near the dock, hardcode or learn a start point, and give detectors park-specific priors. Out of scope until after detector v1. Do not build profile files, editors, or geofence hardcoding yet.
- **Non-Ultra auto-swim** — Speed-only fall→`swimming` without `CMWaterSubmersionManager`. v0 requires Ultra `submerged`.
- **Knots / mph display** — Thresholds authored in km/h; convert at GPS edge to m/s. Extra unit labels later for Mac viz only.

## Detection hypotheses (ride/pause MVP shipped)

GPS samples store m/s; detection thresholds + `reason` strings use **km/h**. Stream: `detections.jsonl` only (manual labels removed).

| Signal | Code | Notes |
|--------|------|-------|
| ≥15 km/h sustained 2 s while `paused` | `riding` | Mid-session start OK |
| ≤4 km/h × 3 s usable while `riding` | `paused` | End of run |
| Unusable GPS × 3 s while `riding` | `unsure` | Fall flake; not pause |
| Unsure &lt; 3 min + speed returns high | `riding` (supersede) | Same ride lookback |
| Unsure ≥ 3 min | `paused` | Next enter = new ride |
| Water / motion activity | (logged only) | Future fall / walk detectors |

## Other notes

- Temporary wrong detections OK if `reason` makes tuning obvious.
- Trick detection, ML models, CloudKit, and phone label editing stay out until Phase 4 / explicit ask.
- Park profiles / dock geofence still Deferred above.
