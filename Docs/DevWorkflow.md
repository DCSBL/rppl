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

## Notes

- Commit stays light (hygiene + spell + lint). First push after app/Core source changes still pays for `xcodebuild`; later pushes with the same inputs skip it. Core-test-only pushes skip the app build.
- SwiftLint starts lenient; tighten `.swiftlint.yml` over time.
- Unit tests live primarily in `RpplCore` (`swift test`). Keep app targets thin wrappers around Core logic.

## Device pair: one Cmd+R (Watch + iPhone)

WatchConnectivity only pairs apps when IDs match Apple’s rule:

| Role | Bundle ID (dev) |
|------|-----------------|
| iPhone | `nl.dcsbl.dev.rppl` |
| Watch | `nl.dcsbl.dev.rppl.watchkitapp` |
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
