#!/usr/bin/env python3
"""ONE-OFF. Migrate Rppl sessions from any pre-reset format to schema v1, then delete this file.

Rppl reset its session format to schema v1 and dropped every migration and compatibility path
(#369). Sessions recorded before that cannot be opened by the new app. Only the dev device has
such sessions, so they are converted once, here, instead of in the app.

    scripts/one-off/migrate-sessions-to-v1.py INPUT [INPUT ...] --out OUTDIR

INPUT is a session package folder (anything with a manifest.json), a Share export `.json`, or a
folder that contains either; folders are searched recursively. The input is never modified.
Results go to OUTDIR/packages/<folder> and OUTDIR/exports/<file>.json.

What it converts:
  - folder names: bare UUID / date-only -> `YYYY-MM-DD HH-mm - City` (local time of this Mac,
    city from derived/view.json, else Unknown). Names that are already canonical, or that you
    renamed yourself, are kept.
  - assumptions.jsonl -> detections.jsonl (when detections.jsonl is missing or empty);
    labels.jsonl is dropped; detection code `paused` -> `inactive`; events without an id or a
    detectorId get one.
  - plain motion-NNN.jsonl and verbose motion keys -> compact keys inside motion-NNN.jsonl.zlib.
  - derived/ is dropped (the app rebuilds it from the raw streams).
  - manifest schemaVersion -> 1.
  - Share exports: the same, on the JSON keys (assumptions/labels/motion/motionFramesZlib/derived).

Python 3.9+, standard library only.
"""

import argparse
import base64
import json
import re
import shutil
import struct
import sys
import uuid
import zlib
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 1
UNKNOWN_CITY = "Unknown"
CANONICAL = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}-\d{2} - .+?(?: \(\d+\))?$")
BARE_UUID = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
DATE_ONLY = re.compile(r"^\d{4}-\d{2}-\d{2} - .+?(?: \(\d+\))?$")

# Motion: verbose key -> compact key (MotionSample.CompactCodingKeys).
MOTION_KEYS = {
    "timestamp": "t", "userAccelX": "ax", "userAccelY": "ay", "userAccelZ": "az",
    "rotationX": "rx", "rotationY": "ry", "rotationZ": "rz", "pitch": "p", "roll": "r", "yaw": "y",
}
# Frame limits from CompressedJSONLFrames; stay well under them when re-framing.
MAX_LINES_PER_FRAME = 20_000


# MARK: - helpers

def compact_json(value):
    return json.dumps(value, separators=(",", ":"), sort_keys=True, ensure_ascii=False)


def parse_iso(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def display_city(name):
    cleaned = " ".join((name or "").replace("/", " ").replace("\\", " ").split())
    return cleaned or UNKNOWN_CITY


def canonical_folder_name(started_at, city):
    local = parse_iso(started_at).astimezone()
    return "%s - %s" % (local.strftime("%Y-%m-%d %H-%M"), display_city(city))


def unique_name(base, taken):
    if base not in taken:
        return base
    n = 2
    while "%s (%d)" % (base, n) in taken:
        n += 1
    return "%s (%d)" % (base, n)


def is_app_named(folder_name):
    return bool(BARE_UUID.match(folder_name) or DATE_ONLY.match(folder_name))


# MARK: - detections

def migrate_detection(event, from_assumptions=False):
    event = dict(event)
    if event.get("code") == "paused":
        event["code"] = "inactive"
    if not event.get("id"):
        event["id"] = str(uuid.uuid4()).upper()
    if not event.get("detectorId"):
        event["detectorId"] = "legacy_assumption" if from_assumptions else "unknown"
    return event


def read_jsonl_objects(path):
    """Tolerant like the app: a torn or garbage line costs only that line."""
    objects = []
    skipped = 0
    for raw in path.read_bytes().split(b"\n"):
        if not raw.strip():
            continue
        try:
            objects.append(json.loads(raw.decode("utf-8")))
        except (ValueError, UnicodeDecodeError):
            skipped += 1
    return objects, skipped


# MARK: - motion frames

def inflate(payload):
    for wbits in (-15, 15):  # Apple's COMPRESSION_ZLIB is raw deflate; accept zlib-wrapped too
        try:
            return zlib.decompress(payload, wbits)
        except zlib.error:
            continue
    raise ValueError("frame does not inflate")


def read_frames(data):
    """Leading complete frames only, like the app. Returns the decoded JSONL lines."""
    lines = []
    offset = 0
    while offset + 4 <= len(data):
        (length,) = struct.unpack(">I", data[offset:offset + 4])
        if length == 0 or offset + 4 + length > len(data):
            break
        try:
            text = inflate(data[offset + 4:offset + 4 + length])
        except ValueError:
            break
        lines.extend(line for line in text.split(b"\n") if line.strip())
        offset += 4 + length
    return lines


def make_frame(lines):
    body = ("\n".join(lines) + "\n").encode("utf-8")
    deflater = zlib.compressobj(5, zlib.DEFLATED, -15)
    payload = deflater.compress(body) + deflater.flush()
    return struct.pack(">I", len(payload)) + payload


def compact_motion(sample):
    if "t" in sample:
        return sample
    return {MOTION_KEYS[key]: value for key, value in sample.items() if key in MOTION_KEYS}


def reframe_motion(samples):
    lines = [compact_json(compact_motion(sample)) for sample in samples]
    return b"".join(make_frame(lines[i:i + MAX_LINES_PER_FRAME]) for i in range(0, len(lines), MAX_LINES_PER_FRAME))


def convert_frames(data):
    """Returns (bytes, changed). Frames that are already compact are returned untouched."""
    lines = read_frames(data)
    samples = []
    verbose = False
    for line in lines:
        try:
            sample = json.loads(line)
        except ValueError:
            continue
        verbose = verbose or "timestamp" in sample
        samples.append(sample)
    if not verbose:
        return data, False
    return reframe_motion(samples), True


# MARK: - Share export (.json)

def load_export(path):
    """The parsed Share export, or None when this is some other JSON file."""
    try:
        package = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if isinstance(package, dict) and "manifest" in package and "locations" in package:
        return package
    return None


def migrate_export(package, target, report):
    manifest = package["manifest"]
    manifest["schemaVersion"] = SCHEMA_VERSION

    detections = package.get("detections") or []
    from_assumptions = False
    if not detections and package.get("assumptions"):
        detections = package["assumptions"]
        from_assumptions = True
    package["detections"] = [migrate_detection(e, from_assumptions) for e in detections]
    for key in ("assumptions", "labels", "derived"):
        package.pop(key, None)

    if package.get("motion"):
        package["motion"] = [compact_motion(sample) for sample in package["motion"]]
    frames_b64 = package.get("motionFramesZlib")
    if frames_b64:
        converted, changed = convert_frames(base64.b64decode(frames_b64))
        if changed:
            package["motionFramesZlib"] = base64.b64encode(converted).decode("ascii")
            report.append("  motion re-framed")

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(compact_json(package) + "\n", encoding="utf-8")


# MARK: - session package folder

def migrate_package(source, out_root, taken, report):
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    manifest["schemaVersion"] = SCHEMA_VERSION

    name = source.name
    if is_app_named(name):
        city = None
        view = source / "derived" / "view.json"
        if view.exists():
            try:
                city = json.loads(view.read_text(encoding="utf-8")).get("cityName")
            except ValueError:
                pass
        name = canonical_folder_name(manifest["startedAt"], city)
    name = unique_name(name, taken)
    taken.add(name)
    target = out_root / name
    target.mkdir(parents=True)

    (target / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    detections, skipped = [], 0
    det_path = source / "detections.jsonl"
    if det_path.exists():
        detections, skipped = read_jsonl_objects(det_path)
    from_assumptions = False
    assumptions_path = source / "assumptions.jsonl"
    if not detections and assumptions_path.exists():
        detections, skipped = read_jsonl_objects(assumptions_path)
        from_assumptions = True
    with (target / "detections.jsonl").open("w", encoding="utf-8") as handle:
        for event in detections:
            handle.write(compact_json(migrate_detection(event, from_assumptions)) + "\n")
    if skipped:
        report.append("  skipped %d unreadable detection line(s)" % skipped)

    handled = {"manifest.json", "detections.jsonl", "assumptions.jsonl", "labels.jsonl", "derived"}
    for entry in sorted(source.iterdir()):
        if entry.name in handled or entry.name.startswith("."):
            continue
        motion = re.match(r"^motion-(\d{3})\.jsonl(\.zlib)?$", entry.name)
        if motion:
            index, compressed = motion.group(1), motion.group(2)
            zlib_target = target / ("motion-%s.jsonl.zlib" % index)
            if compressed:
                converted, changed = convert_frames(entry.read_bytes())
                zlib_target.write_bytes(converted)
                if changed:
                    report.append("  %s re-framed" % entry.name)
            elif not (source / ("motion-%s.jsonl.zlib" % index)).exists():
                samples, _ = read_jsonl_objects(entry)
                zlib_target.write_bytes(reframe_motion(samples))
                report.append("  %s -> %s" % (entry.name, zlib_target.name))
            continue
        if entry.is_dir():
            shutil.copytree(entry, target / entry.name)
        else:
            shutil.copy2(entry, target / entry.name)
    return name


# MARK: - discovery and main

def discover(root):
    packages, exports = [], []
    if root.is_file():
        if root.suffix == ".json":
            exports.append(root)
        return packages, exports
    if (root / "manifest.json").exists():
        return [root], exports
    for child in sorted(root.iterdir()):
        if child.name.startswith("."):
            continue
        sub_packages, sub_exports = discover(child)
        packages.extend(sub_packages)
        exports.extend(sub_exports)
    return packages, exports


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    out = args.out.resolve()
    for source in args.inputs:
        source = source.resolve()
        if out == source or source in out.parents or out in source.parents:
            sys.exit("refusing: --out must be a separate folder, not inside or around an input (%s)" % source)
    if out.exists() and any(out.iterdir()):
        sys.exit("refusing: %s is not empty" % out)

    packages, exports = [], []
    for source in args.inputs:
        if not source.exists():
            sys.exit("not found: %s" % source)
        found_packages, found_exports = discover(source)
        packages.extend(found_packages)
        exports.extend(found_exports)

    failures = 0
    taken = set()
    (out / "packages").mkdir(parents=True, exist_ok=True)
    for source in packages:
        report = []
        try:
            name = migrate_package(source, out / "packages", taken, report)
            print("package  %s -> %s" % (source.name, name))
        except Exception as error:  # noqa: BLE001 - report and keep going
            failures += 1
            print("package  %s FAILED: %s" % (source.name, error))
        for line in report:
            print(line)
    exported = 0
    for source in exports:
        package = load_export(source)
        if package is None:
            continue
        report = []
        try:
            migrate_export(package, out / "exports" / source.name, report)
            exported += 1
            print("export   %s" % source.name)
        except Exception as error:  # noqa: BLE001
            failures += 1
            print("export   %s FAILED: %s" % (source.name, error))
        for line in report:
            print(line)

    print("\n%d package(s), %d export(s), %d failure(s). Input untouched. Output: %s"
          % (len(packages), exported, failures, out))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
