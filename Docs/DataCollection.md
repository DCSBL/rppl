# Data collection

Cable-park wakeboarding data collector. Tracking runs only on Apple Watch; sessions can also be typed in on iPhone (`manifest.manual`, see [SessionStorage.md](SessionStorage.md)), with no sensors and no HealthKit.

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
| deviceMotion | **1 Hz** while `inactive`, **25 Hz** while riding/unsure → framed zlib JSONL, one frame per **30 s**. Expendable: see *Motion gives way first* below | `motion-000.jsonl.zlib` |
| HR / active energy (mirrored, not saved to Health) | workout builder | `health-000.jsonl` |
| Water temperature | sparse; Ultra while submerged (~first sample of a bout, then ~15 s) | `water-000.jsonl` |
| Height (barometer) | `CMAltimeter` relative altitude (m, cm resolution) + pressure (kPa), ~1 Hz while riding only (the hold before a confirmed `riding` is backfilled); recorded only, nothing reads it yet. Not on every Watch and can drop out, so gaps are normal; relative altitude re-zeros when updates restart (after a product pause) | `altitude-000.jsonl` |
| Battery | sparse; raw `WKInterfaceDevice.batteryLevel` (0…1 Float) + state; on change / 60 s / start·stop·pause·resume | `battery-000.jsonl` |
| Detections | on transitions / revisions | `detections.jsonl` |
| Manifest | once | `manifest.json` |

Session packages are schema **v1** (`manifest.schemaVersion`). The format was reset once; there are no migrations or compatibility paths for anything older. Future format changes bump the version and add a step to `SessionMigrations` (see [SessionStorage.md](SessionStorage.md#schema-and-migrations)).

## Derived stats

Set distance, duration, set count, riding/inactive ratio, calories, sustained/trimmed speeds, session water-temperature mean, and record highlights come from `SessionStatsBuilder` in RpplCore (detections + GPS + health + water).

### Record badges

`HighlightAssigner` hands out record badges. Set badges compare sets within one session and are stored in `derived/view.json`. Session badges compare the whole logbook and are computed when the list loads. A "highest" badge needs at least two values, a "lowest" badge at least three. Ties and missing values (no weather, older sessions) award nothing. Character badges (marked *gated*) also need the record to clear a line, else nobody gets them; the app copy never names the numbers. Tapping a badge in the app explains it.

| Scope | Badge | Rule |
|-------|-------|------|
| Set | `longest` / `longestTime` / `shortest` / `fastest` | Distance, duration, shortest duration, sustained speed |
| Set | `mostLaps` | Most laps (more than zero) |
| Set | `comeback` / `backToBack` | Longest / shortest break since the previous set; *gated*: over 15 min / under 2 min |
| Session | `longest` / `mostWaterTime` / `mostLaps` / `mostCalories` / `longestSetEver` | Duration, riding time, laps, energy, longest set by distance |
| Session | `highestRidePercentage` / `laziest` | Highest / lowest riding ratio; *gated*: over 50% / under 25% |
| Session | `mostSets` / `mostDistance` / `topSpeed` | Set count, distance, peak speed |
| Session | `coldest` / `hottest` / `windiest` / `rainiest` | Weather snapshot; *gated*: air below 10 °C / above 25 °C, wind above Bft 4, rain at least 0.5 mm/h |
| Session | `iceBath` | Coldest water: measured mean, else park estimate; *gated*: below 17 °C |
| Session | `earlyBird` / `nightOwl` | Earliest start / latest end, local time of day; *gated*: before 10:00 / after 21:00 |

After Stop / import, Core writes `derived/view.json` (`SessionAnalyzer.version` + stats + `MapTrackFrame`). Phone logbook list and detail basics read that file; GPS polyline loads after detail appear. Rebuild when analyzer version is stale or sidecar missing. Layout: [SessionStorage.md](SessionStorage.md).

Watch live UI still uses in-memory trackers while recording. Past sessions stay phone-only.

Water temperature is a session metric: a rolling mean of the latest persisted samples (trailing window of at least 5 samples and 5 minutes; all samples while the window cannot be filled), so early readings taken under the wetsuit are forgotten once the Watch sits on top. The Watch shows that rolling value live. The phone session detail never shows a whole-session average: when the session min–max spans more than 3 °C it shows `low – high` (we cannot know which reading is correct), otherwise the single rolling value (`WaterTemperatureSummary`). Ultra sets `manifest.waterTemperatureAvailable`; the UI hides the tile on unsupported watches, shows `- C` until the first sample, then the average. Submersion is when the Watch can measure; the value stays relevant while riding. Watch target needs the **Shallow Depth and Pressure** entitlement (`com.apple.developer.submerged-shallow-depth-and-pressure`) and `underwater-depth` in `WKBackgroundModes`, plus `NSMotionUsageDescription` — without the entitlement, `CMWaterSubmersionManager` reports `CMErrorNotEntitled` and never delivers submerged / water-temp events. Depth-zone updates (`submergedShallow` / `submergedDeep` / …) normalize to opaque detection string `submerged`; water-temp samples also mark submerged if a temperature callback races ahead of the state event.

## HealthKit policy

`HKWorkoutSession` + builder run for sensors/runtime and **save to Health** on stop (`finishWorkout()`). Starting a session requires **share** authorization for Workouts. The HK session **stays running** for the full park day. Detection `inactive` does **not** call `session.pause()` (heart rate stays continuous). Instead: **`beginNewActivity`** at workout start (`inactive`, so every workout has an interval even with no riding) and on each confident `riding` and `inactive` (same `waterSports` type). Fitness Intervals show numbered rows (kcal / time / HR) with **no rest labels**. Disable active-energy collection while docked. Do **not** live-collect GPS distance (system would count dock walking); write ride-gated `distancePaddleSports` samples at save, one window per set, plus interval distance on the matching `HKWorkoutActivity`. Heart rate and basal energy keep collecting. Route points go to `HKWorkoutRouteBuilder` during the session and `finishRoute` after `finishWorkout()`. Do **not** emit `motionPaused` for detection rest (purple duration).

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

**Health access is required to start.** The HK workout session is what keeps the app running with the wrist down (watchOS suspends it otherwise, stopping GPS, motion and detection), and an `HKWorkoutSession` cannot start without workout sharing access. Health must be `authorized` — denied, restricted or unavailable (including the Simulator) all block Start. Location is required the same way. The Watch stays browsable: the logbook and existing sessions remain viewable, and only Start (idle tap, Action Button, Siri) is refused with a "Can't start yet" sheet that names the missing permission, explains why and how to enable it (Health app › Sharing › Apps › Rppl; watchOS cannot deep-link to Settings), and offers **Try again**. Nothing asks before the first Start: there is no onboarding screen, and launching the Watch app only reads permission status. `startSession` presents the system sheets still undecided (Health, Location, Motion), each answered before the next shows (the Location answer is awaited, bounded at 60 s, so Start never reads an undecided state as blocked). The idle Permissions button and the "Can't start yet" sheet's **Try again** are the only other triggers. The decision lives in Core (`WatchPermissionOrder.startBlocker`, `SessionStartGate`).

**iPhone asks just in time too.** No sheet at launch or on first sync. Location is requested where it is used: the Parks *Nearby* list, the map's *Center on my location* button, and the park editor's *Use my current location* button. Opening the Parks map never prompts and starts on the Netherlands; the blue dot and recentering need location granted. The About › Permissions rows stay as a manual way to allow or fix a permission.

If the workout start only *times out or fails* (busy `healthd`, older watches), the session is not blocked: it records in a temporary **sensors-only** mode (GPS + detections, shown as "Screen-on only") and retries the HK start every 30 s (max 10) until a workout session protects the recording.

Water temperature: sparse `HKQuantityTypeIdentifier.waterTemperature` samples are added to the finished workout after `endCollection` (same window as set distance), when Ultra recorded any. They appear in Health as samples on that workout. Fitness / Workout summary tiles are Apple-controlled and typically show water temp for swimming/dive, not generic water sports — Rppl does not switch activity type for temperature. JSONL remains the source for in-app stats.

Air weather: Watch fetches WeatherKit current conditions from the first usable GPS fix (retry at stop, ~8 s timeout). On save it attaches `HKMetadataKeyWeatherTemperature`, `HKMetadataKeyWeatherHumidity`, and `HKMetadataKeyWeatherCondition`. Fail open — missing weather never blocks `finishWorkout()`. Distinct from Ultra water-temperature samples. Manual sessions typed in on iPhone get the hour nearest the session midpoint from WeatherKit hourly history after saving (the park pin or picked place, best effort, nothing before 2022-08-01). WeatherKit calls are capped per month, so every call site (Watch + phone park weather) goes through `WeatherFetchThrottle`: max one network attempt per location (~5 km grid) per hour, failures included; a Watch session starting at the same spot within the hour reuses the previous snapshot. No fetch time is shown in the UI. Requires the Watch WeatherKit entitlement (and App ID capability). Apple requires the Apple Weather mark and its legal link wherever WeatherKit values are on screen, stored ones included: put `AppleWeatherAttribution` (`Rppl/Design/`) next to them, as the session detail air tile and the park conditions do.

Water estimate: from the first usable GPS fix the Watch resolves the nearest bundled park within 1 km of the pin or a traced cable (`ParkListing.nearest`; fixes worse than 250 m accuracy are skipped until a better one arrives) and, if it has a `water_temperature` source, fetches the station reading (~8 s timeout, readings older than 48 h dropped). Stored in the manifest as `waterTemperatureEstimate` and shown on the inactive page as `~17°`, so watches without a submersion sensor (and Ultras before first submersion) still show a value. Once the Watch measures real samples, the display switches to the measured rolling mean and the estimate is no longer attached to the workout; otherwise it is saved as workout metadata `nl.dcsbl.rppl.waterTemperatureEstimate` (not as a Health water-temperature sample). Fail open — no park, source or network means no estimate.

## Action Button (Ultra)

Optional start only:

1. Settings › Action Button › **Workout**
2. App › **Rppl** (Cable Park)
3. Press starts the session when idle; press while recording is a **no-op**

Requires an active HealthKit workout path for Workout intent registration. Cycle Label (manual Action Button labeling) is removed.

## Battery guard

The Health workout and the phone transfer only happen at Stop, and a park day can outlast an older Watch's battery (roughly 6–7 h with GPS and heart rate). `BatteryGuardPolicy` (Core) decides what the Watch does while it runs down, checked on every flush:

- **Unplugged** (an unknown state counts as unplugged): a notification haptic and a flush once at **15 %** and once at **10 %**, then an automatic Stop at **5 %** or lower. A jump past both thresholds warns once.
- The automatic Stop writes an `inactive` marker with `detectorId` `battery_critical`, then runs the normal Stop, so the Health save and the transfer happen while there is power.
- **Charging** or **full** never acts. Product Pause is not checked (sensors are off while paused).
- Battery samples (`battery-000.jsonl`) carry `lowPowerMode` (optional), so GPS gaps under Low Power Mode can be explained.

The thresholds are product defaults in one place (`BatteryGuardPolicy`).

## Transfer

Phone may be away during the session. After **Stop session**, Watch queues a WC file transfer and **keeps checkpoints until the phone sends an ack**. Transfer failure must not delete Watch data. Transfer package includes `detections`.

**While a session records**, the Watch does no work that is not part of the recording: no packaging of older sessions (acks are still processed), no view sync with the phone, no scan for orphaned recordings and no pending-transfer count. They run after Stop. Each of them reads every stored manifest, and on an older Watch a wrist raise would stall the main thread of a running workout. The view-sync service keeps one `SessionFileStore`, so its package path cache survives and listing N sessions is linear.

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
| `altitude` | Barometric relative altitude + pressure when the Watch has a barometer |
| `derived` | Fast view stats / map frame when present |

User-facing export / sharing policy: [LEGAL.md](../LEGAL.md) (Export / sharing). In-app: **iPhone → Rppl → Legal → Terms & Privacy policy**.

Session detail (iPhone): the toolbar Export button opens the share sheet with the raw JSON. When Mail is set up (`MFMailComposeViewController.canSendMail()`), it becomes a menu with **Send to Rppl**: the export is zipped, attached to a mail to rppl@dcsbl.nl with a "Why I'm sending this session" template, and capped at 20 MB. Larger sessions show a message pointing to Export; there is no base64 / plain-text fallback.

## Set flags

Rider self-notes per detected set (`manifest.setFlags`, see [SessionStorage.md](SessionStorage.md#set-flags)), added on the phone after the set. No timestamps: one flag list per set, meant as notes and as labels for later ML. Not a detection taxonomy; the strings stay opaque.

## Motion gives way first

Nothing analyses device motion yet; it is kept for future event / trick analysis. `scripts/analyze-session.py` decodes it offline (airtime, impacts, spins next to GPS, per set); labelled examples live in the session fixtures. It is the first stream to stop so GPS, detection, health and water keep recording (`MotionRecordingPolicy` in Core, checked after each motion frame and at start):

| Condition | Effect | `manifest.motionStoppedReason` |
|-----------|--------|-------------------------------|
| Session ≥ **4 h** | stop motion for the rest of the session | `long_session` |
| Compressed motion ≥ **15 MB** | stop | `file_budget` |
| Free space < **300 MB** (or a motion write fails) | stop | `low_storage` |
| Free space < **100 MB** | stop and delete this session's motion | `storage_critical` |

`manifest.motionStoppedAt` records when. Motion is written after every other stream, so a failed motion write never costs GPS or health samples.
