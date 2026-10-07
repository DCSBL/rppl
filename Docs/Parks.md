# Parks

The Parks tab lists cable parks (nearby or most visited; the Favourites filter narrows to starred parks) with a detail screen per park. Each park is one YAML file.

## Data sources and rules

- Park data is collected **by hand** by the developer or community from the park's own site or by visiting. Do not import or bulk-copy data from other cable-park apps or directories.
- When an AI agent does this collection, follow the [`park-data-collection`](../.claude/skills/park-data-collection/SKILL.md) skill: official domain only (never aggregators or other wakeboard apps), never guess a vague/uncertain field (omit instead), and list the source URL(s) + fetch date in the PR description so a reviewer can verify before merging (not in the file, see [Keeping a park file tidy](#keeping-a-park-file-tidy)).
- Free-text `description` fields (park, cable, `opening.note`) follow [Docs/ParkDescriptions.md](ParkDescriptions.md): no em-dash, direct language, no hype words.
- Bundled parks live in `RpplCore/Sources/RpplCore/Resources/Parks/*.yaml`.
- User files in `<App Group>/Parks/*.yaml` (fallback `Documents/Parks/`) override bundled parks with the same `id`. Invalid files are skipped and logged.
- YAML stays the source of truth. The in-app editor writes the same format.

### In-app editor

- Parks tab `+` creates a park; park detail `…` menu → Edit changes one. `AppSettingsKey.parkEditorEnabled` (default on) hides the editor entry points.
- A **new park** is walked through page by page (welcome, basics, contact and links, about, cables, opening times, prices, review). An **existing park** opens a list of the same pages to jump between. Only name and location are needed to save; empty pages are left out. The time zone sits under "Advanced"; `author`, `from`/`until` and `exceptions` are kept when saving but not edited in the app.
- **Drafts:** every change is written to `<App Group>/ParkDrafts/<id>.json` (`ParkEditDraft`, `ParkDraftStore`), also when the app goes to the background. A draft may be incomplete (no name, no location, half-filled lists). Drafts show on top of the Parks list; closing with unsaved changes asks: save as draft, discard, or keep editing. Saving the park deletes the draft.
- **Lists** (facilities, cables, hours, blocks, prices, links, dates) always end in an empty row. Typing in it makes it a real row and a new empty one appears; a real row left empty when the keyboard goes away is removed; swipe deletes (cables, hours, blocks, prices and links ask first).
- **Text** typed in the editor is cleaned by `ParkText`: control characters, bidi overrides and private-use code points go, any script, RTL and emoji stay, each field has a length limit. Description and notes accept light markdown (italic, bold, lists); headings and HTML tags are stripped. Markdown is stored as typed and not rendered yet.
- **Location** is set on a map with a crosshair; the time zone follows the location (MapKit) until picked by hand. Cables are traced the same way; the shape question (full size or 2.0) is only asked when the cable has none yet, and the direction of a loop follows the traced order.
- **Opening times:** months and days are switch lists (`ParkDaySelection` stores the shortest selector). Block ids are assigned by the editor and `numbered` is not shown. **No rules or blocks filled in means unknown**, not closed (`ParkOpening.isScheduleKnown`).
- **Prices:** a name plus amount rows (currency menu, number, a "per" menu with an "Other" free text, a note). Similar prices are one name with several amounts.
- **Links:** Booking, Instagram, Facebook, YouTube (picked from the address) or a custom name; one link per name, a repeated name replaces the first. Shown on the contact page.
- Saved files are marked **Custom** (only a user file) or **Edited** (user file overriding a bundled park). A user file always wins over bundled data.
- An override stores `based_on_updated_at`, the bundled `updated_at` it was edited from, and `based_on_revision`, the bundled `history.count` at that point (catches a same-day bundled content change that `updated_at`'s day granularity can't). When the app later ships a newer `updated_at` or a longer `history`, the park shows **Update available** and asks: keep my version (bumps both) or use the app version (deletes the override). Always add a `history` entry when editing a bundled park file, even without changing `updated_at`, so existing overrides pick up the fix.
- `author` credits whoever wrote or maintains the file (shown as "Credits" in the detail footer). Rppl is the default credit and is not shown, so bundled files leave `author` out.
- Share exports `<id>.yaml` through the share sheet. "Send to Rppl" opens a mail to rppl@dcsbl.nl with the YAML attached (falls back to the share sheet when Mail is not set up).

### Keeping a park file tidy

`scripts/validate_parks.py` enforces these in CI ([Docs/DevWorkflow.md](DevWorkflow.md#validate-parks-linux)).

- **Comments** only where they stop a reader from getting something wrong: an approximate pin, a water station far away, a direction that did not come from the park's site. At most 3 lines in a row, no URLs, no restating the schema. Sources go in the PR description and the `history` entry.
- **Leave out what the app ignores or hides:** `author: Rppl` (the default credit is not shown), `numbered` without `slots`, `hours_unknown`, and a rule `label` that only repeats its month ("September"; the month is already the heading).
- **A price name appears once**, with one option per amount (audience, season, gear, duration). **One link per kind.**
- **No em-dash or en-dash** anywhere, and no spaced hyphen used as a dash in `description` or `note` text. A range keeps a plain hyphen (`14:00-20:00`, `18 July-30 August`).
- **Past opening dates** (`dates`, `from`, `until`, exceptions) are accepted by the validator. Remove them when you tidy a file.
- **Tidying** without new information keeps `updated_at` (it is shown as "Last updated" and reads as freshness) but still adds a `history` entry, which is what makes overrides show "Update available".

## Schema (version 1)

Only `version`, `id`, `name` and `location` are required. Everything else may be omitted.

```yaml
version: 1
id: project7-rotterdam            # stable slug, unique
author: Jane Doe                  # optional credit; leave out for Rppl (the default, not shown)
based_on_updated_at: 2026-09-24   # optional, set on user overrides of bundled parks
based_on_revision: 1              # optional, set alongside based_on_updated_at (bundled history.count)
created_at: 2026-09-24
updated_at: 2026-09-24
history:
  - { date: 2026-09-24, description: initial }

name: Project 7 Cablepark Rotterdam
address: Kosboulevard 35, 3059 XZ Rotterdam
timezone: Europe/Amsterdam        # used to resolve "today"; default Europe/Amsterdam
location: { lat: 51.979207, lon: 4.573426 }
phone: 010 - 2600 110
email: info@project7cablepark.nl
website: https://www.project7cablepark.nl

cables:
  - name: Cable                   # optional ("Beginner", "Advanced", …)
    direction: cw                 # cw | ccw = "full size" (goes round), "2.0" = 2-point cable
    description: optional text
    length_m: 760                 # optional; wins over the length computed from points
    points:                       # optional; listed in travel order, first point is the start
      - { lat: 51.97933, lon: 4.57403 }
      - { lat: 51.98027, lon: 4.57763, start: true }   # explicit start(s) when needed

opening:
  booking: required               # required | optional | none
  numbered: true                  # with slots: false = blocks are plain start times (hourly), not "Block 3" (not shown in the editor)
  booking_minutes: [60, 120]      # optional: bookable per 1 or 2 hours
  note: free text
  rules:                          # drop-in / open windows
    - { months: [9], days: [weekdays], open: "14:00", close: "20:00" }
  slots:                          # fixed-start blocks
    - { id: "3", start: "14:00", end: "15:30" }
  exceptions:                     # optional one-offs on top of `rules`, see "Exceptions" below
    - { kind: closed, label: Wind, dates: ["2026-09-25"] }

prices:                           # a name with one or more amounts
  - name: Skis
    options:
      - { amount: "10", currency: EUR, per: hour }
      - { amount: "15", currency: EUR, per: "2 hours" }
  - name: Day pass
    options:
      - { amount: "38.50", currency: EUR, note: kids up to 15 }
      - { amount: "49.50", currency: EUR, note: adults }
  - name: Group discount
    options:
      - { amount: "-3", currency: EUR, per: person }   # negative = discount
links:   [{ kind: booking, url: "https://…" }, { kind: instagram, url: "https://…" }]   # `booking` shows a "Book online" button
facilities: [rental, bar]
description: optional text
wakesys: true                     # optional, default false — this park's booking system is Wakesys (shared by several parks)

# Optional: source for the estimated water temperature feature (opt-in, off by default; see below).
water_temperature: { provider: rws_nl, station_id: nieuwegein.lekkanaal }
```

### Prices

A price is a `name` with `options`: one entry per amount ("skis": €10 for 1 hour, €15 for 2 hours; "day pass": one amount per audience). `amount` is exact decimal text, signed (negative is a discount); a plain YAML number is read the same. `currency` is an ISO 4217 code. `per` is free text; `person`, `hour`, `day` and `session` are shown in the reader's language ("per hour"), anything else as written ("per season", "1,5 uur"). `note` says who or what the amount is for. The detail screen groups the amounts under the name and formats them in the reader's own number format (`€12,34` or `$12.34`). In the editor people type the amount (`12,34`, `1.234,56`, `12,-`, `-3`) and `ParkPriceParser` reads it. Times are stored as 24 hour `HH:mm` (or `sunset`), dates as `yyyy-MM-dd`.

### Opening rules and slots

Rules and slots share optional selectors, all of which must match a date:

| Field | Meaning |
|-------|---------|
| `months` | Month numbers 1–12 |
| `days` | `mon`…`sun`, `weekdays`, `weekend`, `daily` |
| `from` / `until` | Inclusive `yyyy-MM-dd`, for a change of hours from or until a date |
| `dates` | Explicit `yyyy-MM-dd` dates (holidays, special days); listed under their month |

`open` / `close` also accept `sunset` (see Exceptions).

- A park with **rules only** is drop-in: the Today section shows the open windows.
- A park with **slots only** offers each slot on the days it matches.
- A park with **both** offers a slot only when it fits completely inside an open window. Example: Project 7 in September on a weekday is open 14:00–20:00, so blocks 3–6 are available; on weekends 12:30–20:00 adds block 2.
- Several rules may match one day (for example a beginner hour inside the opening window); all are shown.
- No matching rule means closed. **No rules and no slots at all** means the hours are unknown: "Opening hours unknown", never filtered out by the Open filter.

### Display

- The opening-times card collapses rules into one entry per month, listing the specialities (weekend hours, beginner hour, …) as lines under it. The current month is highlighted.
- Today shows "Open from … to …", today's available blocks as chips and the current temperature and wind (WeatherKit at the park location; hidden when unavailable).
- Recurring special days (holidays) use a rule with `dates`; it appears as an extra line under the month of those dates. Unplanned openings, closures and events use `exceptions` instead.
- Today shows notices for the day's exceptions under the hours; a park detail with announced exceptions still ahead gets an "Upcoming changes" card. The list chip reads "Closed · <label>" when a labelled `closed` exception is the reason.
- Cables are called "full size" (`cw`/`ccw`) or "2.0". The map shows an arrow on each start point, pointing towards the next traced point.

### Exceptions

`opening.exceptions` holds announced changes that are not part of the regular schedule: extra opening hours, a closure for wind or maintenance, an event. The regular `rules` stay untouched; an exception sits on top of them for its dates only, and stops having any effect after them. Past entries are accepted and can stay until someone tidies the file.

```yaml
opening:
  exceptions:
    - { kind: hours, label: Extra opening hours, dates: ["2026-09-29"], open: "17:00", close: sunset }
    - { kind: closed, label: Wind, dates: ["2026-10-02"], note: Reopens on Saturday }
    - { kind: extra, label: Early start, from: "2026-10-05", until: "2026-10-09", days: [weekdays], open: "10:00", close: "12:00" }
    - { kind: event, label: Wake Battle, dates: ["2026-10-10"] }
```

| Field | Meaning |
|-------|---------|
| `kind` | Opaque string. `hours`: these are the hours on the matching dates, replacing the regular ones. `closed`: closed all day. `extra`: added next to the regular hours. `event`: notice only, open/closed does not change. Unknown kinds behave like `event`. |
| `label` | Short reason or name ("Extra opening hours", "Wind"), shown in the notice and the list chip. |
| `note` | Longer text. |
| `months`, `days`, `from`, `until`, `dates` | Same selectors as rules. **At least one of `from`, `until` or `dates` is required**; an exception without a date bound is ignored so a forgotten entry can never change every day. |
| `open`, `close` | `HH:mm` or `sunset`. Used by `hours` and `extra`. |

- Precedence per day: `closed` beats `hours` beats the regular rules. `extra` is added on top of either.
- `sunset` (also allowed in normal rules) is not calculated: it is just a name for 00:00 internally, so the park counts as open until the end of that day and closed after 00:00. The UI still says "sunset" ("Open from 17:00 to sunset"), never a clock time; `ParkTimeWindow.endsAtSunset` carries that. Blocks only count when they end before the close, so a `sunset` window offers every block up to 23:00.
- The Open date filter, the list chip, the Today card and (in dev builds) the arrival notification all read the same per-day schedule (`ParkSchedule.day`), so an exception is reflected everywhere. For a park without rules or slots, an `hours` or `closed` exception makes just that day known.
- The in-app editor keeps exceptions when saving but cannot edit them yet; add them in the YAML.
- Record the source (for example the park's Instagram story and the date you saw it) in the PR description. Exceptions from a story or post are announcements, not the park's regular schedule; do not fold them into `rules`.

### Water temperature (opt-in)

- Off by default (Settings → "Park water temperature"). When on, a park with a `water_temperature` source shows an estimated reading next to the weather row, and, in dev builds with park arrival notifications, the arrival notification includes it.
- `water_temperature.provider` is an opaque provider id: `rws_nl` (Rijkswaterstaat WaterWebServices — CC0-licensed Dutch government open data, `station_id` is a location code), `hic_be` (MOW-HIC KiWIS service — Flemish government open data for Belgium's navigable waterways), or `vmm_be` (VMM KiWIS service — Flemish government open data for Belgium's non-navigable waterways). Both Belgian providers share the same KiWIS REST API shape, just different hosts/databases; `station_id` for either is a KiWIS `ts_id`, not a station code. A new provider (another country's open-data API) is a new entry in `ParkWaterTemperatureProvider`'s fetcher registry (`Rppl/Parks/ParkWaterTemperatureProvider.swift`), not a schema or architecture change.
- Always the nearest official station's reading, not a sensor at the park — shown with an "Estimate near <station>, via <source>" caption. Some stations report infrequently (see `wetnwild-alphen`'s comment), so the reading can be from earlier in the season, not necessarily "now".
- `RpplCore` only defines the shape (`ParkWaterTemperatureSource`, `ParkWaterTemperature`, `ParkWaterTemperatureFetching`); the actual HTTP fetch, caching (max once per 4 hours per station) and failure backoff live in the `Rppl` app layer, mirroring `ParksWeatherProvider`.
- A reading older than 48 hours is treated as unavailable (`ParkWaterTemperatureProvider.maxReadingAge`) — a station that stopped reporting doesn't show a stale number. Unlike park weather's fail-open convention, the park screen shows an explicit "Not available" row whenever the setting is on and no fresh reading came back, whether the park has no `water_temperature` source at all, the fetch failed/timed out, or the latest reading is too old.

### Park arrival notifications (dev builds only)

- Not shipped. All of it — Settings toggle, Notifications permission row, explainer sheet, debug screen, region monitoring and the `Rppl/Notifications/` sources — is compiled only with the Swift compilation condition `PARK_ARRIVAL_NOTIFICATIONS`. It is set for the Debug configuration only (`SWIFT_ACTIVE_COMPILATION_CONDITIONS` in `Rppl.xcodeproj`), so Release, TestFlight and App Store builds do not contain it.
- The location usage description and `LEGAL.md` do not mention the feature while it is off. Re-add both before shipping it.
- `ParkArrivalPlanner` (which parks to monitor, cooldown) lives in `RpplCore` and is not flagged, so `ParkArrivalPlannerTests` keep running in every configuration.
- To try it on a device, run a Debug build and turn on Settings → "Notify on arrival".

### Wakesys badge

- `wakesys: true` marks a park whose booking system is Wakesys (several parks share the same booking platform, under their own accounts/subdomain). Optional, defaults to `false`/absent.
- Shown today only as a "Wakesys" chip on the park card and on the detail page's booking button — not used to filter or group parks yet.

### Cable length

`length_m` is used when present. Otherwise the length is computed from `points`; loop cables (`cw`, `ccw`) include the closing segment back to the first point, `"2.0"` cables count the traced line once. With neither, no length is shown.

### Visits

A logbook session counts as a visit to a park when its track center is within 750 m of the park pin or any traced cable point (`ParkListing.visitRadiusMeters`).
