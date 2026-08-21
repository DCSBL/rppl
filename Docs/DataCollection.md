# Data collection (Phase 2+)

Alpha collector for cable-park wakeboarding. Tracking runs only on Apple Watch.

## Detection codes (auto)

Opaque strings written to `detections.jsonl`:

- `inactive` — not riding (session starts here)
- `riding` — wakeboard / waterski ride speed
- `unsure` — mid-ride GPS soft (Watch primary UI keeps last confident code)

Engine: `DetectionEngine` in RpplCore (filter → holds → detectors → lookback merger). Writes on transitions + lookback revisions only. Each line: `code`, `timestamp`, `reason` (km/h), `detectorId`, optional speed/accuracy/water/activity, optional `supersedesId`.

Manual Action Button labels are **removed**. Ultra Action Button may still **start** a session via Workout intent.

Schema / UML: [DESIGN.md](DESIGN.md) · Core: [../RpplCore/DESIGN.md](../RpplCore/DESIGN.md) · storage: [SessionStorage.md](SessionStorage.md) · thresholds: [Phase3.md](Phase3.md).

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

## Derived stats

Ride distance, duration, ride count, riding/inactive ratio, calories, sustained/trimmed speeds, session water-temperature mean, and record highlights come from `SessionStatsBuilder` in RpplCore (detections + GPS + health + water).

After Stop / import, Core writes `derived/view.json` (`SessionAnalyzer.version` + stats + `MapTrackFrame`). Phone logbook list and detail basics read that file; GPS polyline loads after detail appear. Rebuild when analyzer version is stale or sidecar missing. Layout: [SessionStorage.md](SessionStorage.md).

Watch live UI still uses in-memory trackers while recording. Past sessions stay phone-only.

Water temperature is a session metric (mean of persisted samples). Ultra sets `manifest.waterTemperatureAvailable`; the UI hides the tile on unsupported watches, shows `- C` until the first sample, then the average. Submersion is when the Watch can measure; the value stays relevant while riding.

## HealthKit policy

`HKWorkoutSession` + builder run for sensors/runtime and **save to Health** on stop (`finishWorkout()`). Starting a session requires **share** authorization for Workouts. The HK session **stays running** for the full park day. Detection `inactive` does **not** call `session.pause()` (heart rate stays continuous). Instead: **`beginNewActivity`** on each confident `riding` and `inactive` (same `waterSports` type). Fitness Intervals show numbered rows (kcal / time / HR) with **no rest labels**. Disable active-energy collection while docked. Do **not** live-collect GPS distance (system would count dock walking); write ride-gated `distancePaddleSports` samples at save, one window per ride, plus interval distance on the matching `HKWorkoutActivity`. Heart rate and basal energy keep collecting. Route points go to `HKWorkoutRouteBuilder` during the session and `finishRoute` after `finishWorkout()`. Do **not** emit `motionPaused` for detection rest (purple duration).

**Activity type:** Production Watch saves `HKWorkoutActivityType.waterSports` so Health calorie / MET estimates use the water-sports model (wakeboarding), not paddle sports. Fitness **distance / average-speed tiles still follow the activity-type template** (DCS-44): `waterSports` has no distance template, so those summary tiles may stay blank even when samples exist. Calories, heart rate, GPS route map, and numbered intervals still save. In-app logbook shows max / avg speed and per-ride splits from GPS timestamps (`LocationSpeedStats`). At `finishWorkout()` Watch writes:

- Per-ride `HKQuantityTypeIdentifier.distancePaddleSports` (ride-gated meters, aligned to ride activities)
- Session `HKMetadataKeyAverageSpeed` (ride meters / riding duration) and `HKMetadataKeyMaximumSpeed` (peak usable GPS)
- Session metadata `nl.dcsbl.rppl.totalDistanceMeters`
- Per-ride activity metadata `nl.dcsbl.rppl.distanceMeters` (+ interval average speed)

Do **not** dual-write walking+running or swimming distance (pollutes those Health charts; Fitness still ignored them on water-sports). JSONL remains the source for in-app stats.

**Activity-type tradeoff:** Fitness/Health list the workout as Water Sports. Calorie estimate uses the water-sports model. Fitness may omit summary distance/speed until Apple adds a water-sports distance template; route + samples stay on the workout for that future. Do not claim the Health type is wakeboarding in App Store copy. Rest/transition **word labels** are still not possible.

**Product Pause** (Watch Pause button) is separate from detection `inactive`: it freezes the session clock, flushes then stops GPS/motion, **pauses the HK session**, and writes `inactive` detection lines with `detectorId` `product_pause` / `product_resume` (intentional sensor gap). Resume stays `inactive` until live detection re-proves `riding`.

**Rides vs laps in Health:** Fitness intervals are detection **rides and dock waits**, not cable-park **loop laps** (`LapRideTracker`). Loop laps stay in-app / export only. Never emit `HKWorkoutEvent.lap` unless Fitness shows a lap count we can fill.

If Health denies workout sharing (common after tapping Don’t Allow, or flaky on Simulator), the Watch continues in **sensors-only** mode: GPS + detections still record; HR/energy from the builder are skipped.

Water temperature: sparse `HKQuantityTypeIdentifier.waterTemperature` samples are added to the finished workout after `endCollection` (same window as ride distance), when Ultra recorded any. They appear in Health as samples on that workout. Fitness / Workout summary tiles are Apple-controlled and typically show water temp for swimming/dive, not generic water sports — Rppl does not switch activity type for temperature. JSONL remains the source for in-app stats.

Air weather: Watch fetches WeatherKit current conditions from the first usable GPS fix (retry at stop, ~8 s timeout). On save it attaches `HKMetadataKeyWeatherTemperature`, `HKMetadataKeyWeatherHumidity`, and `HKMetadataKeyWeatherCondition`. Fail open — missing weather never blocks `finishWorkout()`. Distinct from Ultra water-temperature samples. Requires the Watch WeatherKit entitlement (and App ID capability).

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
