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

This installs a git `pre-commit` hook. Every `git commit` runs the gate below. Commit is blocked if any step fails.

## What runs on commit

1. Basic file hygiene (trailing whitespace, YAML/JSON, merge conflict markers)
2. **codespell**
3. **SwiftLint** (`--strict`, config in `.swiftlint.yml`)
4. **xcode-gate** (`scripts/git-hooks/xcode-gate.sh`):
   - `swift test` in `RpplCore` (fail fast)
   - `xcodebuild build` for `Rppl` (iOS Simulator; embeds Watch)
   - `xcodebuild analyze`

Manual full gate:

```bash
make check
# or
pre-commit run --all-files
```

Core tests only:

```bash
make test-core
```

## Escape hatches (emergency only)

- Skip one hook: `SKIP=xcode-gate git commit ...`
- Skip all hooks: `git commit --no-verify` (do not use as normal workflow)

## Notes

- Gate is intentionally heavy (full build + analyze). Expect ~1–2+ minutes on commit.
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
