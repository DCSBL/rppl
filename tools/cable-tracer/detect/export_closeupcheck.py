"""Writes the close-up check (cabledetect/closeupcheck.py) as the binary resource RpplCore loads
(TowerCloseupCheck.weights, the TowerNet format) and prints reference scores for the Swift test.

    python3 export_closeupcheck.py <closeupcheck.npz> <out.weights>
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

import jax.numpy as jnp
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cabledetect import closeupcheck  # noqa: E402


def synthetic_closeup(size: int = 768) -> np.ndarray:
    y, x = np.mgrid[0:size, 0:size]
    return np.stack([(x * 7 + y * 13 + c * 31 + (x * y) % 17) % 256 for c in range(3)], axis=-1).astype(np.uint8)


def main(params_path: Path, out: Path) -> None:
    params = closeupcheck.load_params(params_path)
    blob = bytearray(b"RPMN") + struct.pack("<II", 1, len(closeupcheck.LAYERS))
    for (w, b), (cin, cout) in zip(params[:-1], closeupcheck.LAYERS):
        w, b = np.asarray(w), np.asarray(b)
        assert w.shape == (3, 3, cin, cout) and b.shape == (cout,)
        blob += struct.pack("<II", cin, cout) + w.astype("<f4").tobytes() + b.astype("<f4").tobytes()
    w, b = (np.asarray(a) for a in params[-1])
    blob += struct.pack("<II", w.shape[0], w.shape[1]) + w.astype("<f4").tobytes() + b.astype("<f4").tobytes()
    out.write_bytes(bytes(blob))
    stored = closeupcheck.downsample(synthetic_closeup())[None]
    plain = float(closeupcheck.forward(params, jnp.asarray(closeupcheck.centre(stored)))[0])
    score = float(closeupcheck.predict(params, stored)[0])
    print(f"wrote {out} ({len(blob)} bytes)")
    print(f"synthetic close-up: logit of the plain view {plain:.6f}, score over 8 views {score:.6f}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
