# Data collection (Phase 2+)

Alpha collector for cable-park wakeboarding. Tracking runs only on Apple Watch.

## Detection codes (auto)

Opaque strings written to `detections.jsonl`:

- `inactive` — not riding (session starts here)
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
| Water temperature | sparse; Ultra while submerged (~first sample of a bout, then ~15 s) | `water-000.jsonl` |
| Detections | on transitions / revisions | `detections.jsonl` |
| Manifest | once | `manifest.json` |

Schema **v3**: detections replace labels/assumptions. Legacy `assumptions.jsonl` migrates to detections on open; transfer packages may still carry `assumptions` / `labels` keys (decoded into detections / discarded).

Schema **v4**: detection code `paused` rewritten to `inactive` on read/append (one-time per session package).

## Derived stats (not a stream)

Ride distance, duration, ride count, riding/inactive ratio, calories, sustained/trimmed speeds, session water-temperature mean, and record highlights are **computed on demand** from detections + GPS + health + water — not written to disk. Watch shows live ride count / meters / speed during recording (and water temp on the inactive overview); iPhone session detail shows summary + per-ride list via `SessionStatsBuilder` in RpplCore.

Water temperature is a session metric (mean of persisted samples). Ultra sets `manifest.waterTemperatureAvailable`; the UI hides the tile on unsupported watches, shows `- C` until the first sample, then the average. Submersion is when the Watch can measure; the value stays relevant while riding.

## HealthKit policy

`HKWorkoutSession` + builder run for sensors/runtime and **save to Health** on stop (`finishWorkout()`). Starting a session requires **share** authorization for Workouts. The HK session **stays running** for the full park day. Detection `inactive` does **not** call `session.pause()` (heart rate stays continuous). Instead: **`beginNewActivity`** on each confident `riding` and `inactive` (same `waterSports` type). Fitness Intervals show numbered rows (kcal / time / HR) with **no rest labels**. Disable active-energy + paddle-distance collection while docked. Heart rate and basal energy keep collecting. Do **not** emit `motionPaused` for detection rest (purple duration).

**Fitness summary distance / average speed (DCS-44):** Fitness tiles are activity-type templates. Cycling shows ride distance + average speed from `distanceCycling` / `cyclingSpeed`. Rppl stays on `HKWorkoutActivityType.waterSports` (wakeboarding / water skiing). At `finishWorkout()` Watch writes:

- `HKQuantityTypeIdentifier.distancePaddleSports` (ride-gated meters; already shipped)
- `HKQuantityTypeIdentifier.paddleSportsSpeed` (discrete m/s = ride meters / riding duration)
- `HKMetadataKeyAverageSpeed` (same m/s; Apple documents this for skiing segments — may or may not surface on water-sports)

Paddle distance may still be hidden on a water-sports summary even when samples exist. Do **not** dual-write walking+running or swimming distance on the live Watch path (pollutes those Health charts). Debug inject can A/B: paddle (production), walking+running, swimming, or `paddleSports` activity type. Confirm on device which encoding Fitness plots. JSONL remains the source for in-app stats.

**Product Pause** (Watch Pause button) is separate from detection `inactive`: it freezes the session clock, flushes then stops GPS/motion, **pauses the HK session**, and writes `inactive` detection lines with `detectorId` `product_pause` / `product_resume` (intentional sensor gap). Resume stays `inactive` until live detection re-proves `riding`.

**Rides vs laps in Health:** Fitness intervals are detection **rides and dock waits**, not cable-park **loop laps** (`LapRideTracker`). Loop laps stay in-app / export only. Never emit `HKWorkoutEvent.lap` unless Fitness shows a lap count we can fill. Rest/transition **word labels** are not possible on `waterSports`.

If Health denies workout sharing (common after tapping Don’t Allow, or flaky on Simulator), the Watch continues in **sensors-only** mode: GPS + detections still record; HR/energy from the builder are skipped.

Water temperature: sparse `HKQuantityTypeIdentifier.waterTemperature` samples are added to the finished workout after `endCollection` (same window as ride distance), when Ultra recorded any. They appear in Health as samples on that workout. Fitness / Workout summary tiles are Apple-controlled and typically show water temp for swimming/dive, not `.waterSports` — Rppl does not change activity type for temperature. JSONL remains the source for in-app stats.

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
