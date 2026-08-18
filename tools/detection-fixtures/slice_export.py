#!/usr/bin/env python3
"""Slice a phone Share export JSON to a time window (for detection fixtures)."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def parse_ts(value: str) -> datetime:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value)


def iso_utc(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def speed_mps(record: dict) -> float | None:
    raw = record.get("speedMps", record.get("speed"))
    return float(raw) if raw is not None else None


def dedupe_locations(records: list[dict]) -> list[dict]:
    seen: set[tuple] = set()
    out: list[dict] = []
    for record in records:
        key = (
            record.get("timestamp"),
            speed_mps(record),
            record.get("horizontalAccuracy") or record.get("horizontalAccuracyM"),
        )
        if key in seen:
            continue
        seen.add(key)
        out.append(
            {
                "timestamp": record["timestamp"],
                "latitude": record.get("latitude"),
                "longitude": record.get("longitude"),
                "horizontalAccuracy": record.get("horizontalAccuracy")
                or record.get("horizontalAccuracyM"),
                "speed": speed_mps(record),
            }
        )
    return out


def records_in_window(records: list[dict], start: datetime, end: datetime) -> list[dict]:
    kept: list[dict] = []
    for record in records:
        ts = parse_ts(record["timestamp"])
        if start <= ts <= end:
            kept.append(record)
    return kept


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Full SessionTransferPackage JSON")
    parser.add_argument("--start", required=True, help="ISO start (inclusive)")
    parser.add_argument("--end", required=True, help="ISO end (inclusive)")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output fixture path")
    parser.add_argument("--name", default=None, help="Fixture name label")
    parser.add_argument(
        "--expected-enters",
        type=int,
        default=None,
        help="Expected ride_enter count under current thresholds",
    )
    args = parser.parse_args()

    with args.input.open() as f:
        data = json.load(f)

    start = parse_ts(args.start)
    end = parse_ts(args.end)
    manifest = dict(data["manifest"])
    manifest["startedAt"] = iso_utc(start)
    manifest["endedAt"] = iso_utc(end)

    locations = dedupe_locations(records_in_window(data.get("locations") or [], start, end))
    name = args.name or args.output.stem

    fixture = {
        "name": name,
        "manifest": manifest,
        "locations": locations,
        "expectedRideEnters": args.expected_enters if args.expected_enters is not None else 1,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as f:
        json.dump(fixture, f, separators=(",", ":"))

    print(f"Wrote {args.output} ({len(locations)} locations, {args.output.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
