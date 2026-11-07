"""Writes the wheel finder (cabledetect/wheelfind.py) as the binary resource RpplCore loads
(TowerWheelFinder.weights, the TowerNet format) and prints the reference offset for the Swift test.

    python3 export_wheelfind.py <wheelfind.npz> <out.weights>
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cabledetect import closeupcheck, wheelfind  # noqa: E402
from export_closeupcheck import synthetic_closeup  # noqa: E402


def main(params_path: Path, out: Path) -> None:
    params = wheelfind.load_params(params_path)
    blob = bytearray(b"RPMN") + struct.pack("<II", 1, len(wheelfind.LAYERS))
    for (w, b), (cin, cout) in zip(params[:-1], wheelfind.LAYERS):
        w, b = np.asarray(w), np.asarray(b)
        assert w.shape == (3, 3, cin, cout) and b.shape == (cout,)
        blob += struct.pack("<II", cin, cout) + w.astype("<f4").tobytes() + b.astype("<f4").tobytes()
    w, b = (np.asarray(a) for a in params[-1])
    blob += struct.pack("<II", w.shape[0], w.shape[1]) + w.astype("<f4").tobytes() + b.astype("<f4").tobytes()
    out.write_bytes(bytes(blob))
    image = closeupcheck.window(synthetic_closeup(), 0.0625, 560.0, 590.0, size=wheelfind.TEST_PX)[None]
    h = wheelfind.heatmaps(params, image)[0]
    dx, dy = wheelfind.peak(h)
    print(f"wrote {out} ({len(blob)} bytes)")
    r, c = np.unravel_index(np.argmax(h), h.shape)
    print(f"synthetic close-up: wheel offset {dx:.4f}, {dy:.4f} input px")
    print(f"cell probabilities: middle (12, 12) {h[12, 12]:.7f}, corner (0, 0) {h[0, 0]:.7f}, "
          f"largest ({r}, {c}) {h[r, c]:.7f}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
