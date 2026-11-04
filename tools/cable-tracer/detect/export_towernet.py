"""Writes the trained tower net as the binary resource RpplCore loads (TowerNet.weights) and prints
reference logits for the Swift unit test. Usage: export_towernet.py <params.npz> <out.weights>"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cabledetect.towertrain import LAYERS, forward  # noqa: E402


def synthetic_patch(size: int = 64) -> np.ndarray:
    y, x = np.mgrid[0:size, 0:size]
    return np.stack([(x * 7 + y * 13 + c * 31 + (x * y) % 17) % 256 for c in range(3)], axis=-1).astype(np.uint8)


def main(params_path: Path, out: Path) -> None:
    data = np.load(params_path)
    if len([k for k in data.files if k.startswith("w")]) != len(LAYERS) + 1:
        sys.exit(f"{params_path} is not a 64 px net; the app's TowerNet only reads 64 px nets (see README, --patch 128)")
    blob = bytearray(b"RPMN")
    blob += struct.pack("<II", 1, len(LAYERS))
    for i, (cin, cout) in enumerate(LAYERS):
        w, b = data[f"w{i}"], data[f"b{i}"]
        assert w.shape == (3, 3, cin, cout) and b.shape == (cout,)
        blob += struct.pack("<II", cin, cout)
        blob += w.astype("<f4").tobytes() + b.astype("<f4").tobytes()
    w, b = data[f"w{len(LAYERS)}"], data[f"b{len(LAYERS)}"]
    blob += struct.pack("<II", w.shape[0], w.shape[1])
    blob += w.astype("<f4").tobytes() + b.astype("<f4").tobytes()
    out.write_bytes(bytes(blob))
    import jax.numpy as jnp
    params = [(jnp.asarray(data[f"w{i}"]), jnp.asarray(data[f"b{i}"])) for i in range(len(LAYERS) + 1)]
    patch = synthetic_patch()
    logit = float(forward(params, jnp.asarray(patch[None].astype(np.float32) / 255))[0])
    count = sum(int(np.prod(data[k].shape)) for k in data.files)
    print(f"wrote {out} ({len(blob)} bytes, {count} parameters); synthetic patch logit {logit:.6f}")
    zeros = float(forward(params, jnp.zeros((1, 64, 64, 3), np.float32))[0])
    print(f"all-black patch logit {zeros:.6f}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
