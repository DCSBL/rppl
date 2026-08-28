# Session storage

On-disk layout for Watch and iPhone session packages. Streams and HealthKit policy: [DataCollection.md](DataCollection.md). Core IO: [../RpplCore/DESIGN.md](../RpplCore/DESIGN.md).

## Current layout (schema v6)

```text
<root>/<sessionId>/
  manifest.json
  detections.jsonl
  location-000.jsonl
  motion-000.jsonl.zlib   # or legacy motion-000.jsonl
  health-000.jsonl
  water-000.jsonl         # optional Ultra
  derived/
    view.json             # analyzerVersion + SessionStats + MapTrackFrame?
```

Legacy: `assumptions.jsonl` / `labels.jsonl` (migrate or ignore). Older packages without `derived/` rebuild on open.

**Roots**

| Target | Root |
|--------|------|
| Watch | Documents/`Sessions` |
| Phone (iCloud Drive **on**, default) | Ubiquity container `iCloud.nl.dcsbl.rppl` → `Documents/Sessions` (Apple file sync) |
| Phone (iCloud Drive **off** / unavailable) | App Group `group.nl.dcsbl.rppl/Sessions` when available, else Documents |

Same folder shape after WC import. Lower than ~10 MB/h when dock time dominates (1 Hz motion + sparse GPS while `inactive`).

### Phone iCloud Drive

- Preference in `NSUbiquitousKeyValueStore` (default **on**). Toggle: iPhone → rppl → Data.
- Live `SessionFileStore` root switches to ubiquity Documents when enabled; Apple syncs creates / edits / deletes across devices.
- Remote packages not yet accepted on this phone: `NSMetadataQuery` + multi-select import picker (location, date, sets, duration).
- Accepted session ids are **local** (`UserDefaults`) so a second iPhone still asks before import.
- Turn **off**: confirm whether to delete Drive copies; packages are copied back to App Group first.
- Visible in Files under iCloud Drive → Rppl (`NSUbiquitousContainerIsDocumentScopePublic`).
- Watch recording stays local Documents; WC import writes into the phone’s current live root.
- Not CloudKit. Prefer `FileManager` ubiquity APIs, `NSFileCoordinator`, `NSMetadataQuery`.

## What is stored (raw)

| File | Role | Approx |
|------|------|--------|
| `manifest.json` | Meta, transfer state, activity, water-temp capability, Watch wrist/crown settings | once |
| `detections.jsonl` | Ride/inactive/unsure transitions | sparse |
| `location-*.jsonl` | GPS | CL updates |
| `motion-*.jsonl.zlib` | Device motion | **1 Hz** inactive, **25 Hz** riding/unsure |
| `health-*.jsonl` | Mirrored HR / energy | workout cadence |
| `water-*.jsonl` | Ultra water temperature | sparse |

Raw is the regeneration source when analyzers change. Export / WC transfer carries these streams (motion as framed zlib when present).

## What UI needs

| Surface | Needs | Skip for UI |
|---------|-------|-------------|
| Phone list | Summary stats (distance, duration, sets, laps, speeds, highlights inputs) | Motion; full GPS parse |
| Phone detail basics | Same stats + per-set splits | Motion |
| Phone map | Stored geo frame + distilled `mapTracks`; live GPS refines on phone | Motion |
| Re-analysis | Raw detections + locations (+ health/water for tiles; motion if detectors need it) | — |
| Watch live | RAM / live trackers while recording | Derived files |
| Watch logbook | `manifest.json` + `derived/view.json` (mirrors phone after sync) | Raw streams (pruned post-ack) |

City name is phone-only (geocode cache). Phone pushes it to Watch via view sync. Not part of Watch→phone WC package equality.

## Watch distilled logbook

After phone **ack**, Watch may **prune raw streams** and keep only:

```text
manifest.json
derived/view.json
```

- **Source of truth:** iPhone logbook (phone pushes `viewUpdate`; delete on phone → `viewDelete` on Watch).
- **Resync:** event-driven — phone pushes on import / geocode / re-analyze; Watch requests diff when logbook opens or app becomes active (reachable only). No polling timers.
- **Pending sync** (`readyToTransfer` / `transferring`): full raw kept until ack; logbook shows session with sync dot when derived exists.
- **Broken** (no readable derived): omitted from Watch list.

## Derived stats today

`SessionStatsBuilder` builds stats from raw streams. Catalog and detail basics read `derived/view.json` when present (ensure rebuilds if missing/stale). Motion never loaded for logbook UI. Session map uses distilled `mapTracks` (averaged + heatmap polylines) and `MapTrackFrame` for camera; phone may rebuild from raw when derived is stale.

## Fast view files

```text
derived/view.json    # analyzerVersion + SessionStats + MapTrackFrame? + mapTracks?; cityName phone-optional
```

| Rule | Detail |
|------|--------|
| Write | After Watch **Stop**; phone import keep if `analyzerVersion` matches else rebuild from raw (same `RpplCore`) |
| Transfer | Include `derived` when present so Watch and iPhone stay aligned |
| Read | Phone list / detail basics from `view.json`; rebuild only if missing or analyzer version stale |
| Map | Store device-agnostic `MapTrackFrame` + distilled `mapTracks` (averaged loop, heatmap set paths, start pin). Phone computes camera distance for its map view size |
| Mid-record | No derived write; live metrics stay RAM |
| Crash | No new resume; do not regress today’s crash = dead |

Raw remains required to regenerate `derived/` after analyzer bumps or storage migrations.

**Forward compat:** `SessionStats` canonical keys are `setCount` and `sets`. Decode also accepts legacy `rideCount` / `rides`. Encode writes `setCount` / `sets` only. `SetSegmentStats` canonical key is `lapCount`. Decode also accepts intermediate slang mis-key `setCount` on segments (circuit crossings briefly mislabeled). Encode writes `lapCount` only. Stale `analyzerVersion` still triggers rebuild; unreadable sidecars are treated as missing so `ensureDerivedView` regenerates from raw.

## Out of scope

- `UIFileSharingEnabled` / Files over USB
- Raw stream sync phone → Watch (view sync carries derived only)
- CloudKit
- Watch logbook edit / delete (view-only mirror of phone)
- New crash / HK workout recovery features
