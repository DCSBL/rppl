"""Builds a training set from the tower review zip the app shares, so no Mac has to render the
satellite close-ups again: the phone already took them when the reviewer tapped "Find towers".

    python3 phone_set.py <tower-review-....zip or its unzipped folder> <out-folder> [--parks <Parks dir>]

The zip holds `tower-labels.json` and `snapshots/<park>-<time>.jpg` with a `.json` beside each
(`TowerReviewSnapshot`: centre, metres per pixel, size). Every labelled park with a snapshot becomes
one row in the format the tracer exports (training-set.json): the park's traced cables from its
YAML, the labels in local metres, and as close-up the snapshot that holds the most labels. Feed the
folder to train_round.py with --sets after the older sets, so these rows replace older ones.
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import numpy as np
import yaml

EARTH_RADIUS_M = 6_371_000.0
REPO = Path(__file__).resolve().parents[3]
PARKS = REPO / "RpplCore" / "Sources" / "RpplCore" / "Resources" / "Parks"


def local_xy(lat: float, lon: float, origin: dict) -> list[float]:
    """Metres east/north of `origin`, like CableTracerCore.LocalProjection."""
    d_lat = math.radians(lat - origin["lat"])
    d_lon = math.radians(lon - origin["lon"])
    return [d_lon * math.cos(math.radians(origin["lat"])) * EARTH_RADIUS_M, d_lat * EARTH_RADIUS_M]


def cable_rows(park: dict) -> list[dict]:
    rows = []
    for cable in park.get("cables") or []:
        direction = str(cable["direction"]).lower() if cable.get("direction") is not None else None
        points = [local_xy(p["lat"], p["lon"], park["location"]) for p in cable.get("points") or []]
        kind = "straight" if direction == "2.0" else "loop" if direction in ("cw", "ccw") else "unknown"
        rows.append({
            "name": cable.get("name"),
            "direction": direction,
            "declaredLengthM": cable.get("length_m"),
            "geometry": {"kind": kind, "isClosed": kind == "loop" and len(points) >= 3, "pointsXY": points},
        })
    return rows


# The app's metres (DetectionImage) use 111,320 m per degree on both axes; ours use the sphere.
APP_METERS_PER_DEGREE = 111_320.0
OUR_METERS_PER_DEGREE = math.radians(1) * EARTH_RADIUS_M


def georeference(info: dict, origin: dict) -> tuple[dict, float, str]:
    """Centre and metres per pixel of a phone close-up in this package's metres.

    With the control points the app saves (coordinates and the pixel MapKit drew each at), the
    scale and centre are fitted to MapKit's own placement and checked: the note gives the worst
    residual in pixels and the north/east scale ratio. Without them the app's scale is converted."""
    size = info["widthPx"]
    points = info.get("controlPoints") or []
    if len(points) < 3:
        mpp = info["metersPerPixel"] * OUR_METERS_PER_DEGREE / APP_METERS_PER_DEGREE
        return info["center"], mpp, "no control points, app scale converted"
    xy = np.array([local_xy(p["coordinate"]["lat"], p["coordinate"]["lon"], origin) for p in points])
    cols = np.array([p["column"] for p in points])
    rows = np.array([p["row"] for p in points])
    # col = a + x / mpp_x, row = c - y / mpp_y
    (a, kx), *_ = np.linalg.lstsq(np.stack([np.ones(len(xy)), xy[:, 0]], 1), cols, rcond=None)
    (c, ky), *_ = np.linalg.lstsq(np.stack([np.ones(len(xy)), -xy[:, 1]], 1), rows, rcond=None)
    mpp = 2 / (kx + ky)
    centre_xy = np.array([(size / 2 - a) / kx, -(size / 2 - c) / ky])
    # Residuals of the single-scale frame the dataset uses.
    predicted_cols = size / 2 + (xy[:, 0] - centre_xy[0]) / mpp
    predicted_rows = size / 2 - (xy[:, 1] - centre_xy[1]) / mpp
    worst = float(np.max(np.hypot(predicted_cols - cols, predicted_rows - rows)))
    lat = origin["lat"] + math.degrees(centre_xy[1] / EARTH_RADIUS_M)
    lon = origin["lon"] + math.degrees(centre_xy[0] / (EARTH_RADIUS_M * math.cos(math.radians(origin["lat"]))))
    return {"lat": lat, "lon": lon}, float(mpp), f"worst control point {worst:.2f} px, north/east scale {kx / ky:.4f}"


def inside(snapshot: dict, xy: list[float], centre_xy: list[float]) -> bool:
    half = snapshot["widthPx"] / 2 * snapshot["metersPerPixel"]
    return abs(xy[0] - centre_xy[0]) < half - 10 and abs(xy[1] - centre_xy[1]) < half - 10


def build(source: Path, out: Path, parks_dir: Path) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        root = source
        if source.suffix == ".zip":
            with zipfile.ZipFile(source) as archive:
                archive.extractall(tmp)
            root = Path(tmp)
        labels_files = sorted(root.rglob("tower-labels.json"))
        if not labels_files:
            sys.exit(f"no tower-labels.json in {source}")
        base = labels_files[0].parent
        labels = json.loads(labels_files[0].read_text())["parks"]
        snapshots: dict[str, list[tuple[dict, Path]]] = {}
        for meta in sorted((base / "snapshots").glob("*.json")):
            info = json.loads(meta.read_text())
            image = meta.with_suffix(".jpg")
            if image.exists():
                snapshots.setdefault(info["parkID"], []).append((info, image))

        out.mkdir(parents=True, exist_ok=True)
        rows, skipped, checks = [], [], []
        for park_id, park_labels in sorted(labels.items()):
            yaml_file = parks_dir / f"{park_id}.yaml"
            if not park_labels or park_id not in snapshots or not yaml_file.exists():
                skipped.append(park_id)
                continue
            park = yaml.safe_load(yaml_file.read_text())
            origin = park["location"]
            towers = []
            for label in park_labels:
                row = {
                    "xy": local_xy(label["coordinate"]["lat"], label["coordinate"]["lon"], origin),
                    "verdict": "tower" if label["verdict"] == "mast" else label["verdict"],
                    "source": label.get("source", "detector"),
                    "probability": label.get("probability"),
                }
                if label.get("arm"):
                    row["arm"] = label["arm"]
                towers.append(row)

            # The close-up that shows the most labels; the newest one on a tie.
            def score(entry):
                info, _ = entry
                centre = local_xy(info["center"]["lat"], info["center"]["lon"], origin)
                return sum(inside(info, t["xy"], centre) for t in towers), info["takenAt"]
            info, image = max(snapshots[park_id], key=score)
            centre, mpp, check = georeference(info, origin)
            checks.append(f"  {park_id}: {check}")
            target = out / f"{park_id}-phone.jpg"
            shutil.copy2(image, target)
            rows.append({
                "parkID": park_id,
                "name": park.get("name", park_id),
                "location": {"lat": origin["lat"], "lon": origin["lon"]},
                "cables": cable_rows(park),
                "towers": towers,
                "snapshot": None,
                "detailSnapshot": {
                    "imageFile": target.name,
                    "sizePx": info["widthPx"],
                    "metersPerPixel": mpp,
                    "center": centre,
                },
            })
        (out / "training-set.json").write_text(json.dumps(rows, indent=1))
    note = f"{len(rows)} parks with labels and a phone close-up"
    if skipped:
        note += f"; skipped {len(skipped)} without a close-up or park file: {', '.join(skipped[:8])}{' …' if len(skipped) > 8 else ''}"
    return "\n".join([note, *checks])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path, help="the zip the app shared, or its unzipped folder")
    parser.add_argument("out", type=Path)
    parser.add_argument("--parks", type=Path, default=PARKS, help="folder with the park YAML files")
    args = parser.parse_args()
    print(build(args.source, args.out, args.parks))


if __name__ == "__main__":
    main()
