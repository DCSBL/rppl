# Ride start / stop detection (intern guide)

How Rppl decides “you’re on a ride” vs “you’re waiting at the dock” from Watch GPS (and Ultra water sensors).

If you only read one thing: **codes are plain strings**, logic lives in **`RpplCore`**, Watch only feeds ticks and shows UI. Tune and test with `cd RpplCore && swift test` — no phone required.

Deeper UML: [../RpplCore/DESIGN.md](../RpplCore/DESIGN.md). Threshold table: [Phase3.md](Phase3.md). On-disk streams: [DataCollection.md](DataCollection.md).

---

## What problem this solves

A cable-park day is one long session (Start → Stop on Watch). Inside that day the rider loops:

dock → grab handle → ride → fall or stop → swim / walk back → dock again.

We need automatic **ride segments** (start + end) so distance, avg speed, and ride count only cover real rides — not walking the dock while “inactive.”

There is **no** manual “I started / I stopped” button for rides. Detection is automatic.

---

## The three codes

Written to `detections.jsonl` only when the code **changes** (plus session start, plus rare lookback revisions):

| Code | Meaning for humans |
|------|--------------------|
| `inactive` | Not riding: dock, waiting, swimming after a committed end, walking back. Session **starts** here. |
| `riding` | On the cable at ride speed. |
| `unsure` | Soft mid-ride GPS (often a fall killed the fix). Soft state: Watch UI still shows last confident code as primary. |

Unknown future codes must round-trip as strings — do not invent a closed Swift enum for the taxonomy yet (`DetectionCodes` helpers only).

---

## Mental model (park day)

```text
session start ──► inactive
                    │
        speed ≥20 km/h for 3s
                    ▼
                  riding ◄──── lookback: usable fast again within 60s
                    │
     ┌──────────────┼──────────────────┐
     │              │                  │
 slow usable     Ultra            GPS unusable
 ≤4 km/h ×3s     submerged        ×3s
     │              │                  │
     ▼              ▼                  ▼
  inactive         inactive           unsure
                                       │
                          ┌────────────┴────────────┐
                          │                         │
                   usable slow /              age ≥ 60s
                   water submerged            timeout
                          │                         │
                          ▼                         ▼
                       inactive                    inactive
                          │
              later: speed ≥20 ×3s again
                          ▼
                       riding   ← always a *new* ride after inactive
```

**Product bias:** detect **any** new start from `inactive` reliably. After a water fall we **end** the ride; a long swim (5–10 min) then re-dock is a **new** ride — we do not try to glue that into the same ride.

---

## Pipeline (every GPS tick)

Watch builds a `DetectionTick` (timestamp, speed m/s, horizontal accuracy, optional `waterSubmersionState`, optional motion activity) and calls `DetectionEngine.process`.

```text
DetectionTick
    → GpsSignalFilter     (is this speed usable for rules?)
    → DetectionHoldClock  (how long have we been fast / slow / unusable?)
    → lookback (if currently unsure)
    → detectors (first match wins)
    → DetectionEvent(s) when something transitions or revises
```

Core never imports CoreLocation / CoreMotion. Watch owns sensors; Core owns decisions.

### 1. GPS filter (`GpsSignalFilter`)

Speed is **unusable** (detectors that need speed ignore it) if any of:

- speed is nil
- accuracy &lt; 0 or &gt; **25 m**
- speed &gt; **45 km/h** (implausible for us)
- speed jumped ≥ **30 km/h** vs last usable sample

Bad ticks still advance time; they just do not count as “fast” or “slow” holds.

### 2. Hold clocks

While speed is usable:

- **highSpeed** — speed ≥ enter threshold (20 km/h)
- **stopped** — speed ≤ exit threshold (4 km/h)

While speed is unusable:

- **unusable** — accumulates for the GPS-gap path

Holds reset on confident transitions.

### 3. Lookback (only while `unsure`)

If GPS becomes usable again **before** 60 seconds of unsure:

| Usable speed | Result |
|--------------|--------|
| ≥ 20 km/h | Same ride: write `riding` with `supersedesId` pointing at the unsure event (`lookback`) |
| ≤ 4 km/h | End ride: write `inactive` with supersede |
| between | Stay `unsure` |

After 60 s, lookback will not merge — timeout forces `inactive`; next enter is a new ride.

### 4. Detectors (order matters — first match wins)

Default order in `DetectionEngine.defaultDetectors`:

| Order | Detector | When | Writes |
|-------|----------|------|--------|
| 1 | `unsure_timeout` | `unsure` age ≥ **60 s** | `inactive` |
| 2 | `water_exit` | `riding` or `unsure` + Ultra `submerged` | `inactive` |
| 3 | `gps_gap` | `riding` + unusable ≥ **3 s** | `unsure` |
| 4 | `ride_exit` | `riding` + usable slow ≤4 km/h × **3 s** | `inactive` |
| 5 | `ride_enter` | `inactive` + usable fast ≥20 km/h × **3 s** | `riding` |

**Why water before gap:** a fall in water often kills GPS. Ultra can say “submerged” even when speed is garbage — end the ride immediately instead of waiting on the unsure timer.

**Non-Ultra:** no water sensor → GPS gap → unsure → timeout or lookback. Same enter/exit speed rules.

Motion activity (`walking`, etc.) is **logged** on events when present; it does **not** drive decisions today.

---

## Default thresholds (km/h in product language)

Authoritative defaults: `DetectionThresholds` in RpplCore.

| Constant | Default | Role |
|----------|---------|------|
| Ride enter | ≥ **20** km/h × **3.0** s | `inactive` → `riding` |
| Ride exit | ≤ **4** km/h × **3.0** s | `riding` → `inactive` (usable GPS only) |
| GPS gap | unusable × **3.0** s | `riding` → `unsure` |
| Same-ride / timeout window | **60** s | lookback merge vs force `inactive` |
| Accuracy gate | **25** m | worse → unusable for speed rules |
| Implausible / jump | **45** / **30** km/h | filter spikes |

Internal comparisons use m/s; `reason` strings on events print **km/h** so exports are human-readable.

---

## What gets written to disk

`detections.jsonl` lines are sparse:

- `session_start` → `inactive`
- each real code change (`ride_enter`, `ride_exit`, `water_exit`, `gps_gap`, `unsure_timeout`, …)
- lookback revision with `supersedesId` (append-only; old unsure line stays, stats ignore superseded ids)

GPS samples live in separate location JSONL. Detections do **not** store the whole track.

---

## How stats use detections (don’t confuse the two)

Detection decides **when** rides start/stop. Stats **derive** meters and speeds later:

| Piece | Behavior (current) |
|-------|--------------------|
| `LiveRideTracker` (Watch live UI) | Accrue distance/speed only while code is confidently `riding`. Unsure freezes meters. Session distance = sum of ride meters. |
| `SessionStatsBuilder` (phone / export) | Ride windows = attributed `riding` phases. **`unsure` counts as inactive for windows** (ride ends at gap). Lookback supersede restores one continuous ride when the unsure line is superseded. |
| Peak speed | Filtered like detection (accuracy / 45 / jump). Session top = max over **ride windows**, not whole-day GPS. |

So: walking the dock while `inactive` must not grow distance. A GPS spike between rides must not become “session top speed.”

---

## Common park stories → what the engine does

1. **Clean stop at dock**
   Speed drops ≤4 km/h for 3 s with good GPS → `ride_exit` → `inactive`. Next pull-away ≥20×3s → new `riding`.

2. **Fall, Ultra**
   `submerged` while riding → `water_exit` → `inactive` immediately. Swim 8 minutes, walk back, start again → new ride (by design).

3. **Fall, Non-Ultra / GPS dies**
   Unusable 3 s → `unsure`. If fix returns fast within 60 s → same ride (lookback). If not → `unsure_timeout` → `inactive`, later start is new ride.

4. **Brief GPS flake mid-ride**
   One bad tick: ignored. Sustained bad: unsure, then lookback if speed returns quickly.

5. **Cable stopped mid-run, long wait in water**
   We prioritize ending/starting cleanly over “same ride after 10 minutes.” Water exit + 60 s window intentionally **do not** keep that as one ride.

---

## Where to change code

| Want to… | Start here |
|----------|------------|
| Thresholds | `DetectionThresholds.swift` |
| Filter rules | `GpsSignalFilter.swift` |
| New start/stop rule | New `Detector` + register in `DetectionEngine.defaultDetectors` |
| Live Watch meters | `LiveRideTracker.swift` |
| Offline ride list / distance | `SessionStatsBuilder.swift` |
| Watch feeds ticks | `RpplWatch/WatchSessionController.swift` |

Offline experiments: `DetectionEngine.replay(ticks:)` or `replay(locations:)`.

---

## Quick myths

- **“Session pause”** — product day-session is continuous. `inactive` means *not riding*, not “workout paused” in the Start/Stop sense. HealthKit keeps the session running; ride-scoped active energy/distance use motion events + collection gating, not `session.pause()`. Product Pause still pauses HK.
- **“Unsure means swimming”** — no. Unsure means GPS soft. Swimming after Ultra fall is usually already `inactive` via `water_exit`.
- **“Average speed should equal cable speed”** — avg = ride distance / ride duration. Bad GPS distance or late ride-end still skews it; that is why end detection and step filters matter.

---

## Suggested first exercise

1. Read `DetectionEngineTests` — names describe park loops.
2. Sketch one timeline (enter → gap → lookback) on paper with timestamps.
3. Change only `unsureSameRideWindow` in a local test thresholds struct and replay; do not change defaults until you understand lookback vs timeout.
