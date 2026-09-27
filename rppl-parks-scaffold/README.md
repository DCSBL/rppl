# rppl-parks scaffold (staging area)

This directory is **not** part of the `rppl` app. It is staged content for the
CI validation workflow described in
[rppl#274](https://github.com/DCSBL/rppl/issues/274), written ahead of the new
public `rppl-parks` repo because that repo's bootstrap
([rppl#273](https://github.com/DCSBL/rppl/issues/273)) hasn't happened yet.

See the epic: [rppl#272](https://github.com/DCSBL/rppl/issues/272).

## What's here

```
.github/workflows/validate.yml   PR check: YAML lint + schema + sanity checks
.yamllint.yml                    yamllint config (matches the repo's flow-mapping house style)
schema/park.schema.json          JSON Schema mirroring RpplCore/Sources/RpplCore/Parks/ParkModels.swift + ParkOpening.swift
scripts/validate_parks.py        The validator the workflow runs
tests/fixtures/*.yaml            One valid + several deliberately-broken park files
tests/smoke_test.sh              Asserts each fixture passes/fails as expected
```

Verified against the app's real bundled seed data
(`RpplCore/Sources/RpplCore/Resources/Parks/*.yaml`) — all four pass schema +
sanity validation and yamllint as-is.

## Moving this into the real rppl-parks repo (once #273 bootstraps it)

1. Copy `.github/`, `.yamllint.yml`, `schema/`, `scripts/`, `tests/` to the
   root of `rppl-parks`.
2. Add the real `parks/*.yaml` seed data (from #273) alongside `schema/`.
3. Confirm `scripts/validate_parks.py` (no args) walks `parks/*.yaml` and
   `bash tests/smoke_test.sh` still passes.
4. Delete this scaffold directory from the `rppl` monorepo — its job is done
   once the workflow lives in `rppl-parks`.

## Keeping the schema in sync

`schema/park.schema.json` is hand-authored to mirror the Swift model. There is
no automated sync (no Swift toolchain in `rppl-parks`) — per #273, update both
by hand when `Park`/`ParkOpening` change in `RpplCore`.

## What the workflow checks

Per the issue: YAML lint, JSON-schema validation against
`schema/park.schema.json`, and sanity checks — duplicate `id`, lat/lon out of
range (including `(0, 0)` Null Island), a cable with fewer than 2 points, and
obvious placeholder/TODO text (`TODO`, `FIXME`, `TBD`, `lorem ipsum`,
`example.com`, etc.). This is the spam/junk filter ahead of `CODEOWNERS`
maintainer review — it does not replace that review.
