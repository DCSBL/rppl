#!/usr/bin/env python3
"""Validate park YAML files against schema/park.schema.json plus sanity checks.

Usage:
    python3 scripts/validate_parks.py [park.yaml ...]

With no arguments, validates every file under
RpplCore/Sources/RpplCore/Resources/Parks/*.yaml. Exits non-zero (and prints
one line per problem) if any file fails.

Checks, per the CI-validation issue:
  - YAML syntax (YAML lint)
  - JSON-schema validation against schema/park.schema.json
  - Sanity: duplicate `id` across files, lat/lon out of range, a cable with
    fewer than 2 points, obvious placeholder/TODO values
  - No em dash (—) anywhere in the file, including comments; use a hyphen
"""

from __future__ import annotations

import datetime
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("error: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

try:
    import jsonschema
except ImportError:
    print("error: jsonschema is required (pip install jsonschema)", file=sys.stderr)
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = REPO_ROOT / "schema" / "park.schema.json"
PARKS_DIR = REPO_ROOT / "RpplCore" / "Sources" / "RpplCore" / "Resources" / "Parks"

# Obvious placeholder/junk markers a real park submission should never contain.
PLACEHOLDER_PATTERNS = [
    re.compile(r"\bTODO\b", re.IGNORECASE),
    re.compile(r"\bFIXME\b", re.IGNORECASE),
    re.compile(r"\bTBD\b", re.IGNORECASE),
    re.compile(r"\bXXX\b"),
    re.compile(r"\blorem ipsum\b", re.IGNORECASE),
    re.compile(r"\bplaceholder\b", re.IGNORECASE),
    re.compile(r"\bchangeme\b", re.IGNORECASE),
    re.compile(r"\bexample\.(com|org|net)\b", re.IGNORECASE),
    re.compile(r"\byour[- ]?park[- ]?name\b", re.IGNORECASE),
]


class ParkError(Exception):
    """A validation problem for one file, carrying its own message."""


def load_schema() -> dict:
    with SCHEMA_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def normalize_dates(value):
    """PyYAML resolves unquoted `2026-09-24` scalars to `datetime.date`, but the
    app decodes these fields as plain strings (see ParkModels.swift) — bring the
    parsed tree back to strings so schema/sanity checks see what the app sees.
    """
    if isinstance(value, (datetime.date, datetime.datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: normalize_dates(sub) for key, sub in value.items()}
    if isinstance(value, list):
        return [normalize_dates(sub) for sub in value]
    return value


def iter_strings(value, path="$"):
    """Yield (path, string) for every string leaf in a nested structure."""
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, dict):
        for key, sub in value.items():
            yield from iter_strings(sub, f"{path}.{key}")
    elif isinstance(value, list):
        for index, sub in enumerate(value):
            yield from iter_strings(sub, f"{path}[{index}]")


def check_placeholders(data) -> list[str]:
    problems = []
    for path, text in iter_strings(data):
        for pattern in PLACEHOLDER_PATTERNS:
            if pattern.search(text):
                problems.append(f"placeholder-looking value at {path}: {text!r}")
                break
    return problems


def check_no_em_dash(raw: str) -> list[str]:
    """Em dashes read as AI-generated filler in park copy; use a hyphen instead."""
    problems = []
    for line_number, line in enumerate(raw.splitlines(), start=1):
        if "—" in line:
            problems.append(f"em dash (—) on line {line_number}: {line.strip()!r}")
    return problems


def check_coordinate_range(lat, lon, path: str) -> list[str]:
    problems = []
    if not isinstance(lat, (int, float)) or not -90 <= lat <= 90:
        problems.append(f"{path}.lat out of range: {lat!r}")
    if not isinstance(lon, (int, float)) or not -180 <= lon <= 180:
        problems.append(f"{path}.lon out of range: {lon!r}")
    if lat == 0 and lon == 0:
        problems.append(f"{path} is (0, 0) — Null Island, almost certainly a placeholder")
    return problems


def check_sanity(data: dict) -> list[str]:
    problems: list[str] = []

    location = data.get("location")
    if isinstance(location, dict):
        problems += check_coordinate_range(location.get("lat"), location.get("lon"), "location")

    for cable_index, cable in enumerate(data.get("cables") or []):
        if not isinstance(cable, dict):
            continue
        points = cable.get("points")
        if points is not None and len(points) < 2:
            name = cable.get("name") or f"#{cable_index}"
            problems.append(f"cable {name!r} has fewer than 2 points ({len(points)})")
        for point_index, point in enumerate(points or []):
            if isinstance(point, dict):
                problems += check_coordinate_range(
                    point.get("lat"), point.get("lon"), f"cables[{cable_index}].points[{point_index}]"
                )

    problems += check_placeholders(data)
    return problems


def validate_file(path: Path, schema: dict) -> tuple[dict | None, list[str]]:
    problems: list[str] = []
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, [f"could not read file: {exc}"]

    problems += check_no_em_dash(raw)

    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        return None, [f"YAML syntax error: {exc}"]

    if not isinstance(data, dict):
        return None, ["top-level YAML document must be a mapping"]

    data = normalize_dates(data)

    validator = jsonschema.Draft202012Validator(schema)
    for error in sorted(validator.iter_errors(data), key=lambda e: list(e.path)):
        location = "$" + "".join(f"[{p!r}]" if isinstance(p, int) else f".{p}" for p in error.path)
        problems.append(f"schema: {location}: {error.message}")

    problems += check_sanity(data)
    return data, problems


def main(argv: list[str]) -> int:
    if not SCHEMA_PATH.exists():
        print(f"error: schema not found at {SCHEMA_PATH}", file=sys.stderr)
        return 2
    schema = load_schema()

    if argv:
        files = [Path(arg) for arg in argv]
    else:
        files = sorted(PARKS_DIR.glob("*.yaml")) if PARKS_DIR.is_dir() else []

    if not files:
        print("no park files to validate")
        return 0

    exit_code = 0
    seen_ids: dict[str, Path] = {}

    for path in files:
        data, problems = validate_file(path, schema)

        if data is not None:
            park_id = data.get("id")
            if isinstance(park_id, str):
                if path.stem != park_id:
                    problems.append(f"id {park_id!r} does not match file name {path.name!r}")
                if park_id in seen_ids:
                    problems.append(f"duplicate id {park_id!r} (already used by {seen_ids[park_id]})")
                else:
                    seen_ids[park_id] = path

        if problems:
            exit_code = 1
            print(f"❌ {path}")
            for problem in problems:
                print(f"   - {problem}")
        else:
            print(f"✅ {path}")

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
