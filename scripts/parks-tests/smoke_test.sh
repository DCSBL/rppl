#!/usr/bin/env bash
# Smoke test for scripts/validate_parks.py: the one valid fixture must pass,
# each invalid fixture must fail. Run from the repo root:
#   bash scripts/parks-tests/smoke_test.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
FIXTURES=scripts/parks-tests/fixtures
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

# Must fail, and say why: the message proves the fixture hit its own check, not another one.
check_fails_with() {
  local out
  out=$(python3 scripts/validate_parks.py "$FIXTURES/$1" 2>&1 || true)
  if grep -qF -- "$2" <<<"$out"; then
    echo "ok:   $1 failed with '$2'"
  else
    echo "FAIL: $1 was expected to fail with '$2', got:"
    echo "$out"
    FAIL=1
  fi
}

check_passes valid.yaml
check_passes accepted.yaml
check_passes languages-ok.yaml
check_fails invalid_coords.yaml
check_fails short_cable.yaml
check_fails placeholder.yaml
check_fails_with dead-author.yaml "author 'Rppl'"
check_fails_with dead-numbered.yaml "numbered only changes"
check_fails_with dead-month-label.yaml "only repeats its month heading"
check_fails_with duplicate-prices.yaml "prices repeat name"
check_fails_with duplicate-links.yaml "links repeat kind"
check_fails_with comment-url.yaml "URL in comment"
check_fails_with comment-block.yaml "longer than 3 lines"
check_fails_with en-dash.yaml "en dash"
check_fails_with spaced-hyphen.yaml "hyphen used as a dash"
check_fails_with languages-unlisted.yaml "not in languages"
check_fails_with languages-missing.yaml "no \`languages\` list"

# Duplicate id: neither file is invalid on its own, only together.
if python3 scripts/validate_parks.py "$FIXTURES/duplicate_id_a.yaml" "$FIXTURES/duplicate_id_b.yaml" >/dev/null 2>&1; then
  echo "FAIL: duplicate_id_a.yaml + duplicate_id_b.yaml were expected to fail but passed"
  FAIL=1
else
  echo "ok:   duplicate ids across files failed as expected"
fi

exit "$FAIL"
