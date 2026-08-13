#!/usr/bin/env bash
# Smoke-launch RpplMac with a session export. Fails if process dies within settle window.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT="${1:-$ROOT/Exports/0158167A-A54E-45D4-8245-3AAD743F7979.json}"
SETTLE_SEC="${SETTLE_SEC:-4}"

xcodebuild -scheme RpplMac -project "$ROOT/Rppl.xcodeproj" -destination 'platform=macOS' -configuration Debug build -quiet
APP="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Rppl-*/Build/Products/Debug/RpplMac.app | head -1)"
BIN="$APP/Contents/MacOS/RpplMac"

"$BIN" -loadExport "$EXPORT" &
PID=$!
sleep "$SETTLE_SEC"
if kill -0 "$PID" 2>/dev/null; then
  echo "ok: RpplMac still running after ${SETTLE_SEC}s (pid $PID)"
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  exit 0
fi
echo "fail: RpplMac exited early while loading $EXPORT" >&2
wait "$PID" || true
exit 1
