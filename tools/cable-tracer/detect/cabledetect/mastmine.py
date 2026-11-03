"""Hard-negative mining for the mast net: run the per-fold models over every park, cut patches at
the confident peaks that are not at a traced bend, and add them to the patch set as negatives.
Usage: mastmine.py <training-set> <patches.npz> <fold-params-prefix.npz> <out.npz>"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cabledetect import dataset, mastheat, water  # noqa: E402
from cabledetect.mastpatches import crop  # noqa: E402


def main(root: Path, patches: Path, params: Path, out: Path, probability: float = 0.6, per_park: int = 40) -> None:
    data = np.load(patches)
    x, y, parks, kinds = list(data["x"]), list(data["y"]), list(data["park"]), list(data["kind"])
    models = {}
    for fold_json in sorted(params.parent.glob(f"{params.stem}.fold*.json")):
        fold_params = mastheat.load_params(fold_json.with_suffix(".npz"))
        for park in json.loads(fold_json.read_text()):
            models[park] = fold_params
    rng = np.random.default_rng(3)
    added = 0
    for example in dataset.load(root):
        if not example.detail or not len(example.mast_positions_xy) or example.park_id not in models:
            continue
        snapshot = example.detail
        rgb = example.image(snapshot)
        seed_px = example.to_pixels(snapshot, np.zeros((1, 2)))[0]
        w = water.water_mask(rgb, (int(np.clip(seed_px[1], 0, 2047)), int(np.clip(seed_px[0], 0, 2047))))
        logits = mastheat.dense_logits(models[example.park_id], rgb)
        # A peak near a traced bend, a confirmed mast or an unsure detection is not a false peak.
        bends = np.concatenate([example.to_pixels(snapshot, example.mast_positions_xy), example.to_pixels(snapshot, example.masts_xy("unsure"))])
        mpp = snapshot.meters_per_pixel
        candidates = []
        for row, col, prob in mastheat.mast_peaks(logits, float(np.log(probability / (1 - probability)))):
            if np.min(np.hypot(bends[:, 0] - col, bends[:, 1] - row)) * mpp < 20:
                continue
            # Only places the detector could meet in the app: on or near the water body.
            if w[max(0, row - 34):row + 35, max(0, col - 34):col + 35].mean() < 0.3:
                continue
            candidates.append((prob, col, row))
        candidates.sort(reverse=True)
        count = 0
        for prob, col, row in candidates[:per_park]:
            for jitter in range(2):
                jc, jr = (0.0, 0.0) if jitter == 0 else rng.normal(0, 2 / mpp, 2)
                patch = crop(rgb, col + jc, row + jr)
                if patch is not None:
                    x.append(patch); y.append(0); parks.append(example.park_id); kinds.append("falsepeak"); count += 1
        added += count
        print(example.park_id, "false peaks", len(candidates), "added", count, flush=True)
    np.savez_compressed(out, x=np.stack(x).astype(np.uint8), y=np.array(y, dtype=np.int64), park=np.array(parks), kind=np.array(kinds))
    print(f"saved {out}: {len(y)} patches (+{added} mined negatives)")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]))
