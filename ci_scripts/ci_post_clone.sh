#!/usr/bin/env bash
set -euo pipefail

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(git rev-parse --show-toplevel)}"
cd "$REPO"

# The only Xcode Cloud workflow is Release, started by a Git tag (GitHub release).
# Free compute minutes are limited, so an untagged start (manual start on a branch,
# a stray workflow) stops here instead of archiving a 1.0 build. PRs are tested on GitHub.
# Sets version + TestFlight What to Test; a bad tag fails the build (see Docs/Release.md).
if [[ -z "${CI_TAG:-}" ]]; then
  echo "error: CI_TAG is not set. This repo only builds release tags in Xcode Cloud (Docs/Release.md)." >&2
  exit 1
fi

echo "Tag build (${CI_TAG}) — preparing release."
python3 scripts/ci/prepare_release.py --tag "$CI_TAG"

# Test the tagged commit before Archive: main can differ from every green PR. A failure here
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
