# Dev workflow

## Where to run checks: GitHub first

The repo is public, so GitHub runners (Linux and macOS) are free. Do not burn local time on what CI already does.

- **Already in a GitHub workflow** (Core tests, coverage floor, `RpplTests`, UI tests, `xcodebuild` build, pre-commit): push and let CI run it. Run locally only to debug a failure CI reported.
- **Automatable but not covered yet** (a manual check you would repeat): turn it into a test (Core Swift Testing or a UI test) and/or a workflow, and commit that with the change. Do not leave it as a local ritual.
- **Local only**: what needs a physical device or account (HealthKit, Watch Connectivity, real sensors) and the fast commit hooks.

## Install (once)

Preferred (Homebrew):

```bash
brew install pre-commit swiftlint codespell
pre-commit install
```

If Homebrew is not writable, user-local install also works:

```bash
python3 -m pip install --user pre-commit codespell
# Ensure ~/Library/Python/*/bin is on PATH
export PATH="$HOME/Library/Python/3.9/bin:$PATH"

# SwiftLint: brew, or portable binary into tools/bin/swiftlint
pre-commit install
```

`pre-commit install` installs both git `pre-commit` and `pre-push` hooks (see `default_install_hook_types` in `.pre-commit-config.yaml`). Re-run after pulling this change if hooks were installed earlier.

## What runs on commit

Fast checks only — commit is blocked if any fail:

1. Basic file hygiene (trailing whitespace, YAML/JSON, merge conflict markers)
2. **codespell**
3. **Format `.xcstrings`** like Xcode (`scripts/format-xcstrings.py` — space before `:`, multi-line empty objects). Stops whole-catalog phantom diffs when Xcode rewrites a catalog after an agent/script edit.
4. **SwiftLint** (`--strict`, config in `.swiftlint.yml`)

Manual catalog format (all catalogs, or specific paths):

```bash
python3 scripts/format-xcstrings.py --all
python3 scripts/format-xcstrings.py --check --all
python3 scripts/format-xcstrings.py Rppl/Localizable.xcstrings
```

## What runs on push

Heavy gate — **only if the push includes build-related files** (Swift, plist, entitlements, Xcode project/schemes, `Package.swift` / `Package.resolved`, `.xcassets`, or `scripts/git-hooks/xcode-gate.sh`). Docs, YAML, and other scripts/helpers skip this.

When it runs, push is blocked if any fail. **xcode-gate** (`scripts/git-hooks/xcode-gate.sh`) then:

1. **`swift test` in `RpplCore` with the coverage floor** (`scripts/check-core-coverage.py`, see [Coverage floor](#coverage-floor)) — skipped if Core sources/tests/`Package.swift`, the coverage baseline and the local Swift/Xcode toolchain match the last successful run (content fingerprint of tracked files, not a time TTL). Dirty working-tree edits count, so `make gate` does not skip stale.
2. **`xcodebuild build`** for `Rppl` (iOS Simulator; embeds Watch) — skipped if app/Watch/project/Core *sources* match the last successful build. Changing only `RpplCore/Tests` does not rebuild the apps.
3. **`xcodebuild analyze` is not part of push.** It is slow and mostly overlaps `build`. Use `make check` (or `XCODE_GATE_ANALYZE=1`) when you want it.

Stamps live in `.git/rppl-xcode-gate/` (shared across worktrees of the same clone). Toolchain (`xcodebuild -version` / `swift --version`) is part of the key, so an Xcode upgrade rebuilds.

Manual gates:

```bash
make gate          # same as pre-push (cache + no analyze)
make check         # full: ignore cache, tests + build + analyze
make test-core     # RpplCore swift test only
make coverage      # Core tests + coverage floor (what the gate runs)
# or
pre-commit run --all-files --hook-stage pre-push
# (also: pre-commit run --all-files for commit-stage hooks)
```

Force a rebuild without analyze: `XCODE_GATE_NO_CACHE=1 make gate`.

## Coverage floor

`RpplCore` coverage may not go down. [`RpplCore/coverage-baseline.json`](../RpplCore/coverage-baseline.json) records the numbers and [`scripts/check-core-coverage.py`](../scripts/check-core-coverage.py) enforces them. It runs `swift test --enable-code-coverage` and measures `RpplCore/Sources/RpplCore` only, so well-covered tests cannot inflate the figure.

| Rule | Fails when |
|------|------------|
| Total | line or function coverage is more than `tolerance` (0.2 points) below the baseline |
| Critical files | a file in the baseline's `critical` list (session store, transfer, import, motion frames, detection, ...) gains more than `criticalMissedLinesAllowed` (2) uncovered lines |

The baseline only ratchets up. After improving coverage, run `make coverage-update` and commit the new file. Lowering a value needs `python3 scripts/check-core-coverage.py --update --allow-lower` and a reason in the PR. New code in a critical file needs tests in the same PR.

It runs in the [macOS CI](#macos-ci) Tests job, and locally in the pre-push `xcode-gate` and `make coverage`. Branch protection is not available on this private repo, so a PR is green or red by eye; do not merge red. Coverage shows what code runs, not what is asserted: keep tests that fail when the behavior breaks (flip the fix back and watch the test go red).

## Escape hatches (emergency only)

- Skip heavy gate on push: `SKIP=xcode-gate git push ...`
- Skip all hooks: `git commit --no-verify` / `git push --no-verify` (do not use as normal workflow)

## GitHub Actions

### PR checks (Linux)

Workflow: [`.github/workflows/pr-checks.yml`](../.github/workflows/pr-checks.yml).

On every PR targeting `main`, a GitHub-hosted `ubuntu-24.04` runner runs:

1. **pre-commit** — same **commit-stage** hooks (hygiene, codespell, SwiftLint, legal sync).

RpplCore `swift test` runs in its own workflow, see [Core tests (Linux)](#core-tests-linux).

`xcodebuild` runs in the separate [macOS CI](#macos-ci) workflow.

### macOS CI

`.github/workflows/macos-ci.yml` (free macOS runners while the repo is public) on every PR to `main` and push to `main`: **Tests** (release script tests, Core `swift test` with the coverage floor, `RpplTests` on an iOS Simulator) and **Build** (dry-run `xcodebuild build` of the `Rppl` scheme, embeds Watch + widgets, no signing). Compiler warnings and errors become PR annotations via `.github/xcode-problem-matcher.json` (GitHub shows at most 10 per step); full logs are `tests-log` / `build-log` artifacts. **UI tests** (`RpplUITests`: tabs, logbook list/detail, add, swipe-delete, parks search, season charts hidden at 3 and shown at 18 sessions) run as a third job (which also uploads the screenshots as an artifact and links them in a PR comment) on an iPhone Simulator against a seeded mock logbook: launch argument `-rpplUITest` (Debug builds only) makes `Rppl/App/UITestFixtures.swift` wipe the phone store, seed one tracked (the bundled Watch session, relabelled as a Project 7 wakeboard day) and three manual sessions and freeze `AppClock` at Sat 15 Aug 2026 12:30 (`-rpplUITestSessions N` swaps that for the tracked session plus N-1 generated manual ones, 0 = empty logbook; `-rpplUITestNow <epoch>` freezes another moment, e.g. winter for closed parks). Park favourites and the satellite map style are set through their UserDefaults keys as launch arguments (`-rppl.favoriteParkIDs "(id, id)"`, `-rppl.mapUsesSatellite YES`). `RpplScreenshotTests` has one scenario per screen set: logbook with 0, 3 and 18 sessions, tracked and manual session detail, parks open, closed, favourites, map, satellite and park detail. `release-screenshots.yml` runs `RpplScreenshotTests` on release publish (or manually with a tag) and adds the PNGs to the release assets and description. The Watch has its own target, `RpplWatchUITests` (scheme `RpplWatch`, a fourth job on an Apple Watch Simulator, same screenshot artifact and PR comment with a `watch-` name): `-rpplUITest` (Debug only) makes `RpplWatch/App/UITestFixtures.swift` wipe the Watch store, seed three tracked Project 7 wakeboard sessions (the bundled example, dates rebased, new session ids) and freeze `AppClock`; `-rpplUITestSummary` also shows the end-of-session summary. `RpplWatchScreenshotTests` covers the start page, sync page, logbook list, session detail and end summary; live recording and HealthKit are not tested. Release screenshots run it too and upload the PNGs with a `watch-` prefix (`iphone-` for the phone). Release builds stay in Xcode Cloud. If the runners become paid, drop this workflow; nothing else depends on it.

- Uses `fetch-depth: 0` so `--from-ref` can see base and head SHAs.
- Caches `~/.cache/pre-commit` and the SwiftLint Linux binary.
- Runs `pre-commit run --from-ref <base> --to-ref <head>` so hooks only see PR-changed files.
- SwiftLint install is a **step-level** skip when the PR has no matching paths. The job always reports a status, so you can mark **`pre-commit`** as a required check without skipped-job merge blocks.
- Hooks with no matching files are skipped by pre-commit (exit 0).

To enforce: GitHub → Settings → Branches → Branch protection (or ruleset) for `main` → require status checks **`pre-commit`** and **`RpplCore tests (Linux)`**.

### Core tests (Linux)

Workflow: [`.github/workflows/core-tests.yml`](../.github/workflows/core-tests.yml).

On every PR targeting `main`, on every push to `main` (a merge that breaks `main` shows red before you tag a release) and on manual dispatch, a GitHub-hosted `ubuntu-24.04` runner runs `cd RpplCore && swift test` inside the official `swift:6.2-noble` container, as the non-root runner user (the store tests inject failures with `chmod 000`, which root ignores). The toolchain comes with the image; there is no separate Swift install step. Required-check friendly: no `paths:` filter, so it always reports a status. Check name: **`RpplCore tests (Linux)`**.

A second job, **`Test summary`**, runs after the tests (also when they fail) and feeds the raw `swift test` log to [`scripts/ci/summarize_swift_test.py`](../scripts/ci/summarize_swift_test.py). It writes the result to the job summary and keeps **one sticky comment** on same-repo PRs, updated on every push: the number of tests, and when any fail, a table of the failed tests with file:line and the issue text (or the compiler errors when the build fails). The test job itself stays read-only; only the report job has `pull-requests: write`. Do not make `Test summary` a required check: it is best-effort. Tests for the script: `python3 -m unittest discover -s scripts/ci -p 'test_*.py'`.

Reproduce locally without a Linux machine (needs Docker; drop `--user` only if you accept the permission tests failing):

```bash
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/work -w /work/RpplCore swift:6.2-noble swift test
```

What this does **not** cover: the coverage floor (`make coverage`; Linux coverage numbers differ from Xcode's), the Apple-only code paths below, `xcodebuild`, and the iOS / watchOS targets.

**Keeping Core buildable on Linux.** Core must compile with `swift build` on Linux. Where an Apple-only API is unavoidable it sits behind `#if canImport(...)`, and the Apple build path stays the real implementation:

| Apple API | Linux handling |
|-----------|----------------|
| `Compression` (`COMPRESSION_ZLIB`) | `Platform/RawDeflate.swift`: same raw DEFLATE via system zlib (`CZlib` system library target, Linux only; needs `zlib1g-dev`) |
| `OSLog` | `Platform/LoggerShim.swift`: no-op `Logger` |
| `String(localized:bundle:)` | `Platform/LocalizationShim.swift`: returns the English key |
| `FormatStyle` / `MeasurementFormatter` (`DistanceFormat`, `EnergyFormat`, `TemperatureFormat`) | compiled out on Linux, and so are their tests |
| App Group `containerURL` | `nil` on Linux |
| `URLSession` | `import FoundationNetworking` |

Tests that need those Apple-only paths run only in Xcode / `xcode-gate`.

### Validate parks (Linux)

Workflow: [`.github/workflows/parks-validate.yml`](../.github/workflows/parks-validate.yml).

Spam/junk filter for changes to `RpplCore/Sources/RpplCore/Resources/Parks/*.yaml`. Only runs when park data, the schema, the validator or formatter script, or the yamllint config change. Steps:

1. **YAML lint** — `yamllint --config-file .yamllint.yml RpplCore/Sources/RpplCore/Resources/Parks/` (relaxed house-style config: long lines and no `---` document start are normal for hand-authored park files).
2. **Schema + sanity validation** — `python3 scripts/validate_parks.py` against [`schema/park.schema.json`](../schema/park.schema.json) (hand-kept in sync with `ParkModels.swift` / `ParkOpening.swift`), plus sanity checks: duplicate `id`, out-of-range or `(0, 0)` coordinates, a cable with fewer than 2 points, obvious placeholder/TODO text. It also enforces the house rules in [Parks.md](Parks.md#keeping-a-park-file-tidy): native block-style YAML (JSON-like `{ }` / `[ ]` fail; `python3 scripts/format_parks.py <file>` converts a file in place, `--check` only reports), no em/en dashes or dash-like hyphens in copy, no dead data (`author: Rppl`, `numbered` without slots, `hours_unknown`, month-name rule labels), one price per name and one link per kind, a variant of every free `per` / `note` for each of the park's `languages`, and short comments without URLs. Past opening dates are accepted.

This does not replace human review of park data (sourcing, accuracy) — see the `park-data-collection` skill and its no-guessing/domain-restricted rules.

Fixtures + smoke test: `scripts/parks-tests/` (`bash scripts/parks-tests/smoke_test.sh` asserts each fixture passes/fails as expected and that `format_parks.py` turns `fixtures/flow-style.yaml` into `expected/flow-style.yaml` — run it after touching the schema, the validator or the formatter).

## Xcode Cloud

Xcode Cloud only builds **releases**: publishing a GitHub release creates a tag, the **Release branch** GitHub workflow pushes `release/X.Y.Z` to the tagged commit, and the **Release** workflow archives that branch and sends it to TestFlight internal (one Build Group per version). Merges to `main` and PRs build nothing there; tests run on GitHub ([PR checks](#pr-checks-linux), [Core tests](#core-tests-linux), also after each merge), in the local push gate, and once more on the tagged commit before a release archive. Setup, the release steps and promotion to external TestFlight / the App Store (manual, in App Store Connect): [Release.md](Release.md).

The older **Nightly TestFlight** and **PR / Core tests** workflows are retired (they spent the free compute hours). Nightly is gone and `Test - PR` is deactivated in App Store Connect; keep it that way (or delete it).

[`ci_scripts/ci_post_clone.sh`](../ci_scripts/ci_post_clone.sh) runs after clone in every Xcode Cloud build. It requires a `release/X.Y.Z` branch (`CI_BRANCH`) or `CI_TAG`, so any other start fails immediately instead of archiving. Otherwise it runs [`scripts/ci/prepare_release.py`](../scripts/ci/prepare_release.py) and then the release script tests and `swift test` for `RpplCore`, so a failing test stops the build before the archive ([Release.md](Release.md#what-the-build-does)).

Dry-run the failure path locally (no tag, exit 1) or a tag against a throwaway worktree (see [Release.md](Release.md#what-the-build-does)):

```bash
CI_PRIMARY_REPOSITORY_PATH=$PWD bash ci_scripts/ci_post_clone.sh; echo "exit=$?"
```

### RpplCore scheme

Xcode's auto-generated `RpplCore` scheme only builds the library, so `xcodebuild test` fails with "There are no test bundles available to test". The shared scheme in `RpplCore/.swiftpm/xcode/xcshareddata/xcschemes/RpplCore.xcscheme` (whitelisted in `.gitignore`) adds `RpplCoreTests` to its Test action. Run Core tests through xcodebuild locally:

```bash
cd RpplCore && xcodebuild test -scheme RpplCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Notes

- Commit stays light (hygiene + spell + lint). First push after app/Core source changes still pays for `xcodebuild`; later pushes with the same inputs skip it. Core-test-only pushes skip the app build.
- SwiftLint starts lenient; tighten `.swiftlint.yml` over time.
- Unit tests live primarily in `RpplCore` (`swift test`). Keep app targets thin wrappers around Core logic.

## Device pair: one Cmd+R (Watch + iPhone)

WatchConnectivity only pairs apps when IDs match Apple’s rule:

| Role | Bundle ID (dev) |
|------|-----------------|
| iPhone | `nl.dcsbl.rppl` |
| Watch | `nl.dcsbl.rppl.watchkitapp` |
| Companion key | Watch `WKCompanionAppBundleIdentifier` = iPhone ID |

**Preferred (install both, debug Watch):**

1. Scheme **RpplWatch**.
2. Destination = **iPhone 16 Pro + Ultra 3** (paired destination, not Watch alone).
3. Cmd+R — Xcode installs/launches companion iPhone app + Watch app; debugger attaches to Watch.
4. Leave iPhone app open (or reopen from Home Screen). Both should show Connected / green when reachable.

**Phone-first (install both, debug iPhone):**

1. Scheme **Rppl** → destination = physical iPhone → Cmd+R (Embed Watch Content installs Watch app).
2. On Watch: open **Rppl** (or Cmd+R **RpplWatch** after first install).
3. Optional second debugger: **Debug → Attach to Process** → other app (Xcode usually stops the prior debug session if you Cmd+R the other scheme).

**If iPhone still says “Watch app missing”:**

1. Delete **Rppl** from iPhone **and** Watch (old wrong Watch ID / non-embedded install won’t upgrade in place).
2. Prefer scheme **Rppl** → physical iPhone → Cmd+R once (must install iPhone `.app` that contains `Watch/RpplWatch.app`).
3. Then scheme **RpplWatch** → paired destination → Cmd+R (or open Watch app manually).
4. iPhone **Watch** app → My Watch → Rppl → **Show App on Apple Watch** = on.
5. Confirm Ultra is the active paired Watch for that iPhone.

## Dev variant: clean install next to the real one

The real install (`nl.dcsbl.rppl`) holds real sessions. To test first-run onboarding, permissions, or an empty logbook without touching it, build the **Dev** configuration: a second app (same name "Rppl", orange icon) with its own bundle ids, App Group, and iCloud container. Both live on the same iPhone and Watch.

| | Prod | Dev |
|---|------|-----|
| iPhone | `nl.dcsbl.rppl` | `nl.dcsbl.rppl.dev` |
| Watch | `nl.dcsbl.rppl.watchkitapp` | `nl.dcsbl.rppl.dev.watchkitapp` |
| App Group | `group.nl.dcsbl.rppl` | `group.nl.dcsbl.rppl.dev` |
| iCloud container | `iCloud.nl.dcsbl.rppl` | `iCloud.nl.dcsbl.rppl.dev` |

How it is wired: the `Dev` build configuration (copy of Debug, compile flag `RPPL_DEV`) sets `RPPL_APP_GROUP_ID` and `RPPL_ICLOUD_CONTAINER` at project level. Entitlements and `Info.plist` read those settings; `AppConstants.appGroupID` / `iCloudContainerIdentifier` read the Info.plist keys `RpplAppGroupID` / `RpplICloudContainerID` and fall back to prod when absent. The Watch Debug tab (detection simulation, screen size) and debug discard are compiled to show only under `RPPL_DEV`. Plist keys do not take build settings, so the Dev iCloud folder name lives in `Rppl/Info-Dev.plist` (Dev uses it instead of `Rppl/Info.plist`); release builds declare only the prod container.

**One-time setup** (Apple Developer portal, or let Xcode automatic signing create it on the first Dev build):

1. App IDs `nl.dcsbl.rppl.dev` and `nl.dcsbl.rppl.dev.watchkitapp`, App Group `group.nl.dcsbl.rppl.dev`, iCloud container `iCloud.nl.dcsbl.rppl.dev`.
2. Capabilities as prod: HealthKit, WeatherKit, iCloud Documents. The Watch App ID also needs the shallow depth and pressure entitlement; check that it is granted for the new ID first, it is the likeliest blocker.

**Use**

1. Scheme **RpplWatch Dev** (or **Rppl Dev**), paired iPhone + Watch destination, Cmd+R. Same flow as [Device pair](#device-pair-one-cmdr-watch--iphone).
2. Fresh onboarding: delete the orange-icon Rppl from iPhone and Watch, reinstall. Prefs and permissions start empty.
3. Empty logbook too: Dev iCloud data survives a reinstall. Clear it in Settings → Apple Account → iCloud → Manage Storage → Rppl Dev (the Dev iCloud folder name), or delete the folder in Files → iCloud Drive → Rppl Dev.
4. Log real sessions only with the prod app.

**Limits**

- Apple Health is shared: Dev workouts show up next to real ones in Health and Fitness. Delete them there. Health permission prompts are per app and still appear fresh.
- Dev is a local Xcode install only. The Release workflow (tag → Xcode Cloud → TestFlight) builds prod and never the Dev configuration.
- The Dev iCloud container cannot see prod sessions. To test the import picker, copy a session folder into Files → Rppl Dev → Sessions.
- Unsent Watch sessions are lost when you delete the Watch app (see hard constraint 2); use the Dev app for throwaway data only.
