from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np
from scipy import ndimage


@dataclass
class Blob:
    row: float
    col: float
    area_m2: float
    length_m: float  # major axis
    width_m: float   # minor axis
    angle_deg: float
    brightness: float  # contrast over the surrounding water, in gray levels


def bright_blobs(rgb: np.ndarray, water: np.ndarray, meters_per_pixel: float,
                 min_area_m2: float = 0.8, max_area_m2: float = 120.0, shore_margin_m: float = 6.0) -> list[Blob]:
    """Small bright objects floating on water: obstacles (kickers, boxes, rails), mast platforms,
    buoys and boats. Everything that is not water texture and not shore.
    """
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32)
    margin_px = max(1, int(round(shore_margin_m / meters_per_pixel)))
    inner = ndimage.binary_erosion(water, iterations=margin_px)
    if not inner.any():
        return []
    # Local water brightness, so a bright lake and a dark lake get the same threshold.
    background = cv2.medianBlur(gray.astype(np.uint8), 31).astype(np.float32)
    diff = gray - background
    water_std = float(np.std(diff[inner]))
    threshold = max(18.0, 4.0 * water_std)
    candidate = (diff > threshold) & inner
    candidate = ndimage.binary_opening(candidate, iterations=1)
    labeled, count = ndimage.label(candidate)
    if count == 0:
        return []
    px_area = meters_per_pixel ** 2
    blobs: list[Blob] = []
    for index, slc in enumerate(ndimage.find_objects(labeled), start=1):
        region = labeled[slc] == index
        area = float(region.sum()) * px_area
        if not (min_area_m2 <= area <= max_area_m2):
            continue
        rows, cols = np.nonzero(region)
        rows = rows + slc[0].start
        cols = cols + slc[1].start
        # A floating object is surrounded by water; trees on an island or a quay are not.
        cy0, cx0 = rows.mean(), cols.mean()
        ring_px = int(round(12 / meters_per_pixel))
        r0, r1 = max(0, int(cy0) - ring_px), min(water.shape[0], int(cy0) + ring_px + 1)
        c0, c1 = max(0, int(cx0) - ring_px), min(water.shape[1], int(cx0) + ring_px + 1)
        if water[r0:r1, c0:c1].mean() < 0.7:
            continue
        points = np.stack([cols, rows], axis=1).astype(np.float32)
        if len(points) >= 5:
            (cx, cy), (w, h), angle = cv2.minAreaRect(points)
            length, width = max(w, h), min(w, h)
        else:
            cx, cy = points[:, 0].mean(), points[:, 1].mean()
            length = width = np.sqrt(len(points))
            angle = 0.0
        blobs.append(Blob(
            row=float(cy), col=float(cx), area_m2=area,
            length_m=float(length) * meters_per_pixel, width_m=float(width) * meters_per_pixel,
            angle_deg=float(angle), brightness=float(diff[rows, cols].mean()),
        ))
    return blobs
