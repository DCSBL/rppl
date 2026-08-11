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
   - `swift test` in `WakeTrackerCore` (fail fast)
   - `xcodebuild build` for `wake-tracker` (iOS Simulator; embeds Watch)
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
- Unit tests live primarily in `WakeTrackerCore` (`swift test`). Keep app targets thin wrappers around Core logic.
