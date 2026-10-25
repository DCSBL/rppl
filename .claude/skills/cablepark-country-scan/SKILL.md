---
name: cablepark-country-scan
description: Find every cable park in one country by searching yourself, then add each park to the bundled park data via park-data-collection. Use when asked to cover a new country or region. Never use overview or listing pages, only each park's own site, only current and verifiable information.
---

# Cable park country scan

Finds all cable parks (wakeboard/waterski cable installations) in one country and adds the ones that qualify to `RpplCore/Sources/RpplCore/Resources/Parks/`. This skill covers **discovery and bookkeeping**. The per-park data work is done by [`park-data-collection`](../park-data-collection/SKILL.md), whose rules apply unchanged to every park found here.

## Rules

1. **Search yourself.** Run your own web searches per region, city and cable-park term in the local language and in English. Do not read, fetch or copy from overview pages: directories, "best cable parks in X" lists, aggregator and booking marketplaces, other wakeboard or cable-park apps, wikis, map listings, forum threads, tourism portals. A search result that is such a page is a signal to stop and search again, not a source. This keeps the data originally sourced and avoids copyright and licensing problems ([Docs/Parks.md](../../../Docs/Parks.md#data-sources-and-rules)).
2. **Scrape the park's own site.** Every fact comes from the park's own domain (the one its own social profile or email address points to). If you cannot tell whether a domain is the park's own, ask the user.
3. **Only reliable and current.** A park is added only when its own site shows it operates now: current-season hours or prices, a current-year date, or a recent post on its own pages. A site that is stale, parked, a "coming soon" page, or says the park is closed or sold is skipped and reported. Never guess a field: leave it out (`park-data-collection` rule 2).
4. **Nothing from memory.** Do not add a park, address, coordinate or price because you remember it. If it is not on a page you fetched this run, it does not go in.
5. **Provenance.** Every park's source URLs and fetch date (`yyyy-MM-dd`) go in the PR description, not in the YAML.

## Steps

1. **Know what exists.** List `RpplCore/Sources/RpplCore/Resources/Parks/*.yaml` (`id`, `name`, `website`, `address`) so you do not add a duplicate. A park already present is not re-collected here; if its data looks outdated, report it instead.
2. **Cover the country systematically.** Search per region/province/state and per larger city, in the local language (`kabelbaan`, `wakeboard cable`, `téléski nautique`, `Wasserskianlage`, `wakepark`, …) and English. Keep a scratch list (scratchpad, not the repo) with candidate name, place and the park's own URL. Search until new queries stop turning up new parks. Include 2-point (2.0) and full-size cables; skip pure towboat schools, rental-only shops and indoor/trampoline parks.
3. **Qualify each candidate** on its own site: is it a cable park, is it operating now (rule 3), and is it in the target country. Drop and note the rest with the reason.
4. **Report the candidate list to the user before collecting** if the number is large (roughly 10+), or any domain is uncertain: name, place, own URL, qualifies yes/no. Otherwise continue.
5. **Collect each qualifying park** by following `park-data-collection` end to end (schema, `languages`, descriptions per [Docs/ParkDescriptions.md](../../../Docs/ParkDescriptions.md), `history` entry, `updated_at`, block-style YAML). Country specifics:
   - `id`: lowercase slug `<name>-<place>` (`kempervennen-westerhoven`), unique and stable.
   - `timezone` of the park's country (the app derives the country from it; there is no country field). Leave the default only for `Europe/Amsterdam`.
   - Price `currency`: ISO 4217 code of the amounts as the site shows them, per option.
   - `languages`: main language first, then English, Dutch, and every other language the park's site is offered in, with a variant of each free `per` / `note` ([Docs/Parks.md](../../../Docs/Parks.md#languages)). Say in the PR which variants are the park's own wording and which are faithful translations.
   - `opening.source_url`: the park's own page with opening hours, when one exists. Then add an entry for it in `ops/hours-watch/markers.yaml` following the comments there (a season heading or date range the park rewrites when hours change). Skip the marker when no stable text exists.
   - `water_temperature`: only via `scripts/find-water-temperature-station.py`, and only where a provider exists for that country ([Docs/Parks.md](../../../Docs/Parks.md)). Otherwise leave it out.
6. **Validate.** `python3 scripts/validate_parks.py`, `python3 scripts/format_parks.py --check <files>`, `pre-commit run`. Fix what they report. macOS-only checks run in CI.
7. **PR.** One PR per country, title `parks(feat): Add <country> cable parks` (English, per [contributions/agent.md](../../../contributions/agent.md), PR template). The body lists, per park, the source URLs and fetch date, plus a short list of skipped candidates with the reason, and any field left out for lack of a confirmed source.

## Stop and ask the user when

- A domain may not be the park's own, or two sources disagree (hours, address).
- A park's status is unclear (maybe closed, maybe seasonal with no current info).
- A site cannot be fetched (blocked, JS only, image-only hours). Say so; do not fall back to an overview page.

## Out of scope

Editing bundled parks' `id`, cable `points` without a clear source map, trick/detection data, and refreshing existing parks (that is `park-data-collection` plus the hours-watch scan).
