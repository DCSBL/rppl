# Tools

## Worktree → main

Move a feature worktree (e.g. `~/Development/rppl-map-fit`) into the main checkout (`~/Development/rppl`):

```bash
cd ~/Development/rppl-map-fit
tools/worktree-to-main.sh
```

See `worktree-to-main.sh --help`. Cursor skill: `/worktree-to-main`.

## Optional local tool binaries

Put `swiftlint` here if Homebrew is unavailable:

```bash
# example: portable SwiftLint release unzipped into this folder
chmod +x tools/bin/swiftlint
```

Scripts prepend `tools/bin` to `PATH`.
