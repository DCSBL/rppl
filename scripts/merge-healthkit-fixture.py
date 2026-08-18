#!/usr/bin/env python3
"""Merge health samples from a full export into a time-window subset for HK debug inject.

Sources (gitignored Exports/):
  - subset: rppl-0C7BAFDD-2026-08-16T13-31-25Z_2026-08-16T13-54-38Z.json
  - full:   0C7BAFDD-C055-483B-8B24-CEBEC02EDE53.json

Output:
  - Rppl/Resources/HealthKitInjectFixture.json (bundled in iPhone app)
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def exports_dir() -> Path:
    for candidate in (REPO_ROOT / "Exports", REPO_ROOT.parent / "rppl" / "Exports"):
        if candidate.is_dir():
            return candidate
    return REPO_ROOT / "Exports"


SUBSET_NAME = "rppl-0C7BAFDD-2026-08-16T13-31-25Z_2026-08-16T13-54-38Z.json"
FULL_NAME = "0C7BAFDD-C055-483B-8B24-CEBEC02EDE53.json"
OUT_PATH = REPO_ROOT / "Rppl" / "Resources" / "HealthKitInjectFixture.json"
LOCATION_STRIDE = 20  # keep inject bundle under pre-commit size gate


def parse_ts(value: str) -> datetime:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value).astimezone(timezone.utc)


def main() -> int:
    exports = exports_dir()
    subset_path = exports / SUBSET_NAME
    full_path = exports / FULL_NAME
    if not subset_path.is_file():
        print(f"Missing subset: {subset_path}", file=sys.stderr)
        return 1
    if not full_path.is_file():
        print(f"Missing full export: {full_path}", file=sys.stderr)
        return 1

    with subset_path.open() as handle:
        subset = json.load(handle)
    with full_path.open() as handle:
        full = json.load(handle)

    manifest = subset["manifest"]
    start = parse_ts(manifest["startedAt"])
    end = parse_ts(manifest["endedAt"])

    health = []
    for row in full.get("health") or []:
        ts = parse_ts(row["timestamp"])
        if start <= ts <= end:
            health.append(row)

    locations = subset.get("locations") or []
    if LOCATION_STRIDE > 1 and len(locations) > LOCATION_STRIDE:
        locations = locations[::LOCATION_STRIDE]

    merged = {
        "manifest": manifest,
        "detections": subset.get("detections") or [],
        "locations": locations,
        "motion": subset.get("motion") or [],
        "health": health,
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w") as handle:
        json.dump(merged, handle, separators=(",", ":"))

    size_mb = OUT_PATH.stat().st_size / (1024 * 1024)
    print(
        f"Wrote {OUT_PATH.relative_to(REPO_ROOT)} "
        f"({len(health)} health rows, {len(merged['locations'])} locations, "
        f"{len(merged['detections'])} detections, {size_mb:.2f} MiB)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
