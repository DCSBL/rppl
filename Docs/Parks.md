# Parks

The Parks tab lists cable parks (favorites first, then nearby or most visited) with a detail screen per park. Each park is one YAML file.

## Data sources and rules

- Park data is collected **by hand** by the developer or community from the park's own site or by visiting. Do not import or bulk-copy data from other cable-park apps or directories.
- Bundled parks live in `RpplCore/Sources/RpplCore/Resources/Parks/*.yaml`.
- User files in `<App Group>/Parks/*.yaml` (fallback `Documents/Parks/`) override bundled parks with the same `id`. Invalid files are skipped and logged.
- YAML stays the source of truth. Later, in-app editing and remote updates write the same format.

## Schema (version 1)

Only `version`, `id`, `name` and `location` are required. Everything else may be omitted.

```yaml
version: 1
id: project7-rotterdam            # stable slug, unique
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
    direction: cw                 # cw | ccw | 2d (unknown values round-trip)
    description: optional text
    length_m: 760                 # optional; wins over the length computed from points
    points:                       # optional; first point is the start
      - { lat: 51.97933, lon: 4.57403 }
      - { lat: 51.98027, lon: 4.57763, start: true }   # explicit start(s) when needed

opening:
  booking: required               # required | optional | none
  note: free text
  rules:                          # drop-in / open windows
    - { label: September, months: [9], days: [weekdays], open: "14:00", close: "20:00" }
  slots:                          # fixed-start blocks
    - { id: "3", start: "14:00", end: "15:30" }

prices:  [{ name: Day pass, price: "€25", note: optional }]
links:   [{ kind: instagram, url: "https://…" }]
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

- A park with **rules only** is drop-in: the Today section shows the open windows.
- A park with **slots only** offers each slot on the days it matches.
- A park with **both** offers a slot only when it fits completely inside an open window. Example: Project 7 in September on a weekday is open 14:00–20:00, so blocks 3–6 are available; on weekends 12:30–20:00 adds block 2.
- Several rules may match one day (for example a beginner hour inside the opening window); all are shown.
- No matching rule means closed.

### Cable length

`length_m` is used when present. Otherwise the length is computed from `points`; loop cables (`cw`, `ccw`) include the closing segment back to the first point, `2d` cables count the traced line once. With neither, no length is shown.

### Visits

A logbook session counts as a visit to a park when its track center is within 750 m of the park pin or any traced cable point (`ParkListing.visitRadiusMeters`).
