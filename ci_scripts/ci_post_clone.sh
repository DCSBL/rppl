#!/usr/bin/env bash
set -euo pipefail

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(git rev-parse --show-toplevel)}"
cd "$REPO"

# The only Xcode Cloud workflow is Release, started by a Git tag (GitHub release).
# Free compute minutes are limited, so an untagged start (manual start on a branch,
# a stray workflow) stops here instead of archiving a 1.0 build. Tests run on GitHub.
# Sets version + TestFlight What to Test; a bad tag fails the build (see Docs/Release.md).
if [[ -z "${CI_TAG:-}" ]]; then
  echo "error: CI_TAG is not set. This repo only builds release tags in Xcode Cloud (Docs/Release.md)." >&2
  exit 1
fi

echo "Tag build (${CI_TAG}) — preparing release."
python3 scripts/ci/prepare_release.py --tag "$CI_TAG"
