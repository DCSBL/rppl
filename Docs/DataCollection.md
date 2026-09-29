# Data collection

Cable-park wakeboarding data collector. Tracking runs only on Apple Watch.

## Detection codes (auto)

Opaque strings written to `detections.jsonl`:

- `inactive` — not riding (session starts here)
- `riding` — wakeboard / waterski set speed
- `unsure` — mid-ride GPS soft (Watch primary UI keeps last confident code)

Engine: `DetectionEngine` in RpplCore (filter → holds → detectors → lookback merger). Writes on transitions + lookback revisions only. Each line: `code`, `timestamp`, `reason` (km/h), `detectorId`, optional speed/accuracy/water/activity, optional `supersedesId`.

Manual Action Button labels are **removed**. Ultra Action Button may still **start** a session via Workout intent.

Schema / UML: [DESIGN.md](DESIGN.md) · Core: [../RpplCore/DESIGN.md](../RpplCore/DESIGN.md) · storage: [SessionStorage.md](SessionStorage.md) · thresholds: [RideDetection.md](RideDetection.md).

## Streams

| Stream | Approx rate | File |
|--------|-------------|------|
| GPS | Core Location; sparse while `inactive` (~10 m, 8 m filter), dense while riding/unsure | `location-000.jsonl` |
| deviceMotion | **1 Hz** while `inactive`, **25 Hz** while riding/unsure → framed zlib JSONL | `motion-000.jsonl.zlib` |
| HR / active energy (mirrored, not saved to Health) | workout builder | `health-000.jsonl` |
| Water temperature | sparse; Ultra while submerged (~first sample of a bout, then ~15 s) | `water-000.jsonl` |
| Battery | sparse; raw `WKInterfaceDevice.batteryLevel` (0…1 Float) + state; on change / 60 s / start·stop·pause·resume | `battery-000.jsonl` |
| Detections | on transitions / revisions | `detections.jsonl` |
| Manifest | once | `manifest.json` |

Schema **v3**: detections replace labels/assumptions. Legacy `assumptions.jsonl` migrates to detections on open; transfer packages may still carry `assumptions` / `labels` keys (decoded into detections / discarded).

Schema **v4**: detection code `paused` rewritten to `inactive` on read/append (one-time per session package).

## Derived stats

Set distance, duration, set count, riding/inactive ratio, calories, sustained/trimmed speeds, session water-temperature mean, and record highlights come from `SessionStatsBuilder` in RpplCore (detections + GPS + health + water).

After Stop / import, Core writes `derived/view.json` (`SessionAnalyzer.version` + stats + `MapTrackFrame`). Phone logbook list and detail basics read that file; GPS polyline loads after detail appear. Rebuild when analyzer version is stale or sidecar missing. Layout: [SessionStorage.md](SessionStorage.md).

Watch live UI still uses in-memory trackers while recording. Past sessions stay phone-only.

Water temperature is a session metric (mean of persisted samples). Ultra sets `manifest.waterTemperatureAvailable`; the UI hides the tile on unsupported watches, shows `- C` until the first sample, then the average. Submersion is when the Watch can measure; the value stays relevant while riding. Watch target needs the **Shallow Depth and Pressure** entitlement (`com.apple.developer.submerged-shallow-depth-and-pressure`) and `underwater-depth` in `WKBackgroundModes`, plus `NSMotionUsageDescription` — without the entitlement, `CMWaterSubmersionManager` reports `CMErrorNotEntitled` and never delivers submerged / water-temp events. Depth-zone updates (`submergedShallow` / `submergedDeep` / …) normalize to opaque detection string `submerged`; water-temp samples also mark submerged if a temperature callback races ahead of the state event.

## HealthKit policy

`HKWorkoutSession` + builder run for sensors/runtime and **save to Health** on stop (`finishWorkout()`). Starting a session requires **share** authorization for Workouts. The HK session **stays running** for the full park day. Detection `inactive` does **not** call `session.pause()` (heart rate stays continuous). Instead: **`beginNewActivity`** on each confident `riding` and `inactive` (same `waterSports` type). Fitness Intervals show numbered rows (kcal / time / HR) with **no rest labels**. Disable active-energy collection while docked. Do **not** live-collect GPS distance (system would count dock walking); write ride-gated `distancePaddleSports` samples at save, one window per set, plus interval distance on the matching `HKWorkoutActivity`. Heart rate and basal energy keep collecting. Route points go to `HKWorkoutRouteBuilder` during the session and `finishRoute` after `finishWorkout()`. Do **not** emit `motionPaused` for detection rest (purple duration).

**Heart rate over clothing / wetsuit:** the optical sensor needs skin contact, so HR can be absent for a whole session. Nothing else depends on it (detection ignores HR). Watch shows `- BPM`; calories are kept whenever watchOS emits energy samples; when none exist the iPhone shows `-` with an info popover instead of hiding the tile. Missing values stay nil in `health-000.jsonl`; no manifest flag.

**Activity type:** Production Watch saves `HKWorkoutActivityType.waterSports` so Health calorie / MET estimates use the water-sports model (wakeboarding), not paddle sports. Fitness **distance / average-speed tiles still follow the activity-type template** (DCS-44): `waterSports` has no distance template, so those summary tiles may stay blank even when samples exist. Calories, heart rate, GPS route map, and numbered intervals still save. In-app logbook shows max / avg speed and per-set splits from GPS timestamps (`LocationSpeedStats`). At `finishWorkout()` Watch writes:

- Per-ride `HKQuantityTypeIdentifier.distancePaddleSports` (ride-gated meters, aligned to set activities)
- Session `HKMetadataKeyAverageSpeed` (set meters / riding duration) and `HKMetadataKeyMaximumSpeed` (peak usable GPS)
- Session metadata `nl.dcsbl.rppl.totalDistanceMeters`
- Per-ride activity metadata `nl.dcsbl.rppl.distanceMeters` (+ interval average speed)

Do **not** dual-write walking+running or swimming distance (pollutes those Health charts; Fitness still ignored them on water-sports). JSONL remains the source for in-app stats.

**Activity-type tradeoff:** Fitness/Health list the workout as Water Sports. Calorie estimate uses the water-sports model. Fitness may omit summary distance/speed until Apple adds a water-sports distance template; route + samples stay on the workout for that future. Do not claim the Health type is wakeboarding in App Store copy. Rest/transition **word labels** are still not possible.

**Product Pause** (Watch Pause button) is separate from detection `inactive`: it freezes the session clock, flushes then stops GPS/motion, **pauses the HK session**, and writes `inactive` detection lines with `detectorId` `product_pause` / `product_resume` (intentional sensor gap). Resume stays `inactive` until live detection re-proves `riding`.

**Sets vs laps in Health:** Fitness intervals are detection **sets and dock waits**, not cable-park **laps** (`LapSetTracker` circuit crossings). Laps stay in-app / derived export. Never emit `HKWorkoutEvent.lap` unless Fitness can show a lap count we fill (Apple API). Product **set** = allocated turn — distinct from lap; see AGENTS Set vs lap.

If Health denies workout sharing (common after tapping Don’t Allow, or flaky on Simulator), the Watch continues in **sensors-only** mode: GPS + detections still record; HR/energy from the builder are skipped.

Water temperature: sparse `HKQuantityTypeIdentifier.waterTemperature` samples are added to the finished workout after `endCollection` (same window as set distance), when Ultra recorded any. They appear in Health as samples on that workout. Fitness / Workout summary tiles are Apple-controlled and typically show water temp for swimming/dive, not generic water sports — Rppl does not switch activity type for temperature. JSONL remains the source for in-app stats.

Air weather: Watch fetches WeatherKit current conditions from the first usable GPS fix (retry at stop, ~8 s timeout). On save it attaches `HKMetadataKeyWeatherTemperature`, `HKMetadataKeyWeatherHumidity`, and `HKMetadataKeyWeatherCondition`. Fail open — missing weather never blocks `finishWorkout()`. Distinct from Ultra water-temperature samples. Requires the Watch WeatherKit entitlement (and App ID capability).

Water estimate: from the first usable GPS fix the Watch resolves the nearest bundled park within 1 km of the pin or a traced cable (`ParkListing.nearest`; fixes worse than 250 m accuracy are skipped until a better one arrives) and, if it has a `water_temperature` source, fetches the station reading (~8 s timeout, readings older than 48 h dropped). Stored in the manifest as `waterTemperatureEstimate` and shown on the inactive page as `~17°`, so watches without a submersion sensor (and Ultras before first submersion) still show a value. Once the Watch measures real samples, the display switches to the measured average and the estimate is no longer attached to the workout; otherwise it is saved as workout metadata `nl.dcsbl.rppl.waterTemperatureEstimate` (not as a Health water-temperature sample). Fail open — no park, source or network means no estimate.

## Action Button (Ultra)

Optional start only:

1. Settings › Action Button › **Workout**
2. App › **Rppl** (Cable Park)
3. Press starts the session when idle; press while recording is a **no-op**

Requires an active HealthKit workout path for Workout intent registration. Cycle Label (manual Action Button labeling) is removed.

## Transfer

Phone may be away during the session. After **Stop session**, Watch queues a WC file transfer and **keeps checkpoints until the phone sends an ack**. Transfer failure must not delete Watch data. Transfer package includes `detections` (legacy `assumptions` accepted on decode).

**Tiny-session discard** (duration < ~30s and zero sets): Stop asks Discard / Keep / Cancel. Confirmed Discard deletes the Watch package and skips transfer + Health save. Keep uses the normal transfer path (ack still required before delete).

## Export

On iPhone: open a session → tap the share icon → prepare (spinner) → system Share sheet (AirDrop / Files / …). File name:

`rppl_<startedAt-UTC>_<location>.json`

- `startedAt-UTC`: session start, ISO-8601 with `:` / `.` replaced by `-` (e.g. `2024-01-01T00-00-00Z`)
- `location`: city slug from derived `cityName` (filesystem-safe); `unknown` when missing

Payload is pretty-printed `SessionTransferPackage` JSON with top-level **`manifest` first** (encode order; not `sortedKeys`):

| Payload | Contents |
|---------|----------|
| `manifest` | Session meta + random install ID (`testerId` field; UUID; new on reinstall) |
| `detections` | Set / inactive / unsure transitions |
| `locations` | GPS with precise lat/lon (not anonymized) |
| `motion` / `motionFramesZlib` | Device motion when present |
| `health` | Mirrored heart rate and energy |
| `water` | Ultra water temperature when present |
| `battery` | Watch battery level (0…1) + state when present |
| `derived` | Fast view stats / map frame when present |

User-facing export / sharing policy: [LEGAL.md](../LEGAL.md) (Export / sharing). In-app: **iPhone → Rppl → Legal → Terms & Privacy policy**.
