# Park data over the air

Park files reach the app in two ways: bundled in the build (`RpplCore/Sources/RpplCore/Resources/Parks/`) and, when the rider turns on **Info → Park data → Update park data** (default off), downloaded from the `parks-distribution` branch. No Rppl server is involved; the app talks to `raw.githubusercontent.com` only.

## Flow

1. A park change merges to `main`.
2. `.github/workflows/parks-distribution.yml` runs `scripts/ci/build_parks_distribution.py` and opens or updates a PR from `parks-distribution-auto` into `parks-distribution`. The PR holds the park YAMLs and a regenerated `manifest.json` (sha256 per file, `dataVersion` + 1).
3. **A human merges that PR.** That is the moment riders can receive the change.
4. The app (pull to refresh in Parks, once a day in the app, and in the background when a park widget is installed) fetches `manifest.json`, downloads only changed files, verifies the hashes, validates every park, and then switches over atomically (`ParkDataStore`). Any failure leaves the data in use untouched.

The first run creates `parks-distribution` from the current parks. Repo setting needed: Actions → General → "Allow GitHub Actions to create and approve pull requests".

## Layers

bundled < downloaded < the rider's own edits and custom parks. A bundled park that is a later revision than the downloaded one (a newer app) wins over the download. Edits based on an older version show the existing "Update available" badge.

## Manifest

`format`, `dataVersion`, `publishedAt` (UTC), `enabled`, `minAppSchema` / `maxAppSchema` (the `version` of the park files), and `parks[]` with `id`, `file`, `sha256`. A different `dataVersion` than the installed one installs, so reverting the branch rolls back.

- **Kill switch:** set `"enabled": false` in `manifest.json` on `parks-distribution`. Apps ignore downloaded data and show the bundled parks until it is `true` again. The CI build keeps the value.
- **Schema:** data needing a newer `Park.version` than the app knows shows "Update the app to get new park data". Bump the schema only together with an app release that reads it.
- **Integrity:** sha256 protects against corruption, not against someone who can push to the branch. There is no signing.

## Closing a park

Do not delete a park file. Set `permanently_closed: true`: it disappears from the list, map and widget picker, but old sessions can still reference it. A rider's own edit of the park still wins.

## Rider-facing rules

A manual refresh takes at least 1 s. Within 60 s of a successful real refresh it is faked (1 to 3 s, nothing downloaded). Errors show for 5 s. Background refresh runs at a fixed random time of day per installation and only with a park widget installed; iOS decides the actual moment.
