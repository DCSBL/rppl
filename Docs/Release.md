# Release to TestFlight

Publishing a GitHub release builds Rppl (iPhone app with the embedded Watch app) in Xcode Cloud and sends it to TestFlight internal and external testers. Version and "What to Test" come from the release. Submitting to the App Store stays a manual step in App Store Connect (see [Promote to the App Store](#promote-to-the-app-store-manual)).

## Cut a release

1. Merge what you want to ship to `main`. Nightly (see [DevWorkflow.md](DevWorkflow.md#xcode-cloud)) keeps building `main` to internal TestFlight as before.
2. GitHub → **Releases** → **Draft a new release**.
3. **Tag**: create `vX.Y.Z` (for example `v1.2.0`) targeting `main`. For a candidate you want to iterate on, use `vX.Y.Z-beta.1`, `-beta.2`, and so on.
4. **Description**: write the release notes, or use **Generate release notes** (PR titles). Testers see this text as "What to Test".
5. **Publish**. The tag is created, which starts the Xcode Cloud **Release** workflow.
6. Check the run:
   - GitHub Actions → **Release preflight** shows the tag verdict and a preview of the "What to Test" text. Red means fix the release, then **Rebuild** in Xcode Cloud (the build only reads the description when it starts).
   - App Store Connect → Xcode Cloud → the run. The log of the *Post-Clone* step prints the version and notes it used.
7. Internal testers get the build as soon as processing finishes. External testers get it after Beta App Review, which applies to the first build of each version. Later builds of the same version usually skip review.

Tag rules (the build fails early on anything else):

| Tag | Result |
|-----|--------|
| `v1.2.0` | version `1.2.0` |
| `v1.2.0-beta.2` | version `1.2.0` (suffix only labels the release) |
| `1.2.0`, `v1.2`, `vNext` | rejected; App Store versions are three integers |

Build numbers are not set by the repo. Xcode Cloud assigns an integer per app and increments it for every build (nightly and release share the counter).

## One-time setup

About 15 minutes. The workflow lives in App Store Connect / Xcode, not in this repo.

1. **TestFlight test information.** App Store Connect → Rppl → TestFlight → Test Information: Beta App Description (required), feedback email, review contact and review notes ("Needs an Apple Watch and Health permission. No login."). Create the **external group** and check the app's TestFlight language includes English (US), which is the file the script writes (`WhatToTest.en-US.txt`).
2. **Next build number.** App Store Connect → Xcode Cloud → Settings → Build Number → set *Next Build Number* above the highest build already uploaded to TestFlight (manual Xcode uploads count). Only Admin or App Manager can edit it.
3. **GitHub token** (the repo is private, so Xcode Cloud cannot read release notes without one). GitHub → Settings → Developer settings → Fine-grained tokens: only repository `DCSBL/rppl`, permission **Contents: Read-only**. Note the expiry in your calendar. Without a valid token the build still ships, but "What to Test" falls back to the last commit subjects and the "tag is on main" check is skipped (both log a warning).
4. **Xcode Cloud workflow.** Xcode → Product → Xcode Cloud → Manage Workflows. Duplicate **Nightly TestFlight**, name it **Release**, then:
   - **General**: turn **Restrict Editing** on. Xcode Cloud requires it for workflows that deploy to external testers.
   - **Environment**: pin the Xcode version (do not float on "Latest Release"). Add environment variable `RPPL_GITHUB_TOKEN` with the token and mark it **Secret** (redacted).
   - **Start Conditions**: remove the schedule. Add **Tag Changes** → **Tags Beginning With** `v`. Turn **Auto-cancel Builds** off. Add **no Custom Conditions**: a "don't start on docs-only changes" filter would silently skip releases.
   - **Actions**: Test (optional, same as nightly) → Archive scheme `Rppl` for iOS. Set **Deployment Preparation** to **TestFlight and App Store**, not "TestFlight (Internal Testing Only)": an internal-only archive can never go to external testers or the App Store.
   - **Post-Actions**: **TestFlight Internal Testing** with your dev group. After the first green run, add **TestFlight External Testing** with the external group.
5. **Merge the release scripts to `main` before the first tag.** Xcode Cloud builds the tagged commit, so it must contain `ci_scripts/` and `scripts/ci/`.
6. Optional: a GitHub tag ruleset for `v*` limited to admins. Any pushed `v*` tag starts an external build.

First run: publish a `-beta` release with only the internal post-action, confirm version, build number and "What to Test" in TestFlight, then add the external post-action.

## Promote to the App Store (manual)

Xcode Cloud never submits to App Review and this repo has no App Store Connect API key. Do it by hand:

1. App Store Connect → Rppl → iOS App → **+** → version `X.Y.Z` (same as the tag).
2. Paste **What's New**. The plain-text release notes are in the release preflight summary and in the Post-Clone log.
3. **Build** → pick the build that testers verified (it must come from the Release workflow, not nightly).
4. Fill review information and privacy answers, choose *Manually release this version* if you want to press the final button yourself, then **Add for Review** → **Submit**.
5. After it is released, that version is closed for new builds (see the nightly note below).

## What the build does

`ci_scripts/ci_post_clone.sh` runs `scripts/ci/prepare_release.py` whenever `CI_TAG` is set. It:

1. Validates the tag and derives the marketing version.
2. Checks the tagged commit is on `main` (GitHub compare API). Ahead or diverged fails the build.
3. Sets every `MARKETING_VERSION` in `Rppl.xcodeproj` so iPhone and Watch match. App Store validation rejects a Watch app whose version differs from its companion.
4. Fetches the release description (retrying for about a minute if the release is not visible yet), converts markdown to plain text, caps it at 4000 characters and writes `TestFlight/WhatToTest.en-US.txt`, which Xcode Cloud attaches to the TestFlight build.
5. Stamps `RpplBuildDate` in `Rppl/Info.plist` (shown in About).

These edits exist only in the CI checkout; nothing is committed back.

Dry run against a scratch copy (use a throwaway worktree, the script rewrites files):

```bash
git worktree add ../rppl-release-dry-run HEAD && cd ../rppl-release-dry-run
printf '%s' '{"body":"## Notes\n* Something new"}' > /tmp/release.json
CI_TAG=v1.2.3-beta.1 RPPL_RELEASE_JSON=/tmp/release.json bash ci_scripts/ci_post_clone.sh
xcodebuild -project Rppl.xcodeproj -scheme Rppl -showBuildSettings | grep MARKETING_VERSION
cd - && git worktree remove --force ../rppl-release-dry-run
```

Unit tests: `python3 -m unittest discover -s scripts/ci -p 'test_*.py'` (also run on PRs by the release preflight workflow).

## Pitfalls

| Pitfall | What to know |
|---------|--------------|
| No "release published" trigger | Xcode Cloud starts from tags. Publishing a release creates the tag; drafts create none. Pushing a bare `v*` tag also builds (no notes, so the commit-list fallback is used). Moving a tag rebuilds. |
| Tag filter is prefix only | `v` also matches `vNext`; the script rejects it. |
| Docs-only tagged commit | Nightly's skip logic would cancel it. Tag builds bypass that logic (`CI_TAG`), and the Release workflow must not have Custom Conditions. |
| Internal-only archive | Builds from "TestFlight (Internal Testing Only)" can never go external or to the App Store. |
| Beta App Review | First build of each version waits for review. Test Information must be filled in or external distribution fails. |
| Auto-cancel Builds | On by default; two quick tags would cancel the first. Off for Release. |
| Watch version mismatch | iPhone and Watch marketing versions must match; the script sets all of them. |
| Build number collisions | Xcode Cloud's counter is per app. Set *Next Build Number* above any manual upload. |
| Release edited after publish | The build already read it. Use **Rebuild**; notes are fetched again. |
| Token expired | Warning in the Post-Clone log, fallback notes. Rotate the token before its expiry. |
| Nightly version drift | Nightly builds keep the repo's `MARKETING_VERSION` (1.0). Fine before the first App Store release. After a version ships, that train is closed and uploads at or below it are rejected, so bump the repo version (or derive the next one) before the first real release. |
| Signing capabilities | Cloud signing needs HealthKit, WeatherKit, iCloud and the Watch depth entitlement enabled on the App IDs. Nightly already exercises this; keep it green. |
| Build expiry | TestFlight builds expire after 90 days. |
