# Cable route proposal (prototype)

Python prototype of the automatic step: given a park location and the 600 m satellite
close-up that `cable-tracer --export-training-set` writes, propose the full-size cable loop
and score how plausible it is. It is checked against the routes already traced by hand, so
every change here is measured on the same 25 parks.

```bash
pip install -r requirements.txt
python3 run.py /path/to/training-set --out /tmp/cable-eval
```

`run.py` prints one JSON line per park (IoU with the traced loop, mean and max distance from
each traced bend to the nearest proposed vertex, perimeter) and writes a debug image per park:
water dimmed, floating objects magenta, the hand trace yellow, the best proposal green.

## How it works

1. **Water** (`water.py`): k-means on colour, saturation and coarse texture; the smoothest,
   least saturated, least green cluster is water. The component nearest the park location is
   kept, small holes (boats, glint) are filled, islands are not.
2. **Floating objects** (`features.py`): bright blobs on the water, 1-120 m², away from the
   shore and surrounded by water. These are obstacles, mast platforms and their shadows,
   buoys and boats.
3. **Loop fit** (`loopfit.py`): the convex hull of the floating objects within 520 m of the park,
   simplified to 4, 5 or 6 vertices, then refined by coordinate descent on a score:
   - a floating object near each vertex (mast platforms sit at the bends),
   - objects along the edges (obstacles sit along the cable),
   - an empty interior (nothing floats in the middle of a loop) and nothing just outside,
   - every edge over water,
   - a log-normal prior on the perimeter (median 700 m) and a penalty on very narrow loops,
   - 5 vertices preferred over 4 and 6 (masts stand outside the loop, so it is convex).
4. **Evaluation** (`evaluate.py`): polygon IoU and vertex distances against the hand trace.

## Results (2026-11-02, 25 traced parks)

See `RESULTS.md`.
