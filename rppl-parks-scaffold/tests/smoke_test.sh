#!/usr/bin/env bash
# Smoke test for scripts/validate_parks.py: the one valid fixture must pass,
# each invalid fixture must fail. Run from the repo root:
#   bash tests/smoke_test.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
FIXTURES=tests/fixtures
FAIL=0

check_passes() {
  if python3 scripts/validate_parks.py "$FIXTURES/$1" >/dev/null; then
    echo "ok:   $1 passed as expected"
  else
    echo "FAIL: $1 was expected to pass but failed"
    FAIL=1
  fi
}

check_fails() {
  if python3 scripts/validate_parks.py "$FIXTURES/$1" >/dev/null 2>&1; then
    echo "FAIL: $1 was expected to fail but passed"
    FAIL=1
  else
    echo "ok:   $1 failed as expected"
  fi
}

check_passes valid.yaml
check_fails invalid_coords.yaml
check_fails short_cable.yaml
check_fails placeholder.yaml

# Duplicate id: neither file is invalid on its own, only together.
if python3 scripts/validate_parks.py "$FIXTURES/duplicate_id_a.yaml" "$FIXTURES/duplicate_id_b.yaml" >/dev/null 2>&1; then
  echo "FAIL: duplicate_id_a.yaml + duplicate_id_b.yaml were expected to fail but passed"
  FAIL=1
else
  echo "ok:   duplicate ids across files failed as expected"
fi

exit "$FAIL"
