# Dev workflow

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

It runs locally only: in the pre-push `xcode-gate` and in `make coverage`. Nothing on GitHub enforces it (branch protection is not available on this private repo), so a PR is green or red by eye; do not merge red. Coverage shows what code runs, not what is asserted: keep tests that fail when the behavior breaks (flip the fix back and watch the test go red).

## Escape hatches (emergency only)

- Skip heavy gate on push: `SKIP=xcode-gate git push ...`
- Skip all hooks: `git commit --no-verify` / `git push --no-verify` (do not use as normal workflow)

## GitHub Actions

### PR checks (Linux)

Workflow: [`.github/workflows/pr-checks.yml`](../.github/workflows/pr-checks.yml).

On every PR targeting `main`, a GitHub-hosted `ubuntu-24.04` runner runs:

1. **pre-commit** — same **commit-stage** hooks (hygiene, codespell, SwiftLint, legal sync).

RpplCore `swift test` runs in its own workflow, see [Core tests (Linux)](#core-tests-linux).

It does **not** run `xcode-gate` / `xcodebuild` on GitHub (macOS + Xcode only).

- Uses `fetch-depth: 0` so `--from-ref` can see base and head SHAs.
- Caches `~/.cache/pre-commit` and the SwiftLint Linux binary.
- Runs `pre-commit run --from-ref <base> --to-ref <head>` so hooks only see PR-changed files.
- SwiftLint install is a **step-level** skip when the PR has no matching paths. The job always reports a status, so you can mark **`pre-commit`** as a required check without skipped-job merge blocks.
- Hooks with no matching files are skipped by pre-commit (exit 0).

To enforce: GitHub → Settings → Branches → Branch protection (or ruleset) for `main` → require status checks **`pre-commit`** and **`RpplCore tests (Linux)`**.

### Core tests (Linux)

Workflow: [`.github/workflows/core-tests.yml`](../.github/workflows/core-tests.yml).

On every PR targeting `main` (and on manual dispatch), a GitHub-hosted `ubuntu-24.04` runner runs `cd RpplCore && swift test` inside the official `swift:6.2-noble` container, as the non-root runner user (the store tests inject failures with `chmod 000`, which root ignores). The toolchain comes with the image; there is no separate Swift install step. Required-check friendly: no `paths:` filter, so it always reports a status. Check name: **`RpplCore tests (Linux)`**.

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

Spam/junk filter for changes to `RpplCore/Sources/RpplCore/Resources/Parks/*.yaml`. Only runs when park data, the schema, the validator script, or the yamllint config change. Steps:

1. **YAML lint** — `yamllint --config-file .yamllint.yml RpplCore/Sources/RpplCore/Resources/Parks/` (relaxed house-style config: long lines, flow mappings and no `---` document start are normal for hand-authored park files).
2. **Schema + sanity validation** — `python3 scripts/validate_parks.py` against [`schema/park.schema.json`](../schema/park.schema.json) (hand-kept in sync with `ParkModels.swift` / `ParkOpening.swift`), plus sanity checks: duplicate `id`, out-of-range or `(0, 0)` coordinates, a cable with fewer than 2 points, obvious placeholder/TODO text.

This does not replace human review of park data (sourcing, accuracy) — see the `park-data-collection` skill and its no-guessing/domain-restricted rules.

Fixtures + smoke test: `scripts/parks-tests/` (`bash scripts/parks-tests/smoke_test.sh` asserts each fixture passes/fails as expected — run it after touching the schema or validator).

## Xcode Cloud

**RpplCore `swift test`** and nightly TestFlight builds run in Xcode Cloud, not GitHub Actions. Local/push gate still runs Core tests through `xcode-gate` / `make test-core`.

### Workflows

Keep three workflows in App Store Connect / Xcode:

| Workflow | Start condition | Actions |
|----------|-----------------|---------|
| **PR / Core tests** | Pull Request Changes | Test (workspace `RpplCore`, scheme **RpplCore**, iOS Simulator) |
| **Nightly TestFlight** | On a Schedule for a Branch (`main`) | Test → Archive (scheme **Rppl**) → Deploy to TestFlight |
| **Release** | Tag Changes, tags beginning with `v` | Test → Archive (scheme **Rppl**, TestFlight and App Store) → TestFlight internal + external. Setup and release steps: [Release.md](Release.md) |

Optional: add **Manual Start** on `main` to the nightly workflow for on-demand TestFlight builds.

> **Check this workflow is running.** On 2026-10-03 no check from it appeared on any PR from #327 to #368; only `Rppl | Test - PR` (app targets) did, and it reported SUCCESS on #327 and #329 while Core tests were red. Running the action below on the #329 snapshot gives `TEST FAILED` (6 tests), so the workflow would have stopped that PR. Open App Store Connect → Xcode Cloud and confirm **PR / Core tests** exists, starts on Pull Request Changes and posts its status to GitHub. Until then the local push gate (`xcode-gate` / `make coverage`) is the only place these tests run, and a PR pushed by a Linux agent never runs them. To enforce the [coverage floor](#coverage-floor) there as well, a `ci_scripts` step can run `python3 scripts/check-core-coverage.py` (it runs `swift test` itself; the `xcodebuild` result bundle is not read). Not set up.

The PR workflow opens the `RpplCore` package directly. Xcode's auto-generated `RpplCore` scheme only builds the library, so Xcode Cloud fails with "There are no test bundles available to test". The shared scheme in `RpplCore/.swiftpm/xcode/xcshareddata/xcschemes/RpplCore.xcscheme` (whitelisted in `.gitignore`) adds `RpplCoreTests` to its Test action. Reproduce locally:

```bash
cd RpplCore && xcodebuild test -scheme RpplCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Nightly schedule

Configure **On a Schedule for a Branch**:

- Branch: **`main`**
- Frequency: daily
- Time: **3:00 AM Europe/Amsterdam** (within the 1–5 AM window; adjust in App Store Connect if you prefer another slot or timezone)

Do **not** add Branch Changes to the nightly workflow unless you also want push-triggered TestFlight (see optional push gate below).

### Skip when no build changes

[`ci_scripts/ci_post_clone.sh`](../ci_scripts/ci_post_clone.sh) runs after clone and cancels the workflow when there is nothing worth archiving:

| `CI_START_CONDITION` | Behavior |
|----------------------|----------|
| `schedule` | Skip unless any commit in the last 24 hours touched build-related paths |
| `push` | Skip unless `HEAD` vs `HEAD~1` includes build-related paths |
| `manual`, `manual_rebuild`, `pr_open`, `pr_update` | Always continue |
| any, with `CI_TAG` set (release tag build) | Always continue; runs `scripts/ci/prepare_release.py` first ([Release.md](Release.md)) |

Build-related paths match the local pre-push **xcode-gate** hook (Swift, plist, entitlements, Xcode project/schemes, `Package.swift` / `Package.resolved`, `.xcassets`, `scripts/git-hooks/xcode-gate.sh`). Docs, YAML, tooling, and most scripts do **not** count.

The shared filter lives in [`scripts/ci/build-related-paths.sh`](../scripts/ci/build-related-paths.sh). Keep it aligned with the `xcode-gate` `files` block in [`.pre-commit-config.yaml`](../.pre-commit-config.yaml).

When the script skips, it exits non-zero — Xcode Cloud stops the run and does not archive or deploy. That cancelled state is intentional (saves compute minutes); it is not a build failure to investigate.

### Optional push gate

If you add **Branch Changes on `main`** to the same TestFlight workflow, also set **Custom Conditions → Don’t Start a Build** in App Store Connect for:

- `Docs/`
- `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, `LEGAL.md`
- `.github/`
- `tools/`

The post-clone script is belt-and-braces for docs-only pushes that still start a run.

### Setup (App Store Connect / Xcode)

1. Open **Xcode → Product → Xcode Cloud → Manage Workflows** (or App Store Connect → Xcode Cloud).
2. Create or edit **Nightly TestFlight** on `Rppl.xcodeproj`.
3. Add start conditions: **On a Schedule for a Branch** (`main`, daily, 3:00 AM Europe/Amsterdam); optionally **Manual Start** on `main`.
4. Actions: Test → Archive (scheme **Rppl**, iOS) → **Deploy to TestFlight** (internal testers).
5. After merging `ci_scripts/` to `main`, run one **Manual Start** build to confirm the hook is picked up.

### Local dry-run

Approximate what Xcode Cloud will do:

```bash
CI_START_CONDITION=schedule CI_PRIMARY_REPOSITORY_PATH=$PWD bash ci_scripts/ci_post_clone.sh
echo "exit=$?"
```

Exit `0` = continue; exit `1` = skip (no build-related changes in the last 24 hours on the current branch).

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
