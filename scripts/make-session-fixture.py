#!/usr/bin/env python3
"""Turn a phone Share export into an annotated session fixture for RpplCore tests.

Keeps what detection and map tests need, in the order the Watch recorded it:

- manifest (tester id replaced),
- locations in on-disk order — the Watch appends fixes as they arrive, so this is
  arrival order, including repeated and late fixes,
- the detections the Watch wrote live (`recordedDetections`),
- `annotations`: hand-written ground truth (good sets, bad sets, bad fixes, late
  deliveries, GPS gaps, labelled events such as jumps and falls). Re-running keeps the
  annotations already in the output,
- `motion`: device motion rows exactly as the Watch wrote them, only around `event`
  annotations (± MOTION_PAD_S), so labelled jumps and falls keep their 25 Hz signal without
  carrying the whole session. Re-run after adding events to refresh the slices.

An export that carries every stream twice (phone import appended a re-sent
transfer) is collapsed to one copy.

Usage:
  python3 scripts/make-session-fixture.py EXPORT.json NAME \\
    [--description "..."]

Writes RpplCore/Tests/RpplCoreTests/Fixtures/Sessions/NAME.json. Annotation
format and test semantics: RpplCore/Tests/RpplCoreTests/Fixtures/Sessions/README.md
"""

from __future__ import annotations

import argparse
import base64
import json
import struct
import sys
import zlib
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = REPO_ROOT / "RpplCore" / "Tests" / "RpplCoreTests" / "Fixtures" / "Sessions"

LOCATION_KEYS = ("timestamp", "latitude", "longitude", "horizontalAccuracy", "speed", "course")
ROUNDING = {"latitude": 7, "longitude": 7, "horizontalAccuracy": 2, "speed": 3, "course": 1}
MOTION_PAD_S = 2.0


def collapse_doubled(items: list) -> tuple[list, bool]:
    half = len(items) // 2
    if items and len(items) % 2 == 0 and items[:half] == items[half:]:
        return items[:half], True
    return items, False


def slim_location(sample: dict) -> dict:
    out = {}
    for key in LOCATION_KEYS:
        if key not in sample or sample[key] is None:
            continue
        value = sample[key]
        if key in ROUNDING:
            value = round(value, ROUNDING[key])
        out[key] = value
    return out


def parse_ts(value: str) -> float:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def motion_rows(package: dict) -> list[dict]:
    """`motionFramesZlib`: `[UInt32 BE length][raw deflate JSONL]` frames (CompressedJSONLFrames)."""
    blob = package.get("motionFramesZlib")
    if not blob:
        return list(package.get("motion") or [])
    raw = base64.b64decode(blob)
    offset, chunks = 0, []
    while offset + 4 <= len(raw):
        (length,) = struct.unpack(">I", raw[offset : offset + 4])
        chunks.append(zlib.decompress(raw[offset + 4 : offset + 4 + length], -15))
        offset += 4 + length
    return [json.loads(line) for line in b"".join(chunks).decode().splitlines() if line.strip()]


def motion_around_events(rows: list[dict], annotations: list[dict]) -> list[dict]:
    windows = [
        (parse_ts(a["start"]) - MOTION_PAD_S, parse_ts(a["end"]) + MOTION_PAD_S)
        for a in annotations
        if a.get("kind") == "event" and a.get("start") and a.get("end")
    ]
    return [row for row in rows if any(start <= parse_ts(row["t"]) <= end for start, end in windows)]


def dump(fixture: dict) -> str:
    """One location / detection per line so diffs and reviews stay readable."""
    lines = ["{"]
    keys = list(fixture.keys())
    for index, key in enumerate(keys):
        value = fixture[key]
        comma = "," if index < len(keys) - 1 else ""
        if key in ("locations", "recordedDetections", "annotations", "motion") and isinstance(value, list):
            lines.append(f'  "{key}": [')
            for row_index, row in enumerate(value):
                row_comma = "," if row_index < len(value) - 1 else ""
                lines.append("    " + json.dumps(row, ensure_ascii=False) + row_comma)
            lines.append("  ]" + comma)
        else:
            lines.append(f'  "{key}": ' + json.dumps(value, ensure_ascii=False) + comma)
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("export", type=Path, help="Phone Share export (SessionTransferPackage JSON)")
    parser.add_argument("name", help="Fixture name, e.g. downunder-2026-09-30")
    parser.add_argument("--description", default="", help="One-line description")
    args = parser.parse_args()

    package = json.loads(args.export.read_text(encoding="utf-8"))
    locations, doubled = collapse_doubled(package.get("locations", []))
    detections, _ = collapse_doubled(package.get("detections", []))

    manifest = dict(package["manifest"])
    manifest["testerId"] = "fixture"

    out_path = OUT_DIR / f"{args.name}.json"
    annotations = []
    description = args.description
    if out_path.exists():
        existing = json.loads(out_path.read_text(encoding="utf-8"))
        annotations = existing.get("annotations", [])
        description = description or existing.get("description", "")

    fixture = {
        "name": args.name,
        "description": description,
        "exportWasDoubled": doubled,
        "manifest": manifest,
        "annotations": annotations,
        "recordedDetections": detections,
        "locations": [slim_location(sample) for sample in locations],
    }
    motion, _ = collapse_doubled(motion_rows(package))
    motion = motion_around_events(motion, annotations)
    if motion:
        fixture["motion"] = motion
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path.write_text(dump(fixture), encoding="utf-8")
    print(
        f"wrote {out_path.relative_to(REPO_ROOT)}: {len(fixture['locations'])} locations, "
        f"{len(detections)} detections, {len(annotations)} annotations, {len(motion)} motion rows"
        + (" (export was doubled — collapsed)" if doubled else ""),
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
