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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("training_set", type=Path)
    parser.add_argument("--out", type=Path, default=Path("/tmp/cable-eval"))
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
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

        candidates = loopfit.propose_loops(blobs, blob_xy, water_test)
        elapsed = time.time() - started
        row = {"park": example.park_id, "blobs": len(blobs), "water_fraction": float(w.mean()), "seconds": round(elapsed, 1), "candidates": len(candidates)}
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
