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
each traced bend to the nearest proposed vertex, perimeter, mast peaks and bends found) and writes
a debug image per park: water dimmed, floating objects magenta, mast detections orange, the hand
trace yellow, the best proposal green.

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
4. **Masts** (`mastheat.py`, optional, `--masts <params.npz>`): a tiny CNN (4 conv layers,
   17,745 parameters) classifies 64 px (19 m) patches as mast or not. Run densely over the water
   (stride 16 px) it gives a heatmap; peaks over 0.7 on or next to the water are mast detections (0.5 until 2026-11-03).
   They enter the loop fit as extra vertex evidence, both as hull points (finds corners the floating
   objects miss) and as pure vertex support (survives a false mast); the two candidate sets are
   pooled and the best score wins. The same net runs in the app (`RpplCore/CableDetection/MastNet`),
   from the weights `export_mastnet.py` writes.
5. **Evaluation** (`evaluate.py`): polygon IoU and vertex distances against the hand trace.
   `--given-others` hands each fit the park's other traced cables, as the app does: their
   evidence is theirs and the new loop keeps clear of them. A park with several loops is fitted
   once per loop, with the water search seeded at that loop, as the user centres the map on the
   cable they want (the app seeds at the map centre).

## Mast labels from the app

The app's Debug screen "Review masts" (see `../README.md`) produces `tools/cable-tracer/mast-labels.json`:
per park the detector's guesses with the reviewer's verdict (`mast`, `none`, `unsure`) and the
masts the reviewer added by hand. The export carries them as `masts` (local metres) and renders
the 600 m close-up for a park that has labels but no traced cable, so such a park trains the mast
net too: `mast` is a positive like a traced bend, `none` a hard negative (`kind == "rejected"`),
`unsure` keeps the patch sampler and the miner away from that spot.

## Training round in one command

`train_round.py` runs a whole round (merge the exported sets, patches, train, mine false peaks,
train again, evaluate the loop fit) and shows a live status line per step: the park it is on, or
the fold, epoch, loss and time left while training. Full output of every step goes to a log in the
work folder. On a Mac (Apple Silicon CPU is plenty for this ~18k-parameter net):

```bash
cd tools/cable-tracer/detect
python3 -m venv /tmp/towernet-venv && /tmp/towernet-venv/bin/pip install -r requirements.txt
C="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/DCSBL/cable-tracer-check"
/tmp/towernet-venv/bin/python train_round.py \
  --sets "$C/training-set" "$C/training-set-2026-11-03" "$C/labels-set1-2026-11-03" "$C/labels-set2-2026-11-03" \
  --work /tmp/towernet-round --copy-to "$C/train-$(date +%F)"
```

It ends with the held-out tower scores (AUC, towers found, rejected guesses still fired on) and
the loop-fit summary line; compare those with `RESULTS.md` before exporting the weights with
`export_mastnet.py`.

## Training the mast net

```bash
python3 cabledetect/mastpatches.py <training-set> /tmp/mast-patches.npz          # positives at the traced bends, negatives on water, objects, shore
python3 cabledetect/masttrain.py /tmp/mast-patches.npz /tmp/mastnet.npz          # 5-fold CV by park, then the final model; writes .foldN.npz/.json too
python3 cabledetect/mastmine.py <training-set> /tmp/mast-patches.npz /tmp/mastnet.npz /tmp/mast-patches-v2.npz   # confident false peaks become negatives
python3 cabledetect/masttrain.py /tmp/mast-patches-v2.npz /tmp/mastnet-v2.npz
python3 export_mastnet.py /tmp/mastnet-v2.npz ../../../RpplCore/Sources/RpplCore/Resources/MastNet.weights   # prints the reference logits for CableDetectionTests
```

`run.py --masts /tmp/mastnet-v2.npz` scores each park with the fold model that did not see it, so
the numbers in `RESULTS.md` are honest for new parks. The Swift port is checked against the
Python heatmap to 0.05 logit.

## Results (2026-11-03, 32 traced parks)

See `RESULTS.md`.
