#!/usr/bin/env bash
set -euo pipefail

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(git rev-parse --show-toplevel)}"
cd "$REPO"

# The only Xcode Cloud workflow is Release. It starts on the branch release/X.Y.Z, which
# .github/workflows/release-branch.yml pushes when a GitHub release is published, so every
# build of a version lands in one Build Group. A manual start on a tag also works.
# Free compute minutes are limited, so any other start (a stray workflow, another branch)
# stops here instead of archiving a 1.0 build. PRs are tested on GitHub.
# Sets version + TestFlight What to Test; a bad tag fails the build (see Docs/Release.md).
if [[ -n "${CI_TAG:-}" ]]; then
  echo "Tag build (${CI_TAG}) — preparing release."
  python3 scripts/ci/prepare_release.py --tag "$CI_TAG"
elif [[ "${CI_BRANCH:-}" == release/* ]]; then
  echo "Branch build (${CI_BRANCH}) — preparing release."
  python3 scripts/ci/prepare_release.py --branch "$CI_BRANCH"
else
  echo "error: neither CI_TAG nor a release/X.Y.Z CI_BRANCH is set. This repo only builds releases in Xcode Cloud (Docs/Release.md)." >&2
  exit 1
fi

# Test the released commit before Archive: main can differ from every green PR. A failure here
# fails the build before anything is archived or sent to TestFlight.
# Emergency only: set RPPL_SKIP_TESTS=1 on the Release workflow to ship anyway.
if [[ "${RPPL_SKIP_TESTS:-}" == "1" ]]; then
  echo "warning: RPPL_SKIP_TESTS=1, skipping the pre-archive tests." >&2
  exit 0
fi

echo "Release script tests."
python3 -m unittest discover -s scripts/ci -p 'test_*.py'

# Scratch path outside the checkout keeps RpplCore/.build out of the archive input.
echo "RpplCore tests."
swift test --package-path RpplCore --scratch-path "$(mktemp -d)"
