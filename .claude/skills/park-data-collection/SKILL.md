---
name: park-data-collection
description: Collect or refresh one cable park's YAML entry (schema in Docs/Parks.md) from the park's own official website. Use when adding a new park or updating an existing one. Domain-restricted (official site only, never aggregators or other wakeboard apps) and no-guessing (omit anything not confirmed on the source) — see AGENTS.md hard constraints.
---

# Park data collection

Formalizes the manual process described in [Docs/Parks.md](../../../Docs/Parks.md#data-sources-and-rules):
scan one park's own official site and hand-pick the fields for its YAML file. Three hard rules,
non-negotiable:

1. **Official domain only.** Fetch only pages under the park's own domain (the site the park itself
   publishes to, e.g. linked from its Instagram bio or the domain in its email address). Never fetch or
   copy data from aggregators, directories, or other wakeboard/cable-park apps — this keeps data
   originally sourced and avoids copyright/licensing issues. If you're not sure a domain is the park's
   own, ask the user rather than guessing.
2. **Never guess or fabricate a vague/uncertain field.** If a value isn't clearly stated on a fetched
   page, omit the field — don't approximate, infer from a template, or carry over a typical value from
   another park. Per the schema, only `version`, `id`, `name`, `location` are required; everything else
   is optional and safe to leave out.
3. **Record provenance.** Every run must leave a trail a human reviewer can check before merging: which
   URL(s) were fetched and when.

## Steps

1. **Identify the target park and its official domain.** If the user gives a URL, use it. If they only
   give a park name, find the official domain (e.g. via the park's own social profiles) — do not fall
   back to a directory/aggregator page to shortcut this.
2. **Fetch official pages only**: home, hours/pricing, contact, about. Use whatever the site actually
   publishes — don't assume a page (e.g. a dedicated "hours" page) exists if it doesn't.
3. **Map fetched content to the schema in [Docs/Parks.md](../../../Docs/Parks.md#schema-version-1)**:
   `name`, `address`, `location` (dock coordinate), `phone`, `email`, `website`, `cables` (name/direction/
   description; only add `points` if the site's own map/satellite view is clear enough to trace —
   otherwise leave `points` out), `opening` (`rules`/`slots`), `prices`, `links`, `facilities`,
   `description`. Leave out anything not directly confirmed by the fetched pages. Write any free-text
   `description` (park, cable, `opening.note`) per
   [Docs/ParkDescriptions.md](../../../Docs/ParkDescriptions.md): no em-dash/hyphen-as-dash, direct
   language, no hype words.
4. **Do not fill `water_temperature`** unless you have confirmed an appropriate official station for
   that park's water body — this is a separate, deliberate lookup, not something to infer from location.
   Use `scripts/find-water-temperature-station.py <lat> <lon>` (the park's `location`) to query the
   Rijkswaterstaat WaterWebServices catalog and find the nearest station that still reports — many
   geographically-nearest "zwemwater" stations stopped reporting years ago, so don't just pick the
   closest one by distance. The script prints the `water_temperature:` YAML line to use; still add the
   provenance comment (station, distance, why closer ones were skipped) by hand.
5. **Write or update** `RpplCore/Sources/RpplCore/Resources/Parks/<id>.yaml`, following the existing file
   layout (see any current file as a formatting example).
6. **Record provenance directly in the file**: add or update a leading comment listing each source URL
   fetched and today's date (`yyyy-MM-dd`), and append a `history` entry describing what changed. Set
   `updated_at` to today's date.
7. **Stop and ask** the user before finalizing whenever a field is ambiguous (conflicting hours on
   different pages, an unclear dock location, etc.) instead of picking one silently.

## Explicitly out of scope

- Trick/taxonomy or detection-threshold data — unrelated to this skill.
- Cable trace `points` when no source map/satellite view is good enough to trace confidently — leave
  `points` out rather than estimating from an address.
- Editing bundled parks' `id` — treat `id` as a stable slug once assigned.
