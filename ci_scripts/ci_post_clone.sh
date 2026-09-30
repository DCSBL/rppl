#!/usr/bin/env bash
set -euo pipefail

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(git rev-parse --show-toplevel)}"
cd "$REPO"

# Release build (GitHub release -> tag). Key off CI_TAG, not CI_START_CONDITION:
# Apple documents no tag value for it, and a docs-only tagged commit must still ship.
# Sets version + TestFlight What to Test; a bad tag fails the build (see Docs/Release.md).
if [[ -n "${CI_TAG:-}" ]]; then
  echo "Tag build (${CI_TAG}) — preparing release."
  python3 scripts/ci/prepare_release.py --tag "$CI_TAG"
  exit 0
fi

# shellcheck source=../scripts/ci/build-related-paths.sh
source "$(dirname "$0")/../scripts/ci/build-related-paths.sh"

case "${CI_START_CONDITION:-}" in
  schedule)
    changed="$(git log --since="24 hours ago" --format=format: --name-only | sort -u)"
    ;;
  push)
    git fetch --deepen 1 --quiet 2>/dev/null || true
    changed="$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)"
    ;;
  manual|manual_rebuild|pr_open|pr_update|"")
    echo "Non-schedule / verification start — continuing build."
    exit 0
    ;;
  *)
    echo "Unknown CI_START_CONDITION=${CI_START_CONDITION} — continuing build."
    exit 0
    ;;
esac

if rppl_any_build_related_path <<< "$changed"; then
  echo "Build-related changes detected — continuing."
  exit 0
else
  echo "No build-related changes — skipping archive/TestFlight."
  exit 1
fi
