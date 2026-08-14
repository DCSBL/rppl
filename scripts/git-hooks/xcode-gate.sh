#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/tools/bin:$PATH"

echo "==> RpplCore swift test"
(
  cd RpplCore
  swift test
)

echo "==> xcodebuild build (iOS Simulator, embeds Watch)"
xcodebuild \
  -project Rppl.xcodeproj \
  -scheme Rppl \
  -destination 'generic/platform=iOS Simulator' \
  -quiet \
  build

echo "==> xcodebuild analyze (iOS Simulator)"
# generic destination avoids brittle device-name matching across Xcode versions
xcodebuild \
  -project Rppl.xcodeproj \
  -scheme Rppl \
  -destination 'generic/platform=iOS Simulator' \
  -quiet \
  analyze

echo "==> xcode-gate OK"
