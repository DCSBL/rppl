# Session storage

On-disk layout for Watch and iPhone session packages. Streams and HealthKit policy: [DataCollection.md](DataCollection.md). Core IO: [../RpplCore/DESIGN.md](../RpplCore/DESIGN.md).

## Layout (schema v1)

```text
<root>/<YYYY-MM-DD HH-mm - City>/   # display name; identity is manifest.sessionId
  manifest.json               # canonical sessionId (UUID)
  detections.jsonl
  location-000.jsonl
  motion-000.jsonl.zlib
  health-000.jsonl
  water-000.jsonl         # optional Ultra
  battery-000.jsonl       # optional Watch battery level + state
  derived/
    view.json             # analyzerVersion + SessionStats + MapTrackFrame?
```

**Folder naming**

- Format: `YYYY-MM-DD HH-mm - City` (local start of `startedAt`; city from phone geocode, else `Unknown`).
- Same-minute collisions (rare): `… (2)`, `… (3)`, …
- Identity is always `manifest.sessionId`. Discovery scans for `manifest.json`; folder name is display-only.
- Manual renames in Files are preserved (store will not overwrite a user-renamed folder).

A missing or stale `derived/view.json` is rebuilt from the raw streams when it is ensured.

### Schema and migrations

`manifest.schemaVersion` is **1**: the format was reset once and nothing older is supported. A future breaking change bumps `SessionSchema.currentVersion` and appends a step to `SessionMigrations`; `SessionFileStore.migrateIfNeeded` runs the pending steps (in version order) when a session is opened and stamps the new version.

**Roots**

| Target | Root |
|--------|------|
| Watch | Documents/`Sessions` |
| Phone (iCloud Drive **on**, default) | Ubiquity container `iCloud.nl.dcsbl.rppl` → `Documents/Sessions` (Apple file sync) |
| Phone (iCloud Drive **off** / unavailable) | App Group `group.nl.dcsbl.rppl/Sessions` when available, else Documents |

The Dev configuration swaps in `iCloud.nl.dcsbl.rppl.dev` / `group.nl.dcsbl.rppl.dev` ([Docs/DevWorkflow.md](DevWorkflow.md#dev-variant-clean-install-next-to-the-real-one)).

Same folder shape after WC import. The import builds the package in tmp and swaps it in at the end, so a failure leaves an existing phone copy untouched. Damaged or over-limit motion frames are dropped (`motionStoppedReason` `import_limit`) and never fail the import. Lower than ~10 MB/h when dock time dominates (1 Hz motion + sparse GPS while `inactive`).

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
| `battery-*.jsonl` | Watch battery fraction (0…1) + state | sparse |

Raw is the regeneration source when analyzers change. Export / WC transfer carries these streams (motion as framed zlib when present). No public millivolt API on watchOS — battery `level` is the raw `Float` fraction from `WKInterfaceDevice`.

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

`SessionStatsBuilder` builds stats from raw streams. Catalog and detail basics read `derived/view.json` when present (ensure rebuilds if missing/stale). Motion never loaded for logbook UI. Session map uses distilled `mapTracks` (heatmap set paths + start pin) and `MapTrackFrame` for camera; phone may rebuild from raw when derived is stale.

## Fast view files

```text
derived/view.json    # analyzerVersion + SessionStats + MapTrackFrame? + mapTracks?; cityName phone-optional
```

| Rule | Detail |
|------|--------|
| Write | After Watch **Stop**; phone import keep if `analyzerVersion` matches else rebuild from raw (same `RpplCore`) |
| Transfer | Include `derived` when present so Watch and iPhone stay aligned |
| Read | Phone list / detail basics from `view.json`; rebuild only if missing or analyzer version stale |
| Map | Store device-agnostic `MapTrackFrame` + distilled `mapTracks` (heatmap set paths, start pin). Phone computes camera distance for its map view size |
| Mid-record | No derived write; live metrics stay RAM |
| Crash | No resume. On next Watch launch, sessions left in `recording` (not the active one) are finalized: terminal `inactive` marker with `detectorId` `crash_recovered`, `endedAt` = the last recorded sample (detections, GPS, health, water or battery, so the final set is kept), `readyToTransfer`, derived view built, then queued for transfer. No prompt; the rider starts a new session manually |

Raw remains required to regenerate `derived/` after analyzer bumps or storage migrations.

**Keys:** `SessionStats` uses `setCount` and `sets`; `SetSegmentStats` uses `lapCount`. A stale `analyzerVersion` triggers a rebuild; an unreadable sidecar is treated as missing so `ensureDerivedView` regenerates it from raw.

## Out of scope

- `UIFileSharingEnabled` / Files over USB
- Raw stream sync phone → Watch (view sync carries derived only)
- CloudKit
- Watch logbook edit / delete (view-only mirror of phone)
- Resuming an interrupted session, and HK workout recovery (merge of split sessions may come later)
