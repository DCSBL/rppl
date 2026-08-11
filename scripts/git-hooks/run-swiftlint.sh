#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$ROOT/tools/bin:$PATH"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint not found."
  echo "Install: brew install swiftlint"
  echo "Or place a swiftlint binary at tools/bin/swiftlint"
  exit 1
fi

swiftlint lint --strict --config .swiftlint.yml
