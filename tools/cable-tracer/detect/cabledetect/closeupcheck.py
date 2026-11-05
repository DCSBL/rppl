"""Second look at a tower guess on a zoomed close-up (40 m at 5 cm/px, from the app's "Fetch maps
and close-ups"): a small CNN says tower or not. The coarse net finds candidates on the 0.29 m/px
photo; this one checks each candidate where the wheel, the arm and the cable are sharp.

    python3 cabledetect/closeupcheck.py <phone-set folder> <out folder> [--epochs 80] [--resume]

Scores are leave-parks-out (5 folds by park, the split never changes), so they say how the check
does on a park it has never seen. Writes per fold `closeupcheck.foldN.npz` (kept on --resume), the
final `closeupcheck.npz`, `closeupcheck-scores.csv` (one row per close-up), `closeupcheck-mistakes.png`
(the worst held-out mistakes) and a JSON summary on stdout.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from pathlib import Path

import jax
import jax.numpy as jnp
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cabledetect.towertrain import auc  # noqa: E402

CROP_PX = 640   # 32 m of the 40 m close-up around the label
STORE_PX = 213  # stored at 1/3: 0.15 m/px
INPUT_PX = 192  # random crop of the stored image while training (+-1.5 m jitter)
LAYERS = [(3, 16), (16, 32), (32, 48), (48, 64), (64, 64)]


def load(folder: Path) -> dict:
    labels = json.loads((folder / "tower-labels.json").read_text())["parks"]
    by_id = {label["id"].lower(): (park, label) for park, park_labels in labels.items() for label in park_labels}
    images, y, parks, ids, probability, source = [], [], [], [], [], []
    for meta in sorted((folder / "closeups").glob("*.json")):
        info = json.loads(meta.read_text())
        found = by_id.get(str(info.get("labelID", "")).lower())
        if found is None or found[1]["verdict"] not in ("tower", "mast", "none"):
            continue
        park, label = found
        rgb = Image.open(meta.with_suffix(".jpg")).convert("RGB")
        w, h = rgb.size
        left, top = (w - CROP_PX) // 2, (h - CROP_PX) // 2
        rgb = rgb.crop((left, top, left + CROP_PX, top + CROP_PX)).resize((STORE_PX, STORE_PX), Image.LANCZOS)
        images.append(np.asarray(rgb))
        y.append(0 if label["verdict"] == "none" else 1)
        parks.append(park)
        ids.append(meta.stem)
        probability.append(label.get("probability") if label.get("probability") is not None else np.nan)
        source.append(label.get("source", "detector"))
    return {"x": np.stack(images), "y": np.array(y), "park": np.array(parks), "id": np.array(ids),
            "probability": np.array(probability, dtype=float), "source": np.array(source)}


def init_params(key):
    params = []
    for cin, cout in LAYERS:
        key, sub = jax.random.split(key)
        params.append((jax.random.normal(sub, (3, 3, cin, cout)) * np.sqrt(2 / (9 * cin)), jnp.zeros(cout)))
    key, sub = jax.random.split(key)
    params.append((jax.random.normal(sub, (LAYERS[-1][1], 1)) * 0.01, jnp.zeros(1)))
    return params


def forward(params, x):  # (N, P, P, 3) normalised (see `normalize`) -> logits (N,)
    h = x
    for w, b in params[:-1]:
        h = jax.lax.conv_general_dilated(h, w, (1, 1), "SAME", dimension_numbers=("NHWC", "HWIO", "NHWC")) + b
        h = jax.nn.relu(h)
        h = jax.lax.reduce_window(h, -jnp.inf, jax.lax.max, (1, 2, 2, 1), (1, 2, 2, 1), "VALID")
    h = h.mean(axis=(1, 2))  # 6 x 6 cells after five poolings
    w, b = params[-1]
    return (h @ w + b)[:, 0]


def loss_fn(params, x, y):
    logits = forward(params, x)
    l2 = sum(jnp.sum(w * w) for w, _ in params)
    return jnp.mean(jnp.logaddexp(0, logits) - y * logits) + 1e-4 * l2


@jax.jit
def adam_step(params, opt, x, y, lr):
    loss, grads = jax.value_and_grad(loss_fn)(params, x, y)
    m, v, t = opt
    t = t + 1
    m = jax.tree_util.tree_map(lambda a, g: 0.9 * a + 0.1 * g, m, grads)
    v = jax.tree_util.tree_map(lambda a, g: 0.999 * a + 0.001 * g * g, v, grads)
    params = jax.tree_util.tree_map(lambda p, mi, vi: p - lr * (mi / (1 - 0.9 ** t)) / (jnp.sqrt(vi / (1 - 0.999 ** t)) + 1e-8), params, m, v)
    return params, (m, v, t), loss


_predict = jax.jit(lambda params, x: jax.nn.sigmoid(forward(params, x)))


NORMALIZE = True  # per image and channel to zero mean, unit spread: the net sees shapes, not the water's colour


def normalize(x: np.ndarray) -> np.ndarray:
    """(N, P, P, 3) in 0..1 -> per image and channel standardised, scaled to about +-0.5."""
    if not NORMALIZE:
        return x - 0.5
    mean = x.mean(axis=(1, 2), keepdims=True)
    spread = x.std(axis=(1, 2), keepdims=True) + 0.02
    return ((x - mean) / spread * 0.15).astype(np.float32)


def augment(rng: np.random.Generator, stored: np.ndarray) -> np.ndarray:
    out = np.empty((len(stored), INPUT_PX, INPUT_PX, 3), np.float32)
    slack = STORE_PX - INPUT_PX
    for i, image in enumerate(stored):
        r, c = rng.integers(0, slack + 1, 2)
        patch = image[r:r + INPUT_PX, c:c + INPUT_PX].astype(np.float32) / 255
        patch = np.rot90(patch, rng.integers(4))
        if rng.random() < 0.5:
            patch = patch[:, ::-1]
        patch = (patch - patch.mean()) * rng.uniform(0.85, 1.15) + patch.mean() + rng.uniform(-0.06, 0.06)
        out[i] = np.clip(patch, 0, 1)
    return normalize(out)


def centre(stored: np.ndarray) -> np.ndarray:
    o = (STORE_PX - INPUT_PX) // 2
    return normalize(stored[:, o:o + INPUT_PX, o:o + INPUT_PX].astype(np.float32) / 255)


def predict(params, stored: np.ndarray) -> np.ndarray:
    """Mean over the 8 rotations and flips of the centre crop."""
    x = centre(stored)
    views = [np.rot90(x, k, axes=(1, 2)) for k in range(4)]
    views += [v[:, :, ::-1] for v in views]
    return np.mean([np.concatenate([np.asarray(_predict(params, jnp.asarray(np.ascontiguousarray(v[i:i + 32])))) for i in range(0, len(v), 32)]) for v in views], axis=0)


def train(x, y, epochs: int, seed: int, label: str):
    rng = np.random.default_rng(seed)
    params = init_params(jax.random.PRNGKey(seed))
    opt = (jax.tree_util.tree_map(jnp.zeros_like, params), jax.tree_util.tree_map(jnp.zeros_like, params), 0)
    # Balance the classes per batch: as many towers as rejected guesses.
    pos, neg = np.nonzero(y == 1)[0], np.nonzero(y == 0)[0]
    batch, steps_per_epoch = 32, max(1, len(y) // 32)
    total, started, step = epochs * steps_per_epoch, time.time(), 0
    for epoch in range(epochs):
        losses = []
        for _ in range(steps_per_epoch):
            idx = np.concatenate([rng.choice(pos, batch // 2), rng.choice(neg, batch // 2)])
            lr = 1.5e-3 * 0.5 * (1 + np.cos(np.pi * step / total))
            params, opt, loss = adam_step(params, opt, jnp.asarray(augment(rng, x[idx])), jnp.asarray(y[idx], jnp.float32), lr)
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


def mistakes_sheet(data: dict, scores: np.ndarray, path: Path, count: int = 24) -> None:
    wrong = np.argsort(-np.abs(scores - data["y"]))[:count]
    tile = 160
    sheet = Image.new("RGB", (6 * tile, ((len(wrong) + 5) // 6) * tile), "black")
    for n, i in enumerate(wrong):
        image = Image.fromarray(data["x"][i]).resize((tile, tile))
        draw = ImageDraw.Draw(image)
        truth = "tower" if data["y"][i] else "no tower"
        draw.rectangle([0, 0, tile, 14], fill="black")
        draw.text((3, 1), f"{truth}, check {scores[i]:.2f}", fill="yellow" if data["y"][i] else "red")
        sheet.paste(image, ((n % 6) * tile, (n // 6) * tile))
    sheet.save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("phone_set", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--epochs", type=int, default=80)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--raw-colour", action="store_true", help="feed plain colours instead of per-image standardised ones")
    args = parser.parse_args()
    global NORMALIZE
    NORMALIZE = not args.raw_colour
    args.out.mkdir(parents=True, exist_ok=True)
    data = load(args.phone_set)
    x, y, parks = data["x"], data["y"], data["park"]
    print(f"{len(y)} close-ups: {int(y.sum())} towers, {int((y == 0).sum())} rejected guesses, {len(np.unique(parks))} parks", flush=True)
    unique = np.unique(parks)
    np.random.default_rng(0).shuffle(unique)
    cv = np.zeros(len(y))
    for f, held in enumerate(np.array_split(unique, 5)):
        test = np.isin(parks, held)
        fold_file = args.out / f"closeupcheck.fold{f}.npz"
        if args.resume and fold_file.exists():
            params = load_params(fold_file)
        else:
            params = train(x[~test], y[~test], args.epochs, seed=f, label=f"close-up check fold {f + 1}/5")
            save(params, fold_file)
        cv[test] = predict(params, x[test])
        print(f"fold {f}: AUC {auc(cv[test], y[test]):.3f} on {int(test.sum())} close-ups", flush=True)

    towers, rejected = y == 1, y == 0
    summary = {
        "closeups": int(len(y)), "towers": int(towers.sum()), "rejected": int(rejected.sum()), "parks": int(len(unique)),
        "auc": auc(cv, y),
        "towers_kept@0.5": float(np.mean(cv[towers] >= 0.5)),
        "rejected_removed@0.5": float(np.mean(cv[rejected] < 0.5)),
    }
    # The same question for the coarse net: how well its own probability separates these guesses.
    seen = (data["source"] == "detector") & ~np.isnan(data["probability"])
    if seen.any() and len(np.unique(y[seen])) == 2:
        summary["coarse_auc_same_guesses"] = auc(data["probability"][seen], y[seen])
        summary["check_auc_same_guesses"] = auc(cv[seen], y[seen])
    # Threshold that keeps 98% of the towers, and what it removes then.
    keep98 = float(np.quantile(cv[towers], 0.02))
    summary["threshold_keep98"] = keep98
    summary["rejected_removed@keep98"] = float(np.mean(cv[rejected] < keep98))
    with (args.out / "closeupcheck-scores.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["closeup", "park", "tower", "source", "coarse_probability", "check_score"])
        for i in range(len(y)):
            writer.writerow([data["id"][i], parks[i], int(y[i]), data["source"][i], "" if np.isnan(data["probability"][i]) else round(float(data["probability"][i]), 3), round(float(cv[i]), 4)])
    mistakes_sheet(data, cv, args.out / "closeupcheck-mistakes.png")
    final = args.out / "closeupcheck.npz"
    if not (args.resume and final.exists()):
        save(train(x, y, args.epochs, seed=99, label="close-up check final model"), final)
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
