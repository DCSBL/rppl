# Data collection (Phase 2+)

Alpha collector for cable-park wakeboarding. Tracking runs only on Apple Watch.

## Detection codes (auto)

Opaque strings written to `detections.jsonl`:

- `paused` — not riding (session starts here)
- `riding` — wakeboard / waterski ride speed
- `unsure` — mid-ride GPS soft (Watch primary UI keeps last confident code)

Engine: `DetectionEngine` in RpplCore (filter → holds → detectors → lookback merger). Writes on transitions + lookback revisions only. Each line: `code`, `timestamp`, `reason` (km/h), `detectorId`, optional speed/accuracy/water/activity, optional `supersedesId`.

Manual Action Button labels are **removed**. Ultra Action Button may still **start** a session via Workout intent.

Schema / UML: [DESIGN.md](DESIGN.md) · Core: [../RpplCore/DESIGN.md](../RpplCore/DESIGN.md) · thresholds: [Phase3.md](Phase3.md).

## Streams

| Stream | Approx rate | File |
|--------|-------------|------|
| GPS | Core Location updates | `location-000.jsonl` |
| deviceMotion | ~25 Hz → framed zlib JSONL | `motion-000.jsonl.zlib` |
| HR / active energy (mirrored, not saved to Health) | workout builder | `health-000.jsonl` |
| Detections | on transitions / revisions | `detections.jsonl` |
| Manifest | once | `manifest.json` |

Schema **v3**: detections replace labels/assumptions. Legacy `assumptions.jsonl` migrates to detections on open; transfer packages may still carry `assumptions` / `labels` keys (decoded into detections / discarded).

## HealthKit policy

`HKWorkoutSession` + builder run for sensors/runtime. Starting a session requires **share** authorization for Workouts (even though we **do not call `finishWorkout()`**).

If Health denies workout sharing (common after tapping Don’t Allow, or flaky on Simulator), the Watch continues in **sensors-only** mode: GPS + detections still record; HR/energy from the builder are skipped.

## Action Button (Ultra)

Optional start only:

1. Settings › Action Button › **Workout**
2. App › **Rppl** (Cable Park)
3. Press starts the session when idle; press while recording is a **no-op**

Requires an active HealthKit workout path for Workout intent registration. Cycle Label is obsolete — see [Postmortems/ActionButtonCycleLabel.md](Postmortems/ActionButtonCycleLabel.md).

## Transfer

Phone may be away during the session. After **Stop session**, Watch queues a WC file transfer and **keeps checkpoints until the phone sends an ack**. Transfer failure must not delete Watch data. Transfer package includes `detections` (legacy `assumptions` accepted on decode).

## Export

On iPhone: open a session → **Export session JSON** (Share/AirDrop to Mac for manual analysis). Export includes `detections`.
