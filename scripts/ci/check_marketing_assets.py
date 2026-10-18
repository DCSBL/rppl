#!/usr/bin/env python3
"""Check rendered App Store marketing assets against marketing/marketing.yaml.

Every <folder>/<NN>-<id>.png expected by a format must exist with the exact pixel size, as 8-bit PNG without
alpha (App Store Connect rejects alpha). Usage: check_marketing_assets.py OUT_DIR [marketing.yaml]
"""
import re
import struct
import sys
from pathlib import Path

PNG_SIG = b"\x89PNG\r\n\x1a\n"
NO_ALPHA_COLOR_TYPES = {0, 2, 3}


def png_header(path: Path):
    """(width, height, bit_depth, color_type) from the IHDR chunk."""
    data = path.read_bytes()[:33]
    if data[:8] != PNG_SIG or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    return width, height, depth, color


def _scalar(text: str, key: str, default=None):
    match = re.search(rf"^\s*{re.escape(key)}:\s*(.+?)\s*$", text, re.M)
    return match.group(1).strip("\"'") if match else default


def parse_config(text: str):
    """Minimal reader for marketing.yaml: formats {key: (w, h, folder)}, defaults.formats, slides [(id, formats)].

    Stdlib only so the check runs on the macOS system Python without PyYAML.
    """
    formats = {}
    for key, w, h, folder in re.findall(r"^  ([\w.\-]+): \{ w: (\d+), h: (\d+), folder: ([^ ,}]+) \}", text, re.M):
        formats[key] = (int(w), int(h), folder)
    default_match = re.search(r"^  formats: \[(.*?)\]", text, re.M)
    default_formats = [f.strip() for f in default_match.group(1).split(",")] if default_match else []
    slides = []
    for block in re.split(r"^  - id: ", text.split("\nslides:\n", 1)[1], flags=re.M)[1:]:
        slide_id = block.splitlines()[0].strip()
        own = re.search(r"^    formats: \[(.*?)\]", block, re.M)
        slides.append((slide_id, [f.strip() for f in own.group(1).split(",")] if own else default_formats))
    return formats, slides


def check(out: Path, config: Path):
    formats, slides = parse_config(config.read_text())
    errors, expected = [], set()
    for index, (slide_id, keys) in enumerate(slides, 1):
        for key in keys:
            if key not in formats:
                errors.append(f"slide {slide_id}: unknown format {key}")
                continue
            w, h, folder = formats[key]
            path = out / folder / f"{index:02d}-{slide_id}.png"
            expected.add(path)
            if not path.exists():
                errors.append(f"missing {path.relative_to(out)}")
                continue
            try:
                width, height, depth, color = png_header(path)
            except ValueError as exc:
                errors.append(f"{path.relative_to(out)}: {exc}")
                continue
            if (width, height) != (w, h):
                errors.append(f"{path.relative_to(out)}: {width}x{height}, want {w}x{h}")
            if depth != 8 or color not in NO_ALPHA_COLOR_TYPES:
                errors.append(f"{path.relative_to(out)}: bit depth {depth}, color type {color} (alpha not allowed)")
    for extra in sorted(set(out.rglob("*.png")) - expected):
        errors.append(f"unexpected {extra.relative_to(out)}")
    return errors


if __name__ == "__main__":
    out = Path(sys.argv[1])
    config = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parents[2] / "marketing" / "marketing.yaml"
    problems = check(out, config)
    if problems:
        sys.exit("\n".join(problems))
    print(f"ok: {sum(1 for _ in out.rglob('*.png'))} assets")
