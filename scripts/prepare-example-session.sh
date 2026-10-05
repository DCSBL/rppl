#!/usr/bin/env bash
# Compile a Share-export JSON into the bundled empty-state example session.
#
# Writes the slim, precompiled example (stats in `derived`, GPS trimmed to the set map budget)
# to Rppl/Resources/Exports/ and RpplWatch/Resources/Exports/, and sets the manifest
# activityCode to "Example session" (UI title).
#
# Needed after a Share export change or a SessionAnalyzer.version bump. The original export
# lives in git history: git show 7807101:Rppl/Resources/Exports/FBDC7D8C-8FEA-47B6-911B-00E94A8A496C.json
#
# Usage: scripts/prepare-example-session.sh ~/Downloads/FBDC7D8C-8FEA-47B6-911B-00E94A8A496C.json
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 <Share export JSON>" >&2
  exit 2
fi
input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

exec swift run -c release --package-path "$root/tools/example-session-compiler" \
  example-session-compiler "$input" "$root"
