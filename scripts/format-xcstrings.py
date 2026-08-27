#!/usr/bin/env python3
"""Format Apple String Catalogs (``.xcstrings``) like Xcode.

Xcode / ``xcstringstool`` rewrite catalogs with:

- 2-space indent
- space before every structural colon (``"key" : value``)
- empty objects as a multi-line blank body (not ``{}``)
- UTF-8 with non-ASCII left unescaped
- trailing newline
- existing key order preserved (no sort)

Agent / ``json.dumps`` default style (``"key": value``, compact ``{}``) causes a
whole-file phantom diff the next time Xcode touches the catalog. This script
keeps repo writes aligned with that Xcode form.

Usage::

  python3 scripts/format-xcstrings.py path/to/File.xcstrings
  python3 scripts/format-xcstrings.py --check path/to/File.xcstrings
  python3 scripts/format-xcstrings.py --all
  python3 scripts/format-xcstrings.py --self-test
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def encode_xcstrings(data: object) -> str:
    """Serialize ``data`` to Xcode String Catalog JSON text."""

    def encode(obj: object, level: int) -> str:
        indent = "  " * level
        inner = "  " * (level + 1)
        if isinstance(obj, dict):
            if not obj:
                return "{\n\n" + indent + "}"
            lines: list[str] = []
            items = list(obj.items())
            for index, (key, value) in enumerate(items):
                key_json = json.dumps(key, ensure_ascii=False)
                comma = "," if index < len(items) - 1 else ""
                lines.append(f"{inner}{key_json} : {encode(value, level + 1)}{comma}")
            return "{\n" + "\n".join(lines) + "\n" + indent + "}"
        if isinstance(obj, list):
            if not obj:
                return "[\n\n" + indent + "]"
            lines = []
            for index, value in enumerate(obj):
                comma = "," if index < len(obj) - 1 else ""
                lines.append(f"{inner}{encode(value, level + 1)}{comma}")
            return "[\n" + "\n".join(lines) + "\n" + indent + "]"
        return json.dumps(obj, ensure_ascii=False)

    return encode(data, 0) + "\n"


def format_text(raw: str) -> str:
    return encode_xcstrings(json.loads(raw))


def discover_catalogs(root: Path = REPO_ROOT) -> list[Path]:
    return sorted(
        path
        for path in root.rglob("*.xcstrings")
        if ".build" not in path.parts and "DerivedData" not in path.parts
    )


def process_path(path: Path, *, check: bool) -> bool:
    """Return True when the file already matched (or was written)."""
    raw = path.read_text(encoding="utf-8")
    formatted = format_text(raw)
    if raw == formatted:
        return True
    if check:
        print(f"needs format: {path}", file=sys.stderr)
        return False
    path.write_text(formatted, encoding="utf-8")
    print(f"formatted: {path}")
    return True


def self_test() -> int:
    sample = {
        "sourceLanguage": "en",
        "strings": {
            "": {},
            "Hello": {
                "localizations": {
                    "en": {
                        "stringUnit": {
                            "state": "translated",
                            "value": "Hello",
                        }
                    },
                    "nl": {
                        "stringUnit": {
                            "state": "translated",
                            "value": "Hallo",
                        }
                    },
                }
            },
        },
        "version": "1.0",
    }
    text = encode_xcstrings(sample)
    expected = (
        "{\n"
        '  "sourceLanguage" : "en",\n'
        '  "strings" : {\n'
        '    "" : {\n'
        "\n"
        "    },\n"
        '    "Hello" : {\n'
        '      "localizations" : {\n'
        '        "en" : {\n'
        '          "stringUnit" : {\n'
        '            "state" : "translated",\n'
        '            "value" : "Hello"\n'
        "          }\n"
        "        },\n"
        '        "nl" : {\n'
        '          "stringUnit" : {\n'
        '            "state" : "translated",\n'
        '            "value" : "Hallo"\n'
        "          }\n"
        "        }\n"
        "      }\n"
        "    }\n"
        "  },\n"
        '  "version" : "1.0"\n'
        "}\n"
    )
    assert text == expected, repr(text)
    assert json.loads(text) == sample

    # Byte-stable on catalogs already in Xcode form (no empty entries).
    core = REPO_ROOT / "RpplCore/Sources/RpplCore/Resources/Localizable.xcstrings"
    if core.is_file():
        raw = core.read_text(encoding="utf-8")
        if '" : ' in raw:
            assert format_text(raw) == raw, "Core Localizable must round-trip"

    print("self-test ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help=".xcstrings files to format (default: none; use --all)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help=f"format every *.xcstrings under {REPO_ROOT}",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if any file would change (no writes)",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run built-in assertions and exit",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    paths = list(args.paths)
    if args.all:
        paths.extend(discover_catalogs())
    if not paths:
        parser.error("pass .xcstrings paths, or --all / --self-test")

    ok = True
    seen: set[Path] = set()
    for path in paths:
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        if not path.is_file():
            print(f"missing: {path}", file=sys.stderr)
            ok = False
            continue
        if not process_path(path, check=args.check):
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
