#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/tools/bin:$PATH"

echo "==> WakeTrackerCore swift test"
(
  cd WakeTrackerCore
  swift test
)

echo "==> xcodebuild build (iOS Simulator, embeds Watch)"
xcodebuild \
  -scheme wake-tracker \
  -destination 'generic/platform=iOS Simulator' \
  -quiet \
  build

echo "==> xcodebuild analyze (iOS Simulator)"
# generic destination avoids brittle device-name matching across Xcode versions
xcodebuild \
  -scheme wake-tracker \
  -destination 'generic/platform=iOS Simulator' \
  -quiet \
  analyze

echo "==> xcode-gate OK"
