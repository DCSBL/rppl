"""Find the wheel of a confirmed tower guess on its zoomed close-up.

The coarse net's peak often lands on the tower's arm or platform, a few metres from the wheel
where the cable wraps around it (median 5.9 m on the 2026-11-05 labels, mostly along the arm towards
the foot). This small fully convolutional net looks at the same 48 m around the guess as the
close-up check (0.25 m/px) and gives a heatmap of 2 m cells; the wheel is the probability-weighted mean
around its peak, picked under a 12 m prior around the guess.

    python3 cabledetect/wheelfind.py <phone-set folder> <out folder> [--epochs 60] [--resume]

Training uses every confirmed tower's close-up (they are centred on the wheel the reviewer placed),
shifted at random by up to 12 m and turned and mirrored. Scores are leave-parks-out (5 folds by
park) on the real guesses: the close-up cut around where the detector put the tower (`detected`),
so the distance before and after says how much nearer the wheel the guess gets on a new park.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import jax
import jax.numpy as jnp
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cabledetect.closeupcheck import METERS_PER_PX, normalize, window  # noqa: E402

STORE_PX = 288  # 72 m around the wheel
TRAIN_PX = 160  # 40 m crops while training
TEST_PX = 192   # the 48 m around the guess, as the close-up check sees it
SHIFT = 48      # +-12 m
CELL = 8        # three 2 x 2 poolings: 2 m cells
LAYERS = [(3, 16), (16, 32), (32, 48), (48, 64), (64, 64)]
POOLS = 3
PRIOR_CELLS = 6.0  # the peak is picked under a Gaussian of 12 m around the guess: far peaks are other towers


def affine(info: dict) -> np.ndarray:
    """Least-squares map (lat, lon, 1) -> (column, row) from the close-up's control points."""
    points = info["controlPoints"]
    a = np.array([[p["coordinate"]["lat"], p["coordinate"]["lon"], 1.0] for p in points])
    b = np.array([[p["column"], p["row"]] for p in points])
    return np.linalg.lstsq(a, b, rcond=None)[0]


def load(folder: Path) -> dict:
    labels = json.loads((folder / "tower-labels.json").read_text())["parks"]
    by_id = {label["id"].lower(): (park, label) for park, park_labels in labels.items() for label in park_labels}
    stored, parks, test, test_truth, test_park = [], [], [], [], []
    for meta in sorted((folder / "closeups").glob("*.json")):
        info = json.loads(meta.read_text())
        found = by_id.get(str(info.get("labelID", "")).lower())
        if found is None or found[1]["verdict"] not in ("tower", "mast"):
            continue
        park, label = found
        rgb = np.asarray(Image.open(meta.with_suffix(".jpg")).convert("RGB"))
        mpp = float(info["metersPerPixel"])
        to_pixel = affine(info)
        wheel = np.array([label["coordinate"]["lat"], label["coordinate"]["lon"], 1.0]) @ to_pixel
        stored.append(window(rgb, mpp, *wheel, size=STORE_PX))
        parks.append(park)
        if "detected" in label:
            guess = np.array([label["detected"]["lat"], label["detected"]["lon"], 1.0]) @ to_pixel
            offset = (wheel - guess) * mpp / METERS_PER_PX  # wheel relative to the guess, in input pixels
            if np.abs(offset).max() < TEST_PX / 2 - 4:
                test.append((len(stored) - 1, window(rgb, mpp, *guess, size=TEST_PX)))
                test_truth.append(offset)
                test_park.append(park)
    return {"stored": np.stack(stored), "park": np.array(parks),
            "test_index": np.array([t[0] for t in test]), "test_x": np.stack([t[1] for t in test]),
            "test_truth": np.array(test_truth), "test_park": np.array(test_park)}


def init_params(key):
    params = []
    for cin, cout in LAYERS:
        key, sub = jax.random.split(key)
        params.append((jax.random.normal(sub, (3, 3, cin, cout)) * np.sqrt(2 / (9 * cin)), jnp.zeros(cout)))
    key, sub = jax.random.split(key)
    params.append((jax.random.normal(sub, (LAYERS[-1][1], 1)) * 0.01, jnp.zeros(1)))
    return params


def forward(params, x):  # (N, P, P, 3) -> heatmap logits (N, P/8, P/8)
    h = x
    for k, (w, b) in enumerate(params[:-1]):
        h = jax.lax.conv_general_dilated(h, w, (1, 1), "SAME", dimension_numbers=("NHWC", "HWIO", "NHWC")) + b
        h = jax.nn.relu(h)
        if k < POOLS:
            h = jax.lax.reduce_window(h, -jnp.inf, jax.lax.max, (1, 2, 2, 1), (1, 2, 2, 1), "VALID")
    w, b = params[-1]
    return (h @ w + b)[..., 0]


def loss_fn(params, x, target):  # target: (N, cells, cells) soft one-hot
    logits = forward(params, x)
    n = logits.shape[0]
    flat = logits.reshape(n, -1)
    l2 = sum(jnp.sum(w * w) for w, _ in params)
    return -jnp.mean(jnp.sum(target.reshape(n, -1) * jax.nn.log_softmax(flat), axis=1)) + 1e-4 * l2


@jax.jit
def adam_step(params, opt, x, target, lr):
    loss, grads = jax.value_and_grad(loss_fn)(params, x, target)
    m, v, t = opt
    t = t + 1
    m = jax.tree_util.tree_map(lambda a, g: 0.9 * a + 0.1 * g, m, grads)
    v = jax.tree_util.tree_map(lambda a, g: 0.999 * a + 0.001 * g * g, v, grads)
    params = jax.tree_util.tree_map(lambda p, mi, vi: p - lr * (mi / (1 - 0.9 ** t)) / (jnp.sqrt(vi / (1 - 0.999 ** t)) + 1e-8), params, m, v)
    return params, (m, v, t), loss


def soft_target(points: np.ndarray, size: int) -> np.ndarray:
    """A Gaussian of 1 cell around each point (input pixels, x then y) on the cell grid."""
    cells = size // CELL
    centres = (np.arange(cells) + 0.5) * CELL
    gx = np.exp(-0.5 * ((centres[None, :] - points[:, :1]) / CELL) ** 2)
    gy = np.exp(-0.5 * ((centres[None, :] - points[:, 1:]) / CELL) ** 2)
    t = gy[:, :, None] * gx[:, None, :]
    return (t / t.sum(axis=(1, 2), keepdims=True)).astype(np.float32)


def augment(rng: np.random.Generator, stored: np.ndarray):
    x = np.empty((len(stored), TRAIN_PX, TRAIN_PX, 3), np.float32)
    points = np.empty((len(stored), 2))
    middle = STORE_PX // 2
    for i, image in enumerate(stored):
        dx, dy = rng.integers(-SHIFT, SHIFT + 1, 2)
        top, left = middle - dy - TRAIN_PX // 2, middle - dx - TRAIN_PX // 2
        patch = image[top:top + TRAIN_PX, left:left + TRAIN_PX].astype(np.float32) / 255
        px, py = TRAIN_PX / 2 + dx, TRAIN_PX / 2 + dy  # the wheel in the crop
        for _ in range(rng.integers(4)):  # np.rot90: (x, y) -> (y, P - x)
            patch = np.rot90(patch)
            px, py = py, TRAIN_PX - px
        if rng.random() < 0.5:
            patch = patch[:, ::-1]
            px = TRAIN_PX - px
        patch = (patch - patch.mean()) * rng.uniform(0.85, 1.15) + patch.mean() + rng.uniform(-0.06, 0.06)
        x[i] = np.clip(patch, 0, 1)
        points[i] = (px, py)
    return normalize(x), soft_target(points, TRAIN_PX)


_heatmap = jax.jit(forward)


def heatmaps(params, images: np.ndarray) -> np.ndarray:
    """Cell probabilities (N, cells, cells): the softmax of each of the 8 views, turned back, averaged."""
    x = normalize(images.astype(np.float32) / 255)
    total = 0
    for k in range(4):
        for mirror in (False, True):
            v = np.rot90(x, k, axes=(1, 2))
            if mirror:
                v = v[:, :, ::-1]
            logits = np.asarray(_heatmap(params, jnp.asarray(np.ascontiguousarray(v))))
            h = np.asarray(jax.nn.softmax(jnp.asarray(logits.reshape(len(v), -1)), axis=1)).reshape(logits.shape)
            if mirror:
                h = h[:, :, ::-1]
            total = total + np.rot90(h, -k, axes=(1, 2))
    return total / 8


def peak(h: np.ndarray) -> tuple[float, float]:
    """Offset of the wheel from the middle in input pixels (x right, y down): the cell that is most
    likely under the prior around the guess, refined by the probability-weighted mean of its 3 x 3."""
    cells = h.shape[0]
    centres = np.arange(cells) + 0.5 - cells / 2
    prior = np.exp(-0.5 * (centres[:, None] ** 2 + centres[None, :] ** 2) / PRIOR_CELLS ** 2)
    r, c = np.unravel_index(np.argmax(h * prior), h.shape)
    r0, r1, c0, c1 = max(r - 1, 0), min(r + 2, cells), max(c - 1, 0), min(c + 2, cells)
    w = h[r0:r1, c0:c1]
    rows, cols = np.mgrid[r0:r1, c0:c1]
    return (((cols * w).sum() / w.sum() + 0.5) * CELL - cells * CELL / 2,
            ((rows * w).sum() / w.sum() + 0.5) * CELL - cells * CELL / 2)


def locate(params, images: np.ndarray) -> np.ndarray:
    """Wheel offsets from the middle of each input (input pixels, x then y)."""
    return np.array([peak(h) for h in heatmaps(params, images)])


def train(stored, epochs: int, seed: int, label: str):
    rng = np.random.default_rng(seed)
    params = init_params(jax.random.PRNGKey(seed))
    opt = (jax.tree_util.tree_map(jnp.zeros_like, params), jax.tree_util.tree_map(jnp.zeros_like, params), 0)
    batch, steps_per_epoch = 32, max(1, len(stored) // 16)
    total, started, step = epochs * steps_per_epoch, time.time(), 0
    for epoch in range(epochs):
        losses = []
        for _ in range(steps_per_epoch):
            x, target = augment(rng, stored[rng.choice(len(stored), batch)])
            lr = 1.5e-3 * 0.5 * (1 + np.cos(np.pi * step / total))
            params, opt, loss = adam_step(params, opt, jnp.asarray(x), jnp.asarray(target), lr)
            losses.append(float(loss))
            step += 1
        if epoch % 10 == 9 or epoch == epochs - 1:
            left = (time.time() - started) / (epoch + 1) * (epochs - epoch - 1)
            print(f"progress: {label}: epoch {epoch + 1}/{epochs}, loss {np.mean(losses):.3f}, about {left:.0f} s left", flush=True)
    return params


def save(params, path: Path) -> None:
    np.savez(path, **{f"w{i}": np.asarray(w) for i, (w, _) in enumerate(params)}, **{f"b{i}": np.asarray(b) for i, (_, b) in enumerate(params)})


def load_params(path: Path):
    data = np.load(path)
    return [(jnp.asarray(data[f"w{i}"]), jnp.asarray(data[f"b{i}"])) for i in range(len(LAYERS) + 1)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("phone_set", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--folds", type=int, default=5)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    data = load(args.phone_set)
    parks = np.unique(data["park"])
    print(f"{len(data['stored'])} tower close-ups, {len(data['test_x'])} with the detector's guess, {len(parks)} parks", flush=True)
    fold_of = {park: i % args.folds for i, park in enumerate(np.random.default_rng(0).permutation(parks))}
    found = np.zeros_like(data["test_truth"])
    for fold in range(args.folds):
        path = args.out / f"wheelfind.fold{fold}.npz"
        train_rows = np.array([fold_of[p] != fold for p in data["park"]])
        test_rows = np.array([fold_of[p] == fold for p in data["test_park"]])
        if args.resume and path.exists():
            params = load_params(path)
        else:
            params = train(data["stored"][train_rows], args.epochs, fold, f"wheel finder fold {fold + 1}/{args.folds}")
            save(params, path)
        if test_rows.any():
            found[test_rows] = locate(params, data["test_x"][test_rows])
    before = np.linalg.norm(data["test_truth"], axis=1) * METERS_PER_PX
    after = np.linalg.norm(found - data["test_truth"], axis=1) * METERS_PER_PX
    summary = {"guesses": int(len(before)),
               "before_m": {q: round(float(np.percentile(before, p)), 2) for q, p in (("median", 50), ("p75", 75), ("p90", 90))},
               "after_m": {q: round(float(np.percentile(after, p)), 2) for q, p in (("median", 50), ("p75", 75), ("p90", 90))},
               "within_2m_before": round(float((before <= 2).mean()), 3), "within_2m_after": round(float((after <= 2).mean()), 3),
               "worse": int((after > before + 1).sum())}
    np.savetxt(args.out / "wheelfind-test.csv", np.column_stack([data["test_truth"], found, before, after]), delimiter=",",
               header="truth_x,truth_y,found_x,found_y,before_m,after_m", comments="", fmt="%.2f")
    final = args.out / "wheelfind.npz"
    if not (args.resume and final.exists()):
        save(train(data["stored"], args.epochs, 99, "wheel finder final model"), final)
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
