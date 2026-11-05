from __future__ import annotations

import cv2
import numpy as np
from scipy import ndimage


def water_mask(rgb: np.ndarray, seed_rc: tuple[int, int] | None = None, near_px: int = 1000, min_area_px: int = 20000, max_hole_px: int = 18000) -> np.ndarray:
    """Water on a satellite close-up: low local texture, darker and less saturated than land.

    Unsupervised: k-means on (L, a, b, local std) picks the cluster that looks most like water,
    then the component containing/nearest the seed (image centre by default) is kept. Returns a
    boolean mask of the whole water body, not just the part near the cable.
    """
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32)
    # Texture on a 3x downsampled, blurred image: sun glint and ripples are sub-metre, the
    # texture that separates water from trees, buildings and parked cars is coarser.
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32)
    coarse = cv2.resize(cv2.GaussianBlur(gray, (0, 0), 1.5), (gray.shape[1] // 3, gray.shape[0] // 3), interpolation=cv2.INTER_AREA)
    mean = cv2.blur(coarse, (7, 7))
    sq_mean = cv2.blur(coarse * coarse, (7, 7))
    texture = cv2.resize(np.sqrt(np.maximum(sq_mean - mean * mean, 0)), (gray.shape[1], gray.shape[0]), interpolation=cv2.INTER_LINEAR)
    small = 4  # k-means on a downsampled grid keeps this fast
    sub = (slice(None, None, small), slice(None, None, small))
    features = np.stack([
        lab[sub][..., 0] / 255,
        lab[sub][..., 1] / 255,
        lab[sub][..., 2] / 255,
        hsv[sub][..., 1] / 255,
        np.minimum(texture[sub] / 30, 1),
    ], axis=-1).reshape(-1, 5).astype(np.float32)
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 1e-3)
    _, labels, centers = cv2.kmeans(features, 6, None, criteria, 3, cv2.KMEANS_PP_CENTERS)
    # Water-likeness: smooth, not bright, not saturated, not green (a < 0.5 in Lab is green:
    # grass and fields are smooth too, which is the usual confusion).
    score = (
        2.0 * centers[:, 4]
        + 1.0 * centers[:, 0]
        + 1.0 * centers[:, 3]
        + 2.0 * np.maximum(0.5 - centers[:, 1], 0)
        + 0.5 * np.maximum(centers[:, 2] - 0.55, 0)
    )
    water_cluster = int(np.argmin(score))
    rows_small = lab[sub].shape[0]
    coarse_mask = (labels.reshape(rows_small, -1) == water_cluster)
    mask = cv2.resize(coarse_mask.astype(np.uint8), (rgb.shape[1], rgb.shape[0]), interpolation=cv2.INTER_NEAREST).astype(bool)
    mask = ndimage.binary_opening(mask, iterations=2)
    mask = ndimage.binary_closing(mask, iterations=6)
    # Fill small holes (boats, obstacles, glint) but keep islands: a hole over ~1500 m^2 is land.
    filled = ndimage.binary_fill_holes(mask)
    holes, hole_count = ndimage.label(filled & ~mask)
    if hole_count:
        hole_sizes = ndimage.sum(np.ones_like(mask), holes, range(1, hole_count + 1))
        small_holes = np.isin(holes, np.nonzero(hole_sizes <= max_hole_px)[0] + 1)
        mask = mask | small_holes
    return keep_body(mask, seed_rc, near_px, min_area_px)


def map_water(map_rgb: np.ndarray, max_hole_px: int | None = None) -> np.ndarray:
    """Water on the plain Apple map of the same spot (the app saves it next to the photo): the
    map paints every water body one light blue, so this is a colour test, not a guess.
    Small holes (the lake's name, a jetty line) are filled; islands stay land."""
    if max_hole_px is None:  # 4000 px on a 2048 px map (about 340 m2), the same area at any size
        max_hole_px = max(16, int(4000 * (map_rgb.shape[0] / 2048) ** 2))
    hsv = cv2.cvtColor(map_rgb, cv2.COLOR_RGB2HSV)
    hue, sat, val = hsv[..., 0].astype(int), hsv[..., 1].astype(int), hsv[..., 2].astype(int)
    mask = (hue >= 95) & (hue <= 125) & (sat >= 25) & (val >= 90)  # OpenCV hue 0-180: 190-250 degrees
    mask = ndimage.binary_opening(mask, iterations=1)
    filled = ndimage.binary_fill_holes(mask)
    holes, hole_count = ndimage.label(filled & ~mask)
    if hole_count:
        hole_sizes = ndimage.sum(np.ones_like(mask), holes, range(1, hole_count + 1))
        mask = mask | np.isin(holes, np.nonzero(hole_sizes <= max_hole_px)[0] + 1)
    return mask


def water_for(example, snapshot, rgb: np.ndarray, seed_rc: tuple[int, int] | None = None) -> np.ndarray:
    """The park's water body on `snapshot`: from the saved Apple map when the training set has
    one (exact), else from the photo itself (`water_mask`)."""
    known = example.water(snapshot)
    if known is not None:
        return keep_body(known, seed_rc)
    return water_mask(rgb, seed_rc)


def keep_body(mask: np.ndarray, seed_rc: tuple[int, int] | None = None, near_px: int = 1000, min_area_px: int = 20000) -> np.ndarray:
    """The water component at the seed, or the largest one within `near_px` of it."""
    labeled, count = ndimage.label(mask)
    if count == 0:
        return mask
    seed = seed_rc or (mask.shape[0] // 2, mask.shape[1] // 2)
    sizes = ndimage.sum(mask, labeled, range(1, count + 1))
    seed_label = labeled[seed]
    if seed_label == 0 or sizes[seed_label - 1] < min_area_px:
        # The park location is usually on the shore next to the water, so take the largest
        # component that comes within `near_px` of the seed; the cable is never further away.
        best, best_size = None, 0
        for index in range(1, count + 1):
            if sizes[index - 1] < min_area_px or sizes[index - 1] <= best_size:
                continue
            rows, cols = np.nonzero(labeled == index)
            if np.min(np.hypot(rows - seed[0], cols - seed[1])) <= near_px:
                best, best_size = index, sizes[index - 1]
        if best is None:
            best = int(np.argmax(sizes)) + 1
        seed_label = best
    return labeled == seed_label
