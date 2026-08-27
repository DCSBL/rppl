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
3. **SwiftLint** (`--strict`, config in `.swiftlint.yml`)

## What runs on push

Heavy gate — **only if the push includes build-related files** (Swift, plist, entitlements, Xcode project/schemes, `Package.swift` / `Package.resolved`, `.xcassets`, or `scripts/git-hooks/xcode-gate.sh`). Docs, YAML, and other scripts/helpers skip this.

When it runs, push is blocked if any fail. **xcode-gate** (`scripts/git-hooks/xcode-gate.sh`) then:

1. **`swift test` in `RpplCore`** — skipped if Core sources/tests/`Package.swift` and the local Swift/Xcode toolchain match the last successful run (content fingerprint of tracked files, not a time TTL). Dirty working-tree edits count, so `make gate` does not skip stale.
2. **`xcodebuild build`** for `Rppl` (iOS Simulator; embeds Watch) — skipped if app/Watch/project/Core *sources* match the last successful build. Changing only `RpplCore/Tests` does not rebuild the apps.
3. **`xcodebuild analyze` is not part of push.** It is slow and mostly overlaps `build`. Use `make check` (or `XCODE_GATE_ANALYZE=1`) when you want it.

Stamps live in `.git/rppl-xcode-gate/` (shared across worktrees of the same clone). Toolchain (`xcodebuild -version` / `swift --version`) is part of the key, so an Xcode upgrade rebuilds.

Manual gates:

```bash
make gate          # same as pre-push (cache + no analyze)
make check         # full: ignore cache, tests + build + analyze
make test-core     # RpplCore swift test only
# or
pre-commit run --all-files --hook-stage pre-push
# (also: pre-commit run --all-files for commit-stage hooks)
```

Force a rebuild without analyze: `XCODE_GATE_NO_CACHE=1 make gate`.

## Escape hatches (emergency only)

- Skip heavy gate on push: `SKIP=xcode-gate git push ...`
- Skip all hooks: `git commit --no-verify` / `git push --no-verify` (do not use as normal workflow)

## GitHub Actions

### PR checks (Linux)

Workflow: [`.github/workflows/pr-checks.yml`](../.github/workflows/pr-checks.yml).

On every PR targeting `main`, a GitHub-hosted `ubuntu-24.04` runner runs:

1. **pre-commit** — same **commit-stage** hooks (hygiene, codespell, SwiftLint, legal sync).

**RpplCore `swift test`** runs via **Xcode Cloud**, not GitHub Actions. Local/push gate still runs Core tests through `xcode-gate` / `make test-core`.

It does **not** run `xcode-gate` / `xcodebuild` on GitHub (macOS + Xcode only).

- Uses `fetch-depth: 0` so `--from-ref` can see base and head SHAs.
- Caches `~/.cache/pre-commit` and the SwiftLint Linux binary.
- Runs `pre-commit run --from-ref <base> --to-ref <head>` so hooks only see PR-changed files.
- SwiftLint install is a **step-level** skip when the PR has no matching paths. The job always reports a status, so you can mark **`pre-commit`** as a required check without skipped-job merge blocks.
- Hooks with no matching files are skipped by pre-commit (exit 0).

To enforce: GitHub → Settings → Branches → Branch protection (or ruleset) for `main` → require status check **`pre-commit`** (drop **`RpplCore tests`** if it was required).

## Xcode Cloud

**RpplCore `swift test`** and nightly TestFlight builds run in Xcode Cloud, not GitHub Actions. Local/push gate still runs Core tests through `xcode-gate` / `make test-core`.

### Workflows

Keep two workflows in App Store Connect / Xcode:

| Workflow | Start condition | Actions |
|----------|-----------------|---------|
| **PR / Core tests** | Pull Request Changes | Test (`RpplCore` via `swift test`) |
| **Nightly TestFlight** | On a Schedule for a Branch (`main`) | Test → Archive (scheme **Rppl**) → Deploy to TestFlight |

Optional: add **Manual Start** on `main` to the nightly workflow for on-demand TestFlight builds.

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
