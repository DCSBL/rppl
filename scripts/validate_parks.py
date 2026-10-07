#!/usr/bin/env python3
"""Validate park YAML files against schema/park.schema.json plus sanity checks.

Usage:
    python3 scripts/validate_parks.py [park.yaml ...]

With no arguments, validates every file under
RpplCore/Sources/RpplCore/Resources/Parks/*.yaml. Exits non-zero (and prints
one line per problem) if any file fails.

Checks, per the CI-validation issue:
  - YAML syntax (YAML lint)
  - Native block-style YAML: no JSON-like `{ }` or `[ ]` collections (scripts/format_parks.py converts)
  - JSON-schema validation against schema/park.schema.json
  - Sanity: duplicate `id` across files, lat/lon out of range, a cable with
    fewer than 2 points, obvious placeholder/TODO values
  - No em dash (—) or en dash (–) anywhere in the file, including comments, and no
    hyphen used as a dash in description/note text (Docs/ParkDescriptions.md)
  - Dead data the app ignores or hides: `author: Rppl`, `numbered` without slots,
    `hours_unknown`, a rule label that only repeats its month
  - Languages: per-language text needs `languages`, and with several languages every free
    `per` / `note` has a variant for each (the plain units person/hour/day/session excepted)
  - One price per name (group amounts as options) and one link per kind
  - Comments stay short: at most 3 lines in a row and no URLs (sources go in the PR
    description, not in the file)

Past dates in opening rules or exceptions are accepted; tidying them is cleanup work.
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

from format_parks import flow_spots

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = REPO_ROOT / "schema" / "park.schema.json"
PARKS_DIR = REPO_ROOT / "RpplCore" / "Sources" / "RpplCore" / "Resources" / "Parks"

MONTH_NAMES = {
    "january", "february", "march", "april", "may", "june",
    "july", "august", "september", "october", "november", "december",
}  # fmt: skip

# `per` values the app translates itself (ParkPriceUnit in ParkModels.swift): no language variants needed.
UNITS = {"person", "hour", "day", "session"}

# Free-text fields written per Docs/ParkDescriptions.md. `history` entries are changelog lines, not copy.
PROSE_KEYS = {"description", "note"}
DASH_AS_PUNCTUATION = re.compile(r"\S\s+-\s+\S")

MAX_COMMENT_LINES = 3
URL_IN_COMMENT = re.compile(r"https?://|www\.", re.IGNORECASE)
BLOCK_SCALAR_HEADER = re.compile(r"[:\-]\s+[|>][+\-0-9]*$")

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


def check_block_style(raw: str) -> list[str]:
    """Native YAML only: block style, never the JSON-like `{ a: 1 }` or `[a, b]`."""
    lines = [line for line, _ in flow_spots(raw)]
    if not lines:
        return []
    shown = ", ".join(str(line) for line in lines[:8]) + (", ..." if len(lines) > 8 else "")
    return [
        f"flow style (JSON-like {{ }} or [ ]) on line(s) {shown}; "
        "use block style, `python3 scripts/format_parks.py <file>` converts it"
    ]


def check_dashes(raw: str) -> list[str]:
    """Em and en dashes read as AI-generated filler in park copy; use a hyphen or two sentences."""
    problems = []
    for line_number, line in enumerate(raw.splitlines(), start=1):
        for dash, name in (("—", "em dash"), ("–", "en dash")):
            if dash in line:
                problems.append(f"{name} ({dash}) on line {line_number}: {line.strip()!r}")
    return problems


def check_prose_dashes(data) -> list[str]:
    """A spaced hyphen is a dash in disguise; split the sentence or use a comma (ranges stay unspaced)."""
    problems = []
    for path, text in iter_strings(data):
        if path.startswith("$.history"):
            continue
        parts = [part.split("[")[0] for part in path.split(".")]
        # `note: { nl: ..., en: ... }`: the variant's key is a language, the field is one level up.
        key = parts[-2] if len(parts) > 1 and parts[-2] in PROSE_KEYS else parts[-1]
        if key in PROSE_KEYS and DASH_AS_PUNCTUATION.search(text):
            problems.append(f"hyphen used as a dash at {path}: {text!r}")
    return problems


def comment_start(line: str) -> int | None:
    """Index of the `#` that starts a comment on this line, or None. Quoted `#` and `#` inside a word are text."""
    quote = None
    for index, char in enumerate(line):
        if quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "#" and (index == 0 or line[index - 1].isspace()):
            return index
    return None


def key_indent(line: str) -> int:
    """Column of the key on this line, counting any `- ` list markers in front of it."""
    rest = line.lstrip(" ")
    indent = len(line) - len(rest)
    while rest.startswith("- "):
        stripped = rest[2:].lstrip(" ")
        indent += len(rest) - len(stripped)
        rest = stripped
    return indent


def find_comments(raw: str) -> list[tuple[int, str, bool]]:
    """(line number, comment text, on its own line) for every real YAML comment.

    A `#` inside a block scalar (`description: >-`) is text, not a comment.
    """
    comments: list[tuple[int, str, bool]] = []
    scalar_indent: int | None = None
    for number, line in enumerate(raw.splitlines(), start=1):
        indent = len(line) - len(line.lstrip(" "))
        if scalar_indent is not None:
            if not line.strip() or indent > scalar_indent:
                continue
            scalar_indent = None
        start = comment_start(line)
        code = line if start is None else line[:start]
        if start is not None:
            comments.append((number, line[start:], not code.strip()))
        if BLOCK_SCALAR_HEADER.search(code.rstrip()):
            scalar_indent = key_indent(line)
    return comments


def check_comments(raw: str) -> list[str]:
    """Comments only for a non-obvious data decision: short, and no source URLs."""
    problems = []
    run = 0
    previous = 0
    for number, text, own_line in find_comments(raw):
        if URL_IN_COMMENT.search(text):
            problems.append(f"URL in comment on line {number}: sources belong in the PR description")
        run = run + 1 if own_line and number == previous + 1 else 1
        previous = number if own_line else 0
        if run == MAX_COMMENT_LINES + 1:
            problems.append(
                f"comment block from line {number - MAX_COMMENT_LINES} is longer than {MAX_COMMENT_LINES} lines; "
                "keep a comment to the one thing a reader could get wrong"
            )
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


def normalized_key(text: str) -> str:
    """Case and repeated spaces do not make a different name (same rule as the editor's link kinds)."""
    return " ".join(text.split()).lower()


def check_dead_data(data: dict) -> list[str]:
    """Keys the app ignores or hides: they only add noise to a file."""
    problems = []
    author = data.get("author")
    if isinstance(author, str) and normalized_key(author) == "rppl":
        problems.append("author 'Rppl' is the default credit and the app hides it; omit the key")

    opening = data.get("opening")
    if isinstance(opening, dict):
        if "hours_unknown" in opening:
            problems.append("opening.hours_unknown is ignored: no rules or slots already means unknown hours")
        if "numbered" in opening and not opening.get("slots"):
            problems.append("opening.numbered only changes how slots are labelled; omit it without slots")
        for index, rule in enumerate(opening.get("rules") or []):
            label = rule.get("label") if isinstance(rule, dict) else None
            if isinstance(label, str) and normalized_key(label) in MONTH_NAMES:
                problems.append(
                    f"opening.rules[{index}].label {label!r} only repeats its month heading, "
                    "which the app hides; drop the label"
                )
    return problems


def language_code(tag: str) -> str:
    return re.split(r"[-_]", str(tag).lower())[0]


def repeated_codes(tags) -> list[str]:
    """Language codes that more than one of `tags` stands for (`nl` and `nl-BE` are one language)."""
    codes = [language_code(tag) for tag in tags]
    return sorted({code for code in codes if codes.count(code) > 1})


def check_languages(data: dict) -> list[str]:
    """Per-language text (`per`, `note` as a map) needs `languages`, and with several languages
    every free text needs a variant for each of them (the app shows the units in `UNITS` itself)."""
    declared = data.get("languages")
    codes = {language_code(tag) for tag in declared} if isinstance(declared, list) else set()
    problems = []
    if isinstance(declared, list) and repeated_codes(declared):
        problems.append(f"languages {declared} list {repeated_codes(declared)} more than once; one tag per language")
    for index, price in enumerate(data.get("prices") or []):
        for o_index, option in enumerate(price.get("options") or [] if isinstance(price, dict) else []):
            for field in ("per", "note"):
                value = option.get(field) if isinstance(option, dict) else None
                where = f"prices[{index}].options[{o_index}].{field}"
                if isinstance(value, str):
                    if len(codes) > 1 and not (field == "per" and value in UNITS):
                        problems.append(
                            f"{where} is plain text {value!r} but the park lists several languages; "
                            "give it a variant per language"
                        )
                    continue
                if not isinstance(value, dict):
                    continue
                if not codes:
                    problems.append(f"{where} has language variants but the park has no `languages` list")
                    continue
                for tag in value:
                    if language_code(tag) not in codes:
                        problems.append(f"{where} has variant {tag!r} which is not in languages {declared}")
                if repeated_codes(value):
                    problems.append(f"{where} has more than one variant for {repeated_codes(value)}")
                have = {language_code(tag) for tag in value}
                missing = [tag for tag in declared if language_code(tag) not in have]
                if missing:
                    problems.append(f"{where} has no variant for {missing}")
    return problems


def check_duplicates(data: dict) -> list[str]:
    """One price per name (several amounts are options of it) and one link per kind."""
    problems = []
    for section, key, advice in (
        ("prices", "name", "group the amounts as options of one price"),
        ("links", "kind", "keep one link per kind"),
    ):
        seen: set[str] = set()
        for entry in data.get(section) or []:
            value = entry.get(key) if isinstance(entry, dict) else None
            if not isinstance(value, str):
                continue
            normalized = normalized_key(value)
            if normalized in seen:
                problems.append(f"{section} repeat {key} {value!r}: {advice}")
            seen.add(normalized)
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
    problems += check_prose_dashes(data)
    problems += check_dead_data(data)
    problems += check_duplicates(data)
    problems += check_languages(data)
    return problems


def validate_file(path: Path, schema: dict) -> tuple[dict | None, list[str]]:
    problems: list[str] = []
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, [f"could not read file: {exc}"]

    problems += check_dashes(raw)
    problems += check_comments(raw)

    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        return None, [f"YAML syntax error: {exc}"]

    if not isinstance(data, dict):
        return None, ["top-level YAML document must be a mapping"]

    problems += check_block_style(raw)
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
