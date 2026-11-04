"""Dense tower heatmap: the patch classifier run fully convolutionally over a whole close-up.
The net pools after its first four conv layers, so the output is at 1/16 resolution (4.7 m per
cell at 0.29 m/px); cell (i, j) scores the P px patch (64 or 128) whose top-left corner is at
pixel (16i, 16j), i.e. centred at (16i + P/2, 16j + P/2)."""
from __future__ import annotations

from pathlib import Path

import jax
import jax.numpy as jnp
import numpy as np
from scipy import ndimage

from .towertrain import POOLED, patch_of

jax.config.update("jax_platform_name", "cpu")

STRIDE = 16


def load_params(path: Path):
    data = np.load(path)
    count = len([k for k in data.files if k.startswith("w")])
    return [(jnp.asarray(data[f"w{i}"]), jnp.asarray(data[f"b{i}"])) for i in range(count)]


def _dense(params, x, cells: int):
    h = x
    for layer, (w, b) in enumerate(params[:-1]):
        h = jax.lax.conv_general_dilated(h, w, (1, 1), "SAME", dimension_numbers=("NHWC", "HWIO", "NHWC")) + b
        h = jax.nn.relu(h)
        if layer < POOLED:
            h = jax.lax.reduce_window(h, -jnp.inf, jax.lax.max, (1, 2, 2, 1), (1, 2, 2, 1), "VALID")
    pooled = jax.lax.reduce_window(h, 0.0, jax.lax.add, (1, cells, cells, 1), (1, 1, 1, 1), "VALID") / float(cells * cells)
    w, b = params[-1]
    return (pooled @ w + b)[0, :, :, 0]


_dense_jit = jax.jit(_dense, static_argnums=2)


def dense_logits(params, rgb: np.ndarray) -> np.ndarray:
    x = jnp.asarray(rgb.astype(np.float32)[None] / 255)
    return np.asarray(_dense_jit(params, x, patch_of(params) // STRIDE))


def heat_to_pixels(i: np.ndarray, j: np.ndarray, patch: int = 64) -> tuple[np.ndarray, np.ndarray]:
    """Heatmap cell -> (row, col) of the patch centre in the full image."""
    return i * STRIDE + patch // 2, j * STRIDE + patch // 2


def tower_peaks(logits: np.ndarray, threshold: float = 0.0, min_separation_cells: int = 2, patch: int = 64) -> list[tuple[int, int, float]]:
    """Local maxima of the heatmap above `threshold` (logit 0 = probability 0.5), as (row, col, prob).
    `patch` is the patch size of the net that made the heatmap (`towertrain.patch_of`)."""
    footprint = np.ones((2 * min_separation_cells + 1,) * 2, bool)
    local_max = ndimage.maximum_filter(logits, footprint=footprint) == logits
    cells = np.argwhere(local_max & (logits > threshold))
    rows, cols = heat_to_pixels(cells[:, 0], cells[:, 1], patch)
    probs = 1 / (1 + np.exp(-logits[cells[:, 0], cells[:, 1]]))
    order = np.argsort(-probs)
    return [(int(rows[k]), int(cols[k]), float(probs[k])) for k in order]
