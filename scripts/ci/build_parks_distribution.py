#!/usr/bin/env python3
"""Build the over-the-air park data for the `parks-distribution` branch.

Usage:
    python3 scripts/ci/build_parks_distribution.py PARKS_DIR OUT_DIR [--previous MANIFEST_JSON]

Copies every `*.yaml` in PARKS_DIR to OUT_DIR byte for byte and writes OUT_DIR/manifest.json
(format in RpplCore ParkDataManifest). With --previous, `dataVersion` continues from that
manifest, its kill switch (`enabled`) is kept, and nothing is written when the park files are
unchanged. Prints `changed=true` or `changed=false` (also appended to $GITHUB_OUTPUT).
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path

MANIFEST_FORMAT = 1


def read_version(text: str, name: str) -> int:
    match = re.search(r"^version:\s*(\d+)\s*$", text, re.MULTILINE)
    if not match:
        sys.exit(f"{name}: no top-level `version:`")
    return int(match.group(1))


def collect(parks_dir: Path) -> tuple[list[dict], list[int]]:
    entries, versions = [], []
    for path in sorted(parks_dir.glob("*.yaml")):
        data = path.read_bytes()
        entries.append({"id": path.stem, "file": path.name, "sha256": hashlib.sha256(data).hexdigest()})
        versions.append(read_version(data.decode("utf-8"), path.name))
    return entries, versions


def build(parks_dir: Path, out_dir: Path, previous: dict | None, now: datetime.datetime) -> bool:
    entries, versions = collect(parks_dir)
    if not entries:
        sys.exit(f"no park files in {parks_dir}")
    if previous and previous.get("format") == MANIFEST_FORMAT and previous.get("parks") == entries:
        return False
    manifest = {
        "format": MANIFEST_FORMAT,
        "dataVersion": (previous or {}).get("dataVersion", 0) + 1,
        "publishedAt": now.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "enabled": (previous or {}).get("enabled", True),
        "minAppSchema": min(versions),
        "maxAppSchema": max(versions),
        "parks": entries,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in out_dir.glob("*.yaml"):
        stale.unlink()
    for entry in entries:
        shutil.copyfile(parks_dir / entry["file"], out_dir / entry["file"])
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("parks_dir", type=Path)
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("--previous", type=Path)
    args = parser.parse_args()
    previous = None
    if args.previous and args.previous.exists():
        previous = json.loads(args.previous.read_text(encoding="utf-8"))
    changed = build(args.parks_dir, args.out_dir, previous, datetime.datetime.now(datetime.timezone.utc))
    print(f"changed={'true' if changed else 'false'}")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write(f"changed={'true' if changed else 'false'}\n")


if __name__ == "__main__":
    main()
