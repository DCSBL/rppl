"""Patch dataset for the tower detector: positives at the hand-traced bends (a tower stands at
every bend, a few metres outside the cable) and at the towers confirmed in the tracer's review
mode, negatives on open water, at floating objects that are not bends (obstacles, boats), on
the shore and at the detections the reviewer rejected."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cabledetect import dataset, features, water  # noqa: E402

PATCH = 64  # 64 px = 19 m at 0.29 m/px; 128 px (37 m) also fits the whole tower arm (--patch 128)


def crop(rgb: np.ndarray, col: float, row: float, size: int = PATCH) -> np.ndarray | None:
    r0, c0 = int(round(row)) - size // 2, int(round(col)) - size // 2
    if r0 < 0 or c0 < 0 or r0 + size > rgb.shape[0] or c0 + size > rgb.shape[1]:
        return None
    return rgb[r0:r0 + size, c0:c0 + size]


def build(root: Path, out: Path, rng_seed: int = 7, size: int = PATCH) -> None:
    rng = np.random.default_rng(rng_seed)
    patches, labels, parks, kinds = [], [], [], []
    examples = [e for e in dataset.load(root) if e.detail and len(e.tower_positions_xy)]
    for number, example in enumerate(examples, 1):
        print(f"progress: patches [{number}/{len(examples)}] {example.park_id}", flush=True)
        snapshot = example.detail
        rgb = example.image(snapshot)
        seed_px = example.to_pixels(snapshot, np.zeros((1, 2)))[0]
        w = water.water_mask(rgb, (int(np.clip(seed_px[1], 0, 2047)), int(np.clip(seed_px[0], 0, 2047))))
        bends = example.to_pixels(snapshot, example.tower_positions_xy)
        rejected = example.to_pixels(snapshot, example.towers_xy("none"))
        # Nothing is sampled near an unsure detection (it may be a tower after all) or a tower the imagery does not show.
        avoid = np.concatenate([bends, rejected, example.to_pixels(snapshot, example.keep_out_xy())])
        mpp = snapshot.meters_per_pixel

        def far_from_bends(col, row, metres):
            return np.min(np.hypot(avoid[:, 0] - col, avoid[:, 1] - row)) * mpp >= metres

        # Positives: each bend or confirmed tower with 6 jittered copies (the trace is 5-10 m off the tower anyway).
        for col, row in bends:
            for _ in range(6):
                jc, jr = rng.normal(0, 6 / mpp / 3, 2)  # sigma 2 m
                patch = crop(rgb, col + jc, row + jr, size)
                if patch is not None:
                    patches.append(patch); labels.append(1); parks.append(example.park_id); kinds.append("bend")
        # Rejected detections: the reviewer looked and saw no tower, the hardest negatives there are.
        for col, row in rejected:
            for jitter in range(3):
                jc, jr = (0.0, 0.0) if jitter == 0 else rng.normal(0, 2 / mpp, 2)
                patch = crop(rgb, col + jc, row + jr, size)
                if patch is not None:
                    patches.append(patch); labels.append(0); parks.append(example.park_id); kinds.append("rejected")
        # Hard negatives: floating objects that are not at a bend.
        for blob in features.bright_blobs(rgb, w, mpp):
            if far_from_bends(blob.col, blob.row, 18):
                patch = crop(rgb, blob.col, blob.row, size)
                if patch is not None:
                    patches.append(patch); labels.append(0); parks.append(example.park_id); kinds.append("object")
        # Open water and shore negatives.
        rows_w, cols_w = np.nonzero(w)
        for _ in range(60):
            i = rng.integers(len(rows_w))
            col, row = cols_w[i], rows_w[i]
            if far_from_bends(col, row, 25):
                patch = crop(rgb, col, row, size)
                if patch is not None:
                    patches.append(patch); labels.append(0); parks.append(example.park_id); kinds.append("water")
        rows_l, cols_l = np.nonzero(~w)
        for _ in range(30):
            i = rng.integers(len(rows_l))
            col, row = cols_l[i], rows_l[i]
            if far_from_bends(col, row, 25):
                patch = crop(rgb, col, row, size)
                if patch is not None:
                    patches.append(patch); labels.append(0); parks.append(example.park_id); kinds.append("land")
        print(example.park_id, len(bends), "towers,", len(rejected), "rejected; total patches", len(patches))
    np.savez_compressed(out, x=np.stack(patches).astype(np.uint8), y=np.array(labels, dtype=np.int64),
                        park=np.array(parks), kind=np.array(kinds))
    y = np.array(labels)
    print(f"saved {out}: {len(y)} patches, {y.sum()} positives")


if __name__ == "__main__":
    build(Path(sys.argv[1]), Path(sys.argv[2]), size=int(sys.argv[sys.argv.index("--patch") + 1]) if "--patch" in sys.argv else PATCH)
