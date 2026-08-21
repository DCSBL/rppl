#!/usr/bin/env python3
"""Prepare a Share-export JSON for the empty-state example session.

Reads a SessionTransferPackage export, sets manifest.activityCode to
\"Example session\" (UI title), leaves every other field unchanged, and writes
to Rppl/Resources/Exports/ for bundling.

Usage:
  python3 scripts/prepare-example-session.py \\
    ~/Downloads/FBDC7D8C-8FEA-47B6-911B-00E94A8A496C.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = (
    REPO_ROOT
    / "Rppl"
    / "Resources"
    / "Exports"
    / "FBDC7D8C-8FEA-47B6-911B-00E94A8A496C.json"
)
EXAMPLE_TITLE = "Example session"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "input",
        type=Path,
        help="Phone Share export SessionTransferPackage JSON",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=DEFAULT_OUT,
        help=f"Bundled resource path (default: {DEFAULT_OUT})",
    )
    args = parser.parse_args()

    if not args.input.is_file():
        print(f"missing input: {args.input}", file=sys.stderr)
        return 1

    with args.input.open() as handle:
        package = json.load(handle)

    if not isinstance(package, dict) or "manifest" not in package:
        print("input is not a SessionTransferPackage (missing manifest)", file=sys.stderr)
        return 1

    manifest = package["manifest"]
    if not isinstance(manifest, dict):
        print("manifest must be an object", file=sys.stderr)
        return 1

    manifest["activityCode"] = EXAMPLE_TITLE

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as handle:
        json.dump(package, handle, separators=(",", ":"), ensure_ascii=False)
        handle.write("\n")

    session_id = manifest.get("sessionId", "?")
    print(f"wrote {args.output} ({args.output.stat().st_size} bytes)")
    print(f"sessionId={session_id} activityCode={EXAMPLE_TITLE!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
