from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

EARTH_RADIUS_M = 6_371_000.0


@dataclass
class Snapshot:
    image_file: str
    mask_file: str | None
    size_px: int
    meters_per_pixel: float
    center_lat: float
    center_lon: float
    # Water mask from the plain Apple map of the same frame (phone sets only): white is water.
    water_file: str | None = None


@dataclass
class Cable:
    name: str | None
    direction: str | None
    kind: str
    closed: bool
    points_xy: np.ndarray  # metres east/north of the park location, travel order


@dataclass
class Tower:
    """A reviewed tower position from the tracer's review mode (local metres)."""
    xy: np.ndarray
    verdict: str  # tower | none | notVisible | unsure
    source: str  # detector | manual
    probability: float | None
    # Wheel-to-foot arm on the image from the review frame: (compass bearing in degrees, length in metres).
    arm: tuple[float, float] | None = None


@dataclass
class ParkExample:
    park_id: str
    name: str
    lat: float
    lon: float
    cables: list[Cable]
    overview: Snapshot | None
    detail: Snapshot | None
    root: Path
    towers: list[Tower] = field(default_factory=list)

    def image(self, snapshot: Snapshot) -> np.ndarray:
        return np.asarray(Image.open(self.root / snapshot.image_file).convert("RGB"))

    def mask(self, snapshot: Snapshot) -> np.ndarray | None:
        if snapshot.mask_file is None:
            return None
        return np.asarray(Image.open(self.root / snapshot.mask_file).convert("L")) > 127

    def water(self, snapshot: Snapshot) -> np.ndarray | None:
        if snapshot.water_file is None:
            return None
        return np.asarray(Image.open(self.root / snapshot.water_file).convert("L")) > 127

    def local_xy(self, lat: float, lon: float) -> np.ndarray:
        """Metres east/north of the park location, like CableTracerCore.LocalProjection."""
        d_lat = math.radians(lat - self.lat)
        d_lon = math.radians(lon - self.lon)
        return np.array([d_lon * math.cos(math.radians(self.lat)) * EARTH_RADIUS_M, d_lat * EARTH_RADIUS_M])

    def to_pixels(self, snapshot: Snapshot, points_xy: np.ndarray) -> np.ndarray:
        """Local metres -> (col, row) in the snapshot (row 0 at the top)."""
        center = self.local_xy(snapshot.center_lat, snapshot.center_lon)
        half = snapshot.size_px / 2
        cols = half + (points_xy[:, 0] - center[0]) / snapshot.meters_per_pixel
        rows = half - (points_xy[:, 1] - center[1]) / snapshot.meters_per_pixel
        return np.stack([cols, rows], axis=1)

    def to_local(self, snapshot: Snapshot, pixels: np.ndarray) -> np.ndarray:
        center = self.local_xy(snapshot.center_lat, snapshot.center_lon)
        half = snapshot.size_px / 2
        x = center[0] + (pixels[:, 0] - half) * snapshot.meters_per_pixel
        y = center[1] - (pixels[:, 1] - half) * snapshot.meters_per_pixel
        return np.stack([x, y], axis=1)

    def to_latlon(self, points_xy: np.ndarray) -> np.ndarray:
        lat = self.lat + np.degrees(points_xy[:, 1] / EARTH_RADIUS_M)
        lon = self.lon + np.degrees(points_xy[:, 0] / (EARTH_RADIUS_M * math.cos(math.radians(self.lat))))
        return np.stack([lat, lon], axis=1)

    @property
    def loops(self) -> list[Cable]:
        return [c for c in self.cables if c.kind == "loop" and len(c.points_xy) >= 3]

    def keep_out_xy(self) -> np.ndarray:
        """Reviewed spots no negative may be cut from: unsure ones and towers the imagery does not show."""
        return np.concatenate([self.towers_xy("unsure"), self.towers_xy("notVisible")])

    def towers_xy(self, verdict: str) -> np.ndarray:
        """Reviewed positions with this verdict, (n, 2) local metres."""
        return np.array([m.xy for m in self.towers if m.verdict == verdict], dtype=float).reshape(-1, 2)

    @property
    def tower_positions_xy(self) -> np.ndarray:
        """Where a tower stands: the traced bends plus the reviewed towers."""
        parts = [loop.points_xy for loop in self.loops] + [self.towers_xy("tower")]
        return np.concatenate(parts).reshape(-1, 2)


def _snapshot(raw: dict | None) -> Snapshot | None:
    if not raw:
        return None
    return Snapshot(
        image_file=raw["imageFile"],
        mask_file=raw.get("maskFile"),
        size_px=raw["sizePx"],
        meters_per_pixel=raw["metersPerPixel"],
        center_lat=raw["center"]["lat"],
        center_lon=raw["center"]["lon"],
        water_file=raw.get("waterFile"),
    )


def load(root: Path) -> list[ParkExample]:
    rows = json.loads((root / "training-set.json").read_text())
    examples = []
    for row in rows:
        cables = []
        for cable in row["cables"]:
            geometry = cable["geometry"]
            points = np.array([[p[0], p[1]] if isinstance(p, list) else [p["x"], p["y"]] for p in geometry["pointsXY"]], dtype=float).reshape(-1, 2)
            cables.append(Cable(cable.get("name"), cable.get("direction"), geometry["kind"], geometry["isClosed"], points))
        # Exports before the rename (2026-11-03) used "masts" and the verdict "mast".
        towers = [Tower(np.array(m["xy"], dtype=float), "tower" if m["verdict"] == "mast" else m["verdict"], m.get("source", "detector"), m.get("probability"),
                        (m["arm"]["bearingDeg"], m["arm"]["lengthM"]) if m.get("arm") else None)
                  for m in row.get("towers") or row.get("masts") or []]
        examples.append(ParkExample(
            park_id=row["parkID"], name=row["name"], lat=row["location"]["lat"], lon=row["location"]["lon"],
            cables=cables, overview=_snapshot(row.get("snapshot")), detail=_snapshot(row.get("detailSnapshot")), root=root,
            towers=towers,
        ))
    return examples
