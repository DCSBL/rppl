#!/usr/bin/env bash
# Copy repo-root LEGAL.md into the iOS app bundle resources (single source of truth).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/LEGAL.md"
DST="$ROOT/Rppl/Resources/LEGAL.md"

if [[ ! -f "$SRC" ]]; then
  echo "sync-legal-md: missing $SRC" >&2
  exit 1
fi

mkdir -p "$(dirname "$DST")"
cp "$SRC" "$DST"

# When run from pre-commit, stage the copy so the commit stays consistent.
if [[ -n "${PRE_COMMIT:-}" ]]; then
  git -C "$ROOT" add -- "$DST"
fi

echo "sync-legal-md: $SRC -> $DST"
