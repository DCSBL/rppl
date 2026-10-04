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

Spam/junk filter for changes to `RpplCore/Sources/RpplCore/Resources/Parks/*.yaml`. Only runs when park data, the schema, the validator script, or the yamllint config change. Steps:

1. **YAML lint** — `yamllint --config-file .yamllint.yml RpplCore/Sources/RpplCore/Resources/Parks/` (relaxed house-style config: long lines, flow mappings and no `---` document start are normal for hand-authored park files).
2. **Schema + sanity validation** — `python3 scripts/validate_parks.py` against [`schema/park.schema.json`](../schema/park.schema.json) (hand-kept in sync with `ParkModels.swift` / `ParkOpening.swift`), plus sanity checks: duplicate `id`, out-of-range or `(0, 0)` coordinates, a cable with fewer than 2 points, obvious placeholder/TODO text.

This does not replace human review of park data (sourcing, accuracy) — see the `park-data-collection` skill and its no-guessing/domain-restricted rules.

Fixtures + smoke test: `scripts/parks-tests/` (`bash scripts/parks-tests/smoke_test.sh` asserts each fixture passes/fails as expected — run it after touching the schema or validator).

## Xcode Cloud

Xcode Cloud only builds **releases**: publishing a GitHub release creates a tag, and the **Release** workflow archives it and sends it to TestFlight internal. Merges to `main` and PRs build nothing there; tests run on GitHub ([PR checks](#pr-checks-linux), [Core tests](#core-tests-linux)) and in the local push gate. Setup, the release steps and promotion to external TestFlight / the App Store (manual, in App Store Connect): [Release.md](Release.md).

The older **Nightly TestFlight** and **PR / Core tests** workflows are retired (they spent the free compute hours). If they still exist in App Store Connect, delete them.

[`ci_scripts/ci_post_clone.sh`](../ci_scripts/ci_post_clone.sh) runs after clone in every Xcode Cloud build. It requires `CI_TAG`, so a start without a tag fails immediately instead of archiving, and otherwise runs [`scripts/ci/prepare_release.py`](../scripts/ci/prepare_release.py).

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
