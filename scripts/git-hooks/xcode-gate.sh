#!/usr/bin/env bash
# Rppl push gate: Core tests, then xcodebuild when app/Core sources changed.
#
# Default (pre-push / `make gate`):
#   - Skip a step when its inputs match the last successful run on this machine
#     (content fingerprint + toolchain, not a time TTL).
#   - Skip xcodebuild when only RpplCore tests changed (app fingerprint ignores Tests/).
#   - Skip `xcodebuild analyze` (slow; little extra signal vs build). Use
#     `make check` or XCODE_GATE_ANALYZE=1 for analyze.
#
# Env:
#   XCODE_GATE_FULL=1      ignore cache; run tests + build + analyze
#   XCODE_GATE_ANALYZE=1   run analyze after build (build still cached if unchanged)
#   XCODE_GATE_NO_CACHE=1  ignore cache; still skip analyze unless FULL/ANALYZE
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/tools/bin:$PATH"

FULL="${XCODE_GATE_FULL:-0}"
ANALYZE="${XCODE_GATE_ANALYZE:-0}"
NO_CACHE="${XCODE_GATE_NO_CACHE:-0}"
if [[ "$FULL" == "1" ]]; then
  ANALYZE=1
  NO_CACHE=1
fi

GIT_COMMON="$(git rev-parse --git-common-dir)"
STAMP_DIR="${GIT_COMMON}/rppl-xcode-gate"
mkdir -p "$STAMP_DIR"
CORE_STAMP="${STAMP_DIR}/core.ok"
APP_STAMP="${STAMP_DIR}/app.ok"
ANALYZE_STAMP="${STAMP_DIR}/analyze.ok"

# Tracked working-tree contents (HEAD blobs would ignore dirty `make gate` edits).
paths_fingerprint() {
  git ls-files -- "$@" | git hash-object --stdin-paths | git hash-object --stdin
}

toolchain_id() {
  local xcode="xcodebuild-missing"
  if command -v xcodebuild >/dev/null 2>&1; then
    xcode="$(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
  fi
  local swift="swift-missing"
  if command -v swift >/dev/null 2>&1; then
    swift="$(swift --version 2>/dev/null | tr '\n' ' ')"
  fi
  printf 'xcode:%s\nswift:%s\n' "$xcode" "$swift" | git hash-object --stdin
}

CORE_FP="$(paths_fingerprint \
  RpplCore/Package.swift \
  RpplCore/Package.resolved \
  RpplCore/Sources \
  RpplCore/Tests \
  RpplCore/coverage-baseline.json \
  scripts/check-core-coverage.py)"

# App compile inputs: Core sources + apps + project. Core *tests* omitted so
# detection-test iteration does not rebuild iOS/Watch.
APP_FP="$(paths_fingerprint \
  Rppl \
  RpplWatch \
  RpplTests \
  Rppl.xcodeproj \
  RpplCore/Package.swift \
  RpplCore/Package.resolved \
  RpplCore/Sources \
  scripts/git-hooks/xcode-gate.sh)"

TOOL_FP="$(toolchain_id)"
CORE_KEY="${CORE_FP} ${TOOL_FP}"
APP_KEY="${APP_FP} ${TOOL_FP}"

stamp_matches() {
  local file="$1"
  local key="$2"
  [[ "$NO_CACHE" != "1" && -f "$file" && "$(cat "$file")" == "$key" ]]
}

run_core_tests() {
  # Tests with coverage, then refuse a drop below RpplCore/coverage-baseline.json.
  echo "==> RpplCore swift test + coverage floor"
  python3 scripts/check-core-coverage.py
  printf '%s\n' "$CORE_KEY" >"$CORE_STAMP"
}

run_xcodebuild() {
  local action="$1"
  echo "==> xcodebuild ${action} (iOS Simulator, embeds Watch)"
  xcodebuild \
    -project Rppl.xcodeproj \
    -scheme Rppl \
    -destination 'generic/platform=iOS Simulator' \
    -quiet \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    ONLY_ACTIVE_ARCH=YES \
    "$action"
}

if stamp_matches "$CORE_STAMP" "$CORE_KEY"; then
  echo "==> RpplCore swift test skipped (inputs unchanged since last successful gate)"
else
  run_core_tests
fi

NEED_BUILD=1
if stamp_matches "$APP_STAMP" "$APP_KEY"; then
  NEED_BUILD=0
  echo "==> xcodebuild build skipped (inputs unchanged since last successful gate)"
fi

if [[ "$NEED_BUILD" == "1" ]]; then
  run_xcodebuild build
  printf '%s\n' "$APP_KEY" >"$APP_STAMP"
  rm -f "$ANALYZE_STAMP"
fi

if [[ "$ANALYZE" == "1" ]]; then
  if stamp_matches "$ANALYZE_STAMP" "$APP_KEY"; then
    echo "==> xcodebuild analyze skipped (inputs unchanged since last successful analyze)"
  else
    run_xcodebuild analyze
    printf '%s\n' "$APP_KEY" >"$ANALYZE_STAMP"
  fi
fi

echo "==> xcode-gate OK"
