"""Run the loop proposal on every traced park in a training-set export and compare with the trace.

    python3 run.py /path/to/training-set --out /tmp/cable-eval
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from cabledetect import dataset, evaluate, features, loopfit, water  # noqa: E402


def load_mast_models(path: Path):
    """{park_id: params} from the per-fold files next to `path`, plus "*" for the full model."""
    from cabledetect import mastheat
    models = {"*": mastheat.load_params(path)}
    for fold_json in sorted(path.parent.glob(f"{path.stem}.fold*.json")):
        params = mastheat.load_params(fold_json.with_suffix(".npz"))
        for park in json.loads(fold_json.read_text()):
            models[park] = params
    return models


def detect_masts(models, example, snapshot, rgb, w, probability=0.5):
    """Mast peaks in local metres with probabilities, plus how they compare with the traced bends."""
    from cabledetect import mastheat
    params = models.get(example.park_id, models["*"])
    logits = mastheat.dense_logits(params, rgb)
    peaks = []
    for row, col, prob in mastheat.mast_peaks(logits, threshold=float(np.log(probability / (1 - probability)))):
        r0, r1 = max(0, row - 34), min(w.shape[0], row + 35)
        c0, c1 = max(0, col - 34), min(w.shape[1], col + 35)
        if w[r0:r1, c0:c1].mean() >= 0.3:  # masts stand on or right next to the water
            peaks.append((col, row, prob))
    if not peaks:
        return np.zeros((0, 2)), np.zeros(0), {"mast_peaks": 0, "bends_hit": 0, "bends": sum(len(l.points_xy) for l in example.loops)}
    px = np.array([[c, r] for c, r, _ in peaks], dtype=float)
    xy = example.to_local(snapshot, px)
    prob = np.array([p for _, _, p in peaks])
    bends = np.concatenate([loop.points_xy for loop in example.loops])
    d = np.linalg.norm(bends[:, None, :] - xy[None, :, :], axis=2)
    hit = int((d.min(axis=1) <= 12).sum())
    false_peaks = int((d.min(axis=0) > 20).sum())
    return xy, prob, {"mast_peaks": len(peaks), "bends_hit": hit, "bends": len(bends), "false_mast_peaks": false_peaks}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("training_set", type=Path)
    parser.add_argument("--out", type=Path, default=Path("/tmp/cable-eval"))
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--masts", type=Path, help="mast net params (.npz); with .foldN.npz/.json siblings each park uses the fold that held it out")
    parser.add_argument("--mast-weight", type=float, default=3.0)
    args = parser.parse_args()
    mast_models = load_mast_models(args.masts) if args.masts else None
    args.out.mkdir(parents=True, exist_ok=True)

    results = []
    for example in dataset.load(args.training_set):
        if args.only and example.park_id not in args.only:
            continue
        if not example.detail or not example.loops:
            continue
        started = time.time()
        snapshot = example.detail
        rgb = example.image(snapshot)
        mpp = snapshot.meters_per_pixel
        # Seed the water search at the park location: the only input a new park has.
        seed_px = example.to_pixels(snapshot, np.zeros((1, 2)))[0]
        seed_rc = (int(np.clip(seed_px[1], 0, snapshot.size_px - 1)), int(np.clip(seed_px[0], 0, snapshot.size_px - 1)))
        w = water.water_mask(rgb, seed_rc)
        blobs = features.bright_blobs(rgb, w, mpp)
        blob_px = np.array([[b.col, b.row] for b in blobs]).reshape(-1, 2)
        blob_xy = example.to_local(snapshot, blob_px) if len(blobs) else np.zeros((0, 2))

        def water_test(points_xy, _example=example, _snapshot=snapshot, _w=w):
            px = _example.to_pixels(_snapshot, points_xy)
            cols = np.clip(px[:, 0].astype(int), 0, _snapshot.size_px - 1)
            rows = np.clip(px[:, 1].astype(int), 0, _snapshot.size_px - 1)
            inside = (px[:, 0] >= 0) & (px[:, 0] < _snapshot.size_px) & (px[:, 1] >= 0) & (px[:, 1] < _snapshot.size_px)
            return _w[rows, cols] & inside

        rows_w, cols_w = np.nonzero(w[::8, ::8])
        water_xy = example.to_local(snapshot, np.stack([cols_w * 8, rows_w * 8], axis=1).astype(float))
        water_xy = water_xy[np.linalg.norm(water_xy, axis=1) <= 380]
        mast_xy, mast_prob, mast_stats = np.zeros((0, 2)), np.zeros(0), {}
        if mast_models:
            mast_xy, mast_prob, mast_stats = detect_masts(mast_models, example, snapshot, rgb, w)
        candidates = loopfit.propose_loops(blobs, blob_xy, water_test, water_xy=water_xy, extra_xy=mast_xy, extra_weights=args.mast_weight * mast_prob)
        elapsed = time.time() - started
        row = {"park": example.park_id, "blobs": len(blobs), "water_fraction": float(w.mean()), "seconds": round(elapsed, 1), "candidates": len(candidates), **mast_stats}
        if candidates:
            best = candidates[0]
            matches = [evaluate.compare(best.vertices_xy, loop.points_xy) for loop in example.loops]
            match = max(matches, key=lambda m: m.iou)
            row.update({
                "score": round(best.score, 1), "vertices": len(best.vertices_xy), "perimeter_m": round(best.perimeter_m),
                "iou": round(match.iou, 2), "mean_vertex_error_m": round(match.mean_vertex_error_m, 1),
                "max_vertex_error_m": round(match.max_vertex_error_m, 1), "mean_line_error_m": round(match.mean_line_error_m, 1),
                "notes": best.notes,
            })
        results.append(row)
        print(json.dumps(row))

        # Debug image: water dimmed, blobs magenta, trace yellow, proposal green.
        vis = rgb.copy()
        vis[~w] = (vis[~w] * 0.45).astype(np.uint8)
        for b in blobs:
            cv2.circle(vis, (int(b.col), int(b.row)), 12, (255, 0, 255), 2)
        for (x, y), p in zip(example.to_pixels(snapshot, mast_xy), mast_prob):
            cv2.circle(vis, (int(x), int(y)), 18, (255, 140, 0), 2 if p > 0.75 else 1)
        for loop in example.loops:
            px = example.to_pixels(snapshot, loop.points_xy).astype(int)
            cv2.polylines(vis, [px.reshape(-1, 1, 2)], True, (255, 255, 0), 2)
        for rank, candidate in enumerate(candidates[:3]):
            px = example.to_pixels(snapshot, candidate.vertices_xy).astype(int)
            color = (0, 255, 0) if rank == 0 else (0, 160, 255)
            cv2.polylines(vis, [px.reshape(-1, 1, 2)], True, color, 3 if rank == 0 else 1)
        cv2.imwrite(str(args.out / f"{example.park_id}.png"), cv2.cvtColor(cv2.resize(vis, (1024, 1024)), cv2.COLOR_RGB2BGR))

    (args.out / "results.json").write_text(json.dumps(results, indent=1))
    scored = [r for r in results if "iou" in r]
    if scored:
        print(f"\n{len(scored)}/{len(results)} parks with a proposal; median IoU {np.median([r['iou'] for r in scored]):.2f}, "
              f"median mean vertex error {np.median([r['mean_vertex_error_m'] for r in scored]):.1f} m, "
              f"IoU >= 0.7 for {sum(r['iou'] >= 0.7 for r in scored)}")


if __name__ == "__main__":
    main()
