# Release to TestFlight

Publishing a GitHub release builds Rppl (iPhone app with the embedded Watch app) in Xcode Cloud and sends it to **TestFlight internal** testers automatically. Version and "What to Test" come from the release. Everything after that is manual in App Store Connect: adding the build to an external TestFlight group and submitting to the App Store (see [Promote a build](#promote-a-build-manual)).

Merging to `main` does **not** build anything in Xcode Cloud. Only a release tag does.

## Why Xcode Cloud, and where each check runs

The newest Xcode does not run on the maintainer's Mac, so releases are built in Xcode Cloud, which has it. The Mac keeps using Xcode 26.2 for day-to-day work. Xcode Cloud's free compute hours are limited, so it only does the one job nothing else can do.

| Event | What runs | Where |
|-------|-----------|-------|
| Pull request into `main` | pre-commit, `RpplCore tests (Linux)`, release script tests | GitHub Actions ([DevWorkflow.md](DevWorkflow.md#github-actions)) |
| Merge into `main` | Nothing | n/a |
| GitHub release published (tag created) | Release preflight check, then archive and TestFlight internal | GitHub Actions + Xcode Cloud |
| Add to external group / App Store | You press the button | App Store Connect |

## Cut a release

1. Merge what you want to ship to `main`. Check the PR checks were green.
2. GitHub → **Releases** → **Draft a new release**.
3. **Tag**: create a semver tag targeting `main`, with or without a leading `v`: `2026.9.1` or `v2026.9.1`. For a candidate you want to iterate on, add `-beta.1`, `-beta.2`, and so on.
4. **Description**: write the release notes, or use **Generate release notes** (PR titles). Testers see this text as "What to Test".
5. **Publish**. The tag is created, which starts the Xcode Cloud **Release** workflow.
6. Check the run:
   - GitHub Actions → **Release preflight** shows the tag verdict and a preview of the "What to Test" text. Red means fix the release, then **Rebuild** in Xcode Cloud (the build only reads the description when it starts).
   - App Store Connect → Xcode Cloud → the run. The log of the *Post-Clone* step prints the version and notes it used.
7. Internal testers get the build as soon as processing finishes.

Tag rules (the build fails within seconds on anything else):

| Tag | Result |
|-----|--------|
| `2026.9.1`, `v2026.9.1` | version `2026.9.1` |
| `2026.9.1-beta.2`, `v2026.9.1-beta.2` | version `2026.9.1` (suffix only labels the release) |
| `2026.9`, `v1.2`, `latest`, `vNext` | rejected; App Store versions are three integers |

Build numbers are not set by the repo. Xcode Cloud assigns an integer per app and increments it for every build.

## One-time setup

About 15 minutes. The workflow lives in App Store Connect / Xcode, not in this repo.

1. **Retire the old workflows.** App Store Connect → Xcode Cloud → Workflows. Delete **Nightly TestFlight** (its schedule and any *Branch Changes on `main`* condition, which is what built TestFlight on every merge) and **PR / Core tests**. Core tests run on GitHub now, and these two spent the free compute hours. Keep only **Release**.
2. **Next build number.** App Store Connect → Xcode Cloud → Settings → Build Number → set *Next Build Number* above the highest build already uploaded to TestFlight (manual Xcode uploads count). Only Admin or App Manager can edit it.
3. **GitHub token** (the repo is private, so Xcode Cloud cannot read release notes without one). GitHub → Settings → Developer settings → Fine-grained tokens: only repository `DCSBL/rppl`, permission **Contents: Read-only**. Note the expiry in your calendar. Without a valid token the build still ships, but "What to Test" falls back to the last commit subjects and the "tag is on main" check is skipped (both log a warning).
4. **Xcode Cloud workflow.** Xcode → Product → Xcode Cloud → Manage Workflows (or App Store Connect → Xcode Cloud). Create or edit **Release** on `Rppl.xcodeproj`:
   - **General**: turn **Restrict Editing** on. Apple requires it for workflows that deploy to external testers; it costs nothing on a solo account and avoids a surprise when you add external later.
   - **Environment**: pick the newest Xcode release in the Xcode Version list, and pin it rather than floating on "Latest Release", so a new Xcode never lands in the middle of a release. Bump it by hand when App Store Connect requires a newer SDK. Add environment variable `RPPL_GITHUB_TOKEN` with the token and mark it **Secret** (redacted). Turn **Auto-cancel Builds** off.
   - **Start Conditions**: exactly one, **Tag Changes → Any Tag**. Xcode Cloud only offers *Any Tag* or *Tags beginning with …* (no regex), and `2026.9.1` and `v2026.9.1` share no prefix, so *Any Tag* is the only setting that covers both. The post-clone script rejects tags that are not releases in seconds. No Branch Changes, no Schedule, no Manual Start, and no Custom Conditions (a "don't start on docs-only changes" filter would silently skip a release).
   - **Actions**: **Archive** the `Rppl` scheme for iOS. No Test action (GitHub already tested the PR; every minute here is budgeted). Set **Deployment Preparation** to **TestFlight and App Store**, not "TestFlight (Internal Testing Only)": an internal-only archive can never go to external testers or the App Store.
   - **Post-Actions**: **TestFlight Internal Testing** with your dev group. Do not add *TestFlight External Testing*; external stays manual.
5. **TestFlight test information**, needed before the first external promotion (internal testers skip it). App Store Connect → Rppl → TestFlight → Test Information: Beta App Description (required), feedback email, review contact and review notes ("Needs an Apple Watch and Health permission. No login."). Create the **external group** and check the app's TestFlight language includes English (US), which is the file the script writes (`WhatToTest.en-US.txt`).

First run: publish a `-beta` release, confirm version, build number and "What to Test" in TestFlight on an internal device, then promote only when you are happy.

### Compute hours

Every Apple Developer Program membership includes 25 Xcode Cloud compute hours per month. The Release workflow is an archive of an iPhone app with a Watch app, so a release costs one short build. If the allowance is spent when you publish a release, the build does not start: wait for the next period or buy more under App Store Connect → Xcode Cloud → Usage. Then press **Rebuild** on the tag, or publish again.

## Promote a build (manual)

Xcode Cloud never submits anything beyond internal TestFlight and this repo has no App Store Connect API key. Do it by hand, from the build that testers verified (it must come from the Release workflow).

**External TestFlight**

1. App Store Connect → Rppl → TestFlight → the external group → **Builds** → **+** → pick the build.
2. The first build of each version goes through Beta App Review; later builds of the same version usually skip it.

**App Store**

1. App Store Connect → Rppl → iOS App → **+** → version `X.Y.Z` (same as the tag, without `v`).
2. Paste **What's New**. The plain-text release notes are in the release preflight summary and in the Post-Clone log.
3. **Build** → pick the build.
4. Fill review information and privacy answers, choose *Manually release this version* if you want to press the final button yourself, then **Add for Review** → **Submit**.
5. After it is released, that version is closed for new builds.

## What the build does

`ci_scripts/ci_post_clone.sh` requires `CI_TAG` (an untagged start fails immediately) and runs `scripts/ci/prepare_release.py`. It:

1. Validates the tag and derives the marketing version X.Y.Z (the `v` and the suffix are dropped).
2. Checks the tagged commit is on `main` (GitHub compare API). Ahead or diverged fails the build.
3. Sets every `MARKETING_VERSION` in `Rppl.xcodeproj` so iPhone and Watch match. App Store validation rejects a Watch app whose version differs from its companion.
4. Fetches the release description (retrying for about a minute if the release is not visible yet), converts markdown to plain text, caps it at 4000 characters and writes `TestFlight/WhatToTest.en-US.txt`, which Xcode Cloud attaches to the TestFlight build.
5. Stamps `RpplBuildDate` in `Rppl/Info.plist` (shown in About).

These edits exist only in the CI checkout; nothing is committed back.

Dry run against a scratch copy (use a throwaway worktree, the script rewrites files):

```bash
git worktree add ../rppl-release-dry-run HEAD && cd ../rppl-release-dry-run
printf '%s' '{"body":"## Notes\n* Something new"}' > /tmp/release.json
CI_TAG=2026.9.1-beta.1 RPPL_RELEASE_JSON=/tmp/release.json bash ci_scripts/ci_post_clone.sh
xcodebuild -project Rppl.xcodeproj -scheme Rppl -showBuildSettings | grep MARKETING_VERSION
cd - && git worktree remove --force ../rppl-release-dry-run
```

Unit tests: `python3 -m unittest discover -s scripts/ci -p 'test_*.py'` (also run on PRs by the release preflight workflow).

## Pitfalls

| Pitfall | What to know |
|---------|--------------|
| No "release published" trigger | Xcode Cloud starts from tags. Publishing a release creates the tag; drafts create none. Pushing a bare tag also builds (no notes, so the commit-list fallback is used). Moving a tag rebuilds. |
| Any tag starts a run | *Any Tag* is the only way to match tags with and without `v`. A tag that is not a release (`latest`) starts a run that fails in the Post-Clone step. Delete the tag. |
| Old workflows still alive | A leftover Nightly or Branch Changes workflow keeps spending compute hours and TestFlight builds. Delete them (setup step 1). |
| Internal-only archive | Builds from "TestFlight (Internal Testing Only)" can never go external or to the App Store. |
| Beta App Review | First build of each version waits for review. Test Information must be filled in or external distribution fails. |
| Auto-cancel Builds | On by default; two quick tags would cancel the first. Off for Release. |
| Watch version mismatch | iPhone and Watch marketing versions must match; the script sets all of them. |
| Build number collisions | Xcode Cloud's counter is per app. Set *Next Build Number* above any manual upload. |
| Release edited after publish | The build already read it. Use **Rebuild**; notes are fetched again. |
| Token expired | Warning in the Post-Clone log, fallback notes. Rotate the token before its expiry. |
| Versions only go up | App Store Connect rejects an upload at or below a version that already shipped. The repo's own `MARKETING_VERSION` is `1.0`, so the first year-based tag (`2026.x.y`) is above it. Never tag a lower version after that. |
| Signing capabilities | Cloud signing needs HealthKit, WeatherKit, iCloud and the Watch depth entitlement enabled on the App IDs. Keep them enabled; the first release run exercises them. |
| Build expiry | TestFlight builds expire after 90 days. |
