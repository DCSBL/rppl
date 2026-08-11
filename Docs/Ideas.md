# Idea book

Short backlog for later phases. Not a design doc. Do not implement items marked **Deferred** until product decision unlocks them.

## Deferred

- **Park profiles** — Per-park metadata: orientation, dock/start location, obstacles, cable layout. Used later to geofence “waiting” / failed starts near the dock, hardcode or learn a start point, and give detectors park-specific priors. Out of scope until after detector v1. Do not build profile files, editors, or geofence hardcoding yet.

## Detection hypotheses

Coarse Action Button labels remain ground truth while tuning. Speed on GPS samples is m/s in files; hypotheses below use km/h for readability.

| Signal | Proposed label | Notes |
|--------|----------------|-------|
| ~0 → ≥20 km/h sustained a few seconds while `waiting` | `riding` | Start / pull-away |
| 0 → ~20 for ~3s → 0 | failed start | Stay or return `waiting`, or brief ride then swim; dock geofence later via park profiles |
| Speed → ~0 after ride | `swimming` (fall) | OK to over-mark swim |
| Same position + speed returns | water start | Revert temporary `swimming` → `riding`; temporary wrong label OK |
| Low speed + motion / GPS wander / screen activity | `walking` | Weak signal; validate in Mac viz before encoding |
| Near start geo + stopped | `waiting` | Needs park profiles later |

## Other notes

- Manual override on Watch must always win over auto-detect once live detection ships.
- Temporary wrong auto-labels (e.g. swim then water-start revert) are acceptable if correction is fast and logged.
- Trick detection, ML models, CloudKit, and phone label editing stay out of this backlog until Phase 4 / explicit ask.
