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
| Phone | App Group `group.nl.dcsbl.rppl/Sessions` when available, else Documents |

Same folder shape after WC import. Lower than ~10 MB/h when dock time dominates (1 Hz motion + sparse GPS while `inactive`).

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
| Phone list | Summary stats (distance, duration, rides, laps, speeds, highlights inputs) | Motion; full GPS parse |
| Phone detail basics | Same stats + per-ride splits | Motion |
| Phone map | Stored geo frame for first camera; GPS polyline after appear | Motion |
| Re-analysis | Raw detections + locations (+ health/water for tiles; motion if detectors need it) | — |
| Watch live | RAM / live trackers while recording | Derived files |
| Watch history | **Out** — active session + sync status only; past sessions phone-only |

City name is phone-only (geocode cache). Not part of Watch↔phone equality.

## Derived stats today

`SessionStatsBuilder` builds stats from raw streams. Catalog and detail basics read `derived/view.json` when present (ensure rebuilds if missing/stale). Motion never loaded for logbook UI. Detail map uses stored `MapTrackFrame` first; GPS polyline loads async.

## Fast view files

```text
derived/view.json    # analyzerVersion + SessionStats + MapTrackFrame?; cityName phone-optional
```

| Rule | Detail |
|------|--------|
| Write | After Watch **Stop**; phone import keep if `analyzerVersion` matches else rebuild from raw (same `RpplCore`) |
| Transfer | Include `derived` when present so Watch and iPhone stay aligned |
| Read | Phone list / detail basics from `view.json`; rebuild only if missing or analyzer version stale |
| Map | Store device-agnostic `MapTrackFrame` (center, heading, geographic span). Phone computes camera distance for its map view size |
| Mid-record | No derived write; live metrics stay RAM |
| Crash | No new resume; do not regress today’s crash = dead |

Raw remains required to regenerate `derived/` after analyzer bumps or storage migrations. Distilled-only (drop raw) and Finder/USB Documents sharing are **out of this work**.

## Non-goals (this issue)

- `UIFileSharingEnabled` / Files over USB
- Delete raw / distilled-only mode
- iCloud sync
- Watch past-session viewer
- New crash / HK workout recovery features
