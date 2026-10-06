# Release to TestFlight

Publishing a GitHub release builds Rppl (iPhone app with the embedded Watch app) in Xcode Cloud and sends it to **TestFlight internal** testers automatically. Version and "What to Test" come from the release. Everything after that is manual in App Store Connect: adding the build to an external TestFlight group and submitting to the App Store (see [Promote a build](#promote-a-build-manual)).

Merging to `main` does **not** build anything in Xcode Cloud. Only a release does: publishing it pushes the branch `release/X.Y.Z` (see [Release branches](#release-branches-and-build-groups)), and Xcode Cloud builds that branch.

## Why Xcode Cloud, and where each check runs

The newest Xcode does not run on the maintainer's Mac, so releases are built in Xcode Cloud, which has it. The Mac keeps using Xcode 26.2 for day-to-day work. Xcode Cloud's free compute hours are limited, so it only does the one job nothing else can do.

| Event | What runs | Where |
|-------|-----------|-------|
| Pull request into `main` | pre-commit, `RpplCore tests (Linux)`, release script tests | GitHub Actions ([DevWorkflow.md](DevWorkflow.md#github-actions)) |
| Merge into `main` | `RpplCore tests (Linux)` again, so a merge that breaks `main` shows red before you tag | GitHub Actions |
| GitHub release published (tag created) | Release preflight check and the push of `release/X.Y.Z`; then, on the released commit, release script tests and `RpplCore` `swift test` **before** the archive; then archive and TestFlight internal | GitHub Actions + Xcode Cloud |
| Add to external group / App Store | You press the button | App Store Connect |

## Cut a release

1. Merge what you want to ship to `main`. Check the PR checks were green.
2. GitHub → **Releases** → **Draft a new release**.
3. **Tag**: create a semver tag targeting `main`, with or without a leading `v`: `2026.9.1` or `v2026.9.1`. For a candidate you want to iterate on, add `-beta.1`, `-beta.2`, and so on.
4. **Description**: write the release notes, or use **Generate release notes** (PR titles). Testers see this text as "What to Test".
5. **Publish**. The tag is created. GitHub Actions → **Release branch** then moves `release/X.Y.Z` to the tagged commit, which starts the Xcode Cloud **Release** workflow.
6. Check the run:
   - GitHub Actions → **Release preflight** shows the tag verdict and a preview of the "What to Test" text. Red means fix the release, then **Rebuild** in Xcode Cloud (the build only reads the description when it starts).
   - GitHub Actions → **Release branch** must be green. Red means no build started: a bad tag or a tag that is not on `main`. Green but no Xcode Cloud run within a minute or two: see [Pitfalls](#pitfalls).
   - App Store Connect → Xcode Cloud → the run, listed under the group `release/X.Y.Z`. The log of the *Post-Clone* step prints the tag it found for the commit, the version and the notes it used.
7. Internal testers get the build as soon as processing finishes.

Tag rules (the **Release branch** workflow fails on anything else and no build starts):

| Tag | Result |
|-----|--------|
| `2026.9.1`, `v2026.9.1` | version `2026.9.1` |
| `2026.9.1-beta.2`, `v2026.9.1-beta.2` | version `2026.9.1` (suffix only labels the release) |
| `2026.9`, `v1.2`, `latest`, `vNext` | rejected; App Store versions are three integers |

Build numbers are not set by the repo. Xcode Cloud assigns an integer per app and increments it for every build.

## Release branches and build groups

Xcode Cloud (and TestFlight's **Build Groups** view) groups builds by workflow and Git ref. A tag is its own ref, so building tags gave every beta its own group. The Release workflow therefore starts on the branch `release/X.Y.Z` instead, and every build of one version (`-beta.1`, `-beta.2`, `-rc.1`, the final) lands in the group `release/X.Y.Z`. The next version starts a new group.

Nothing changes in how you release: you still publish a GitHub release. The **Release branch** workflow does the rest:

1. Validates the tag (format, on `main`), the same check the build does.
2. Pushes a **marker commit** to `release/X.Y.Z` (a new version creates the branch): the files of the tagged commit plus `ci_scripts/release-marker.txt` (tag, tagged commit, workflow run). The marker's parent is the previous branch head, so the push is always a fast-forward (no force push) and any tag on `main` can be released, in any order. Pushing the tagged commit itself does not work: a new branch at a commit the repository already has brings no new commit, and Xcode Cloud does not start for it. The marker is always new and changes a file, so "Start if any file changes" holds.
3. Xcode Cloud starts on that push. The build has no `CI_TAG`, so the Post-Clone step reads the tag from the marker file and derives version, notes and the About label from it exactly as before. The About screen shows the tagged commit, not the marker. A branch without a marker file (a manual start on a plain commit) falls back to the release tag that points at the commit (GitHub tags API).

Consequences:

- Every published release starts a build, including a final tag on the commit of the last beta. If you only want to promote the build testers already verified, skip the final release build: add the existing build to Public beta or the App Store instead.
- `release/*` branches are build triggers, not development branches. Do not push work to them by hand; a push without a marker or a matching release tag fails in the Post-Clone step.
- The branch history is a chain of marker snapshots, not `main`'s history. Never merge it back.
- TestFlight → **Versions** is still the per-version overview of builds. **Build Groups** now shows one entry per version too.

## Versions, betas and Beta App Review

TestFlight groups builds by version, and Beta App Review looks at the **first external build of each version**. Later builds of the same version usually skip review (Apple can still review a change it considers significant). So keep one version for all betas and make each build a new tag:

| Tag | Version | Use |
|-----|---------|-----|
| `2026.10.1-beta.1` | `2026.10.1` | First build of the version. Goes to `internal` at once. The first one added to **Public beta** waits for Beta App Review. |
| `2026.10.1-beta.2`, `-beta.3`, … | `2026.10.1` | More builds of the same version: new build number, normally no new review. |
| `2026.10.1` | `2026.10.1` | The build you promote to the App Store. |

Only bump the version when you start the next release cycle; a version that is on the App Store is closed for new builds. Do not use four-part tags such as `2026.10.1.2`: App Store versions have at most three integers, and the build number is Xcode Cloud's counter, not part of the tag.

The About screen in the app shows the release tag with the build number (`2026.10.1-beta.2 (312)`) and the short commit SHA with the build date. TestFlight itself shows only version and build number. A local Xcode build shows the marketing version and no SHA. The commit line is a link: it opens the commit on GitHub (the repository root on a local build). The repo is private for now, so the link shows a 404 until it goes public.

## One-time setup

About 15 minutes. The workflow lives in App Store Connect / Xcode, not in this repo.

1. **Retire the old workflows.** App Store Connect → Xcode Cloud → Workflows. **Nightly TestFlight** (its schedule and any *Branch Changes on `main`* condition, which is what built TestFlight on every merge) must not exist. **Test - PR** must be deactivated (its *Pull Request Changes* start condition only started Core tests, which run on GitHub now). Deleting it is fine too. These two spent the free compute hours. Only **Release** is active.
2. **TestFlight groups.** The Release post-action targets the internal group **internal** (the maintainer; formerly named `nightly`). **Public beta** is the external group and stays empty until you add a build by hand. An old empty group `internal-old` can be deleted.
3. **Build number.** Nothing to do normally: Xcode Cloud numbers builds sequentially across all workflows of the product (App Store Connect → Xcode Cloud → Settings → Build Number shows the next one). Raise *Next Build Number* only if you upload a build manually with a higher number. Only Admin or App Manager can edit it.
4. **GitHub token** (the repo is private, so Xcode Cloud cannot read release notes without one). GitHub → Settings → Developer settings → Fine-grained tokens: only repository `DCSBL/rppl`, permission **Contents: Read-only**. Note the expiry in your calendar. Without a valid token the build still ships, but "What to Test" falls back to the last commit subjects and the "tag is on main" check is skipped (both log a warning). A branch without a marker file also needs the token to find its tag, so that case fails without it. The **Release branch** workflow uses the Actions token, not this one.
5. **Xcode Cloud workflow.** App Store Connect → Xcode Cloud → Workflows (or Xcode → Product → Xcode Cloud → Manage Workflows). The **Release** workflow on `Rppl.xcodeproj` is configured as follows. Use these settings to recreate it:
   - **General**: turn **Restrict Editing** on. Apple requires it for workflows that deploy to external testers; it costs nothing on a solo account and avoids a surprise when you add external later.
   - **Environment**: Xcode Version pinned to a released Xcode (currently **Xcode 27 (27A266a)**) rather than floating on "Latest Release", so a new Xcode never lands in the middle of a release. Bump it by hand when App Store Connect requires a newer SDK. Environment variable `RPPL_GITHUB_TOKEN` holds the token, marked **Secret** (redacted).
   - **Start Conditions**: exactly one, **Branch Changes → Branches beginning with `release/`**, with **Auto-cancel Builds** off and **Files and Folders** left on *Start if any file changes*. No Tag Changes (a tag start next to the branch start builds every release twice), no Schedule, no Manual Start, and no Custom Conditions (a "don't start on docs-only changes" filter would silently skip a release). The post-clone script rejects any other branch in seconds.
   - **Actions**: **Archive** the `Rppl` scheme for iOS. No Xcode Cloud Test action: the `Rppl` scheme only runs the thin `RpplTests` and the slow `RpplUITests`, while the real suite is `RpplCore`. That runs in the Post-Clone step instead (see [What the build does](#what-the-build-does)). Set **Distribution Preparation** to **App Store Connect** (Xcode calls it "TestFlight and App Store"), not "TestFlight (Internal Testing Only)": an internal-only archive can never go to external testers or the App Store.
   - **Post-Actions**: **TestFlight Internal Testing** with the group **internal**. Do not add *TestFlight External Testing*; external stays manual.
6. **TestFlight test information**, needed before the first external promotion (internal testers skip it). App Store Connect → Rppl → TestFlight → Test Information: Beta App Description (required), feedback email, review contact and review notes ("Needs an Apple Watch and Health permission. No login."). The external group is **Public beta**. Check the app's TestFlight language includes English (US), which is the file the script writes (`WhatToTest.en-US.txt`).

First run: publish a `-beta` release, confirm version, build number and "What to Test" in TestFlight on an internal device, then promote only when you are happy.

### Compute hours

Every Apple Developer Program membership includes 25 Xcode Cloud compute hours per month. The Release workflow is an archive of an iPhone app with a Watch app, so a release costs the Core tests plus one archive. If the allowance is spent when you publish a release, the build does not start: wait for the next period or buy more under App Store Connect → Xcode Cloud → Usage. Then press **Rebuild** on the tag, or publish again.

## Promote a build (manual)

Xcode Cloud never submits anything beyond internal TestFlight and this repo has no App Store Connect API key. Do it by hand, from the build that testers verified (it must come from the Release workflow).

**External TestFlight**

1. App Store Connect → Rppl → TestFlight → **Public beta** → **Builds** → **+** → pick the build.
2. The first build of each version goes through Beta App Review; later builds of the same version usually skip it.

**App Store**

1. App Store Connect → Rppl → iOS App → **+** → version `X.Y.Z` (same as the tag, without `v`).
2. Paste **What's New**. The plain-text release notes are in the release preflight summary and in the Post-Clone log.
3. **Build** → pick the build.
4. Fill review information and privacy answers, choose *Manually release this version* if you want to press the final button yourself, then **Add for Review** → **Submit**.
5. After it is released, that version is closed for new builds.

## What the build does

`ci_scripts/ci_post_clone.sh` requires a `release/X.Y.Z` branch (`CI_BRANCH`) or a `CI_TAG`; any other start fails immediately. It runs `scripts/ci/prepare_release.py`, then tests the released commit before the archive starts. A failing test fails the build and nothing reaches TestFlight. `prepare_release.py`:

1. On a branch build, reads the release tag from `ci_scripts/release-marker.txt`. Without a marker it finds the release tag of that version that points at `CI_COMMIT` (GitHub tags API, retrying for about a minute). No tag, or a tag of another version, fails the build.
2. Validates the tag and derives the marketing version X.Y.Z (the `v` and the suffix are dropped).
3. Checks the tagged commit is on `main` (GitHub compare API). Ahead or diverged fails the build.
4. Sets every `MARKETING_VERSION` in `Rppl.xcodeproj` so iPhone and Watch match. App Store validation rejects a Watch app whose version differs from its companion.
5. Fetches the release description (retrying for about a minute if the release is not visible yet), converts markdown to plain text, caps it at 4000 characters and writes `TestFlight/WhatToTest.en-US.txt`, which Xcode Cloud attaches to the TestFlight build.
6. Stamps `RpplBuildDate`, `RpplReleaseTag` (the tag without a leading `v`) and `RpplGitCommit` (short SHA from `CI_COMMIT`, else `git rev-parse HEAD`) in `Rppl/Info.plist`. The About screen shows them.

After that the Post-Clone step runs the release script unit tests and `swift test` for `RpplCore` (on macOS with the pinned Xcode, so the Apple-only code paths run too). The released commit is tested because `main` after merging can differ from every green PR. A failure shows up in the Post-Clone log.

**Emergency skip.** If a test blocks a release you must ship, add environment variable `RPPL_SKIP_TESTS` = `1` to the Release workflow, rebuild, then remove it again. The log prints a warning. Not a normal path: fix or revert the test instead.

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
| No "release published" trigger | Xcode Cloud starts from branches, and the **Release branch** workflow pushes `release/X.Y.Z` when a release is published. Drafts create no tag and no build. A bare tag (pushed without a release) starts nothing: there is no Tag Changes condition. |
| Tag start next to the branch start | A Tag Changes condition left on the workflow builds each release twice (once per ref) and splits the Build Groups again. Keep only Branch Changes. |
| Release branch green, no Xcode Cloud run | The Release start condition did not fire. Check the workflow's Start Conditions (Branch Changes, `release/`, Tag Changes removed). If it is right, start the build once by hand (App Store Connect → Xcode Cloud → Start Build, branch `release/X.Y.Z`; the build finds its tag from the marker, or from the tags API on a plain commit) and see whether the push event reaches Xcode Cloud at all. |
| Branch without a marker or tag | A manual push to a `release/*` branch, or a deleted tag, starts a build that fails in Post-Clone with "No release tag". Delete the branch or restore the tag. |
| Old `release/*` branches | Any branch starting with `release/` starts the Release workflow when pushed. Old ones such as `release/production` or `release/testflight-internal` fail in Post-Clone (not a `release/X.Y.Z`) and spend compute. Delete them. |
| Old workflows still alive | A leftover Nightly or Branch Changes workflow keeps spending compute hours and TestFlight builds. Delete them (setup step 1). |
| Internal-only archive | Builds from "TestFlight (Internal Testing Only)" can never go external or to the App Store. |
| Beta App Review | First build of each version waits for review. Test Information must be filled in or external distribution fails. |
| Auto-cancel Builds | On by default; two quick pushes to one branch would cancel the first. Off for Release. |
| Watch version mismatch | iPhone and Watch marketing versions must match; the script sets all of them. |
| Build number collisions | Xcode Cloud's counter is per app. Set *Next Build Number* above any manual upload. |
| Release edited after publish | The build already read it. Use **Rebuild**; notes are fetched again. |
| Token expired | Warning in the Post-Clone log, fallback notes. Rotate the token before its expiry. |
| Versions only go up | App Store Connect rejects an upload at or below a version that already shipped. The repo's own `MARKETING_VERSION` is `1.0`, so the first year-based tag (`2026.x.y`) is above it. Never tag a lower version after that. |
| Signing capabilities | Cloud signing needs HealthKit, WeatherKit, iCloud and the Watch depth entitlement enabled on the App IDs. Keep them enabled; the first release run exercises them. |
| Build expiry | TestFlight builds expire after 90 days. |
