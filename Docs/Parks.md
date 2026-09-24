# Parks

The Parks tab lists cable parks (favorites first, then nearby or most visited) with a detail screen per park. Each park is one YAML file.

## Data sources and rules

- Park data is collected **by hand** by the developer or community from the park's own site or by visiting. Do not import or bulk-copy data from other cable-park apps or directories.
- Bundled parks live in `RpplCore/Sources/RpplCore/Resources/Parks/*.yaml`.
- User files in `<App Group>/Parks/*.yaml` (fallback `Documents/Parks/`) override bundled parks with the same `id`. Invalid files are skipped and logged.
- YAML stays the source of truth. The in-app editor writes the same format.

### In-app editor

- Parks tab `+` creates a park; park detail `…` menu → Edit changes one. Cables are traced by tapping a satellite or standard map. `AppSettingsKey.parkEditorEnabled` (default on) hides the editor entry points.
- Saved files are marked **Custom** (only a user file) or **Edited** (user file overriding a bundled park). A user file always wins over bundled data.
- An override stores `based_on_updated_at`, the bundled `updated_at` it was edited from. When the app later ships a newer `updated_at`, the park shows **Update available** and asks: keep my version (bumps `based_on_updated_at`) or use the app version (deletes the override).
- `author` credits whoever wrote or maintains the file (shown as "Credits" in the detail footer).
- Share exports `<id>.yaml` through the share sheet. "Send to Rppl" opens a mail to rppl@dcsbl.nl with the YAML attached (falls back to the share sheet when Mail is not set up).

## Schema (version 1)

Only `version`, `id`, `name` and `location` are required. Everything else may be omitted.

```yaml
version: 1
id: project7-rotterdam            # stable slug, unique
author: Rppl                      # optional credit
based_on_updated_at: 2026-09-24   # optional, set on user overrides of bundled parks
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
    direction: cw                 # cw | ccw = "full size" (goes round), 2d = 2-point "2.0" cable
    description: optional text
    length_m: 760                 # optional; wins over the length computed from points
    points:                       # optional; listed in travel order, first point is the start
      - { lat: 51.97933, lon: 4.57403 }
      - { lat: 51.98027, lon: 4.57763, start: true }   # explicit start(s) when needed

opening:
  booking: required               # required | optional | none
  numbered: true                  # false = blocks are plain start times (hourly), not "Block 3"
  booking_minutes: [60, 120]      # optional: bookable per 1 or 2 hours
  note: free text
  rules:                          # drop-in / open windows
    - { label: September, months: [9], days: [weekdays], open: "14:00", close: "20:00" }
  slots:                          # fixed-start blocks
    - { id: "3", start: "14:00", end: "15:30" }

prices:  [{ name: Day pass, price: "€25", note: optional }]
links:   [{ kind: booking, url: "https://…" }, { kind: instagram, url: "https://…" }]   # `booking` shows a "Book online" button
facilities: [rental, bar]
description: optional text
```

### Opening rules and slots

Rules and slots share optional selectors, all of which must match a date:

| Field | Meaning |
|-------|---------|
| `months` | Month numbers 1–12 |
| `days` | `mon`…`sun`, `weekdays`, `weekend`, `daily` |
| `from` / `until` | Inclusive `yyyy-MM-dd`, for a change of hours from or until a date |
| `dates` | Explicit `yyyy-MM-dd` dates (holidays, special days); listed under their month |

- A park with **rules only** is drop-in: the Today section shows the open windows.
- A park with **slots only** offers each slot on the days it matches.
- A park with **both** offers a slot only when it fits completely inside an open window. Example: Project 7 in September on a weekday is open 14:00–20:00, so blocks 3–6 are available; on weekends 12:30–20:00 adds block 2.
- Several rules may match one day (for example a beginner hour inside the opening window); all are shown.
- No matching rule means closed.

### Display

- The opening-times card collapses rules into one entry per month, listing the specialities (weekend hours, beginner hour, …) as lines under it. The current month is highlighted.
- Today shows "Open from … to …", today's available blocks as chips and the current temperature and wind (WeatherKit at the park location; hidden when unavailable).
- Special days (holidays) use a rule with `dates`; it appears as an extra line under the month of those dates. There is no closed-day rule or UI for them yet.
- Cables are called "full size" (`cw`/`ccw`) or "2.0" (`2d`). The map shows an arrow on each start point, pointing towards the next traced point.

### Cable length

`length_m` is used when present. Otherwise the length is computed from `points`; loop cables (`cw`, `ccw`) include the closing segment back to the first point, `2d` cables count the traced line once. With neither, no length is shown.

### Visits

A logbook session counts as a visit to a park when its track center is within 750 m of the park pin or any traced cable point (`ParkListing.visitRadiusMeters`).
