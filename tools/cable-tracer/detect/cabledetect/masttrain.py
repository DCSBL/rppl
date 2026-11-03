"""Tiny mast classifier on 64 px (19 m) patches, trained with JAX; grouped cross-validation by
park so every number below is for parks the model never saw. ~20k parameters."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import jax
import jax.numpy as jnp
import numpy as np

jax.config.update("jax_platform_name", "cpu")

# (in_channels, out_channels) per conv layer; each followed by ReLU and 2x2 max pool, then global mean + linear.
LAYERS = [(3, 12), (12, 20), (20, 28), (28, 40)]


def init_params(key):
    params = []
    for cin, cout in LAYERS:
        key, k = jax.random.split(key)
        params.append((jax.random.normal(k, (3, 3, cin, cout)) * np.sqrt(2 / (9 * cin)), jnp.zeros(cout)))
    key, k = jax.random.split(key)
    params.append((jax.random.normal(k, (LAYERS[-1][1], 1)) * 0.1, jnp.zeros(1)))
    return params


def forward(params, x):  # x: (N,64,64,3) float in 0..1 -> logits (N,)
    h = x
    for w, b in params[:-1]:
        h = jax.lax.conv_general_dilated(h, w, (1, 1), "SAME", dimension_numbers=("NHWC", "HWIO", "NHWC")) + b
        h = jax.nn.relu(h)
        h = jax.lax.reduce_window(h, -jnp.inf, jax.lax.max, (1, 2, 2, 1), (1, 2, 2, 1), "VALID")
    h = h.mean(axis=(1, 2))
    w, b = params[-1]
    return (h @ w + b)[:, 0]


def loss_fn(params, x, y, pos_weight):
    logits = forward(params, x)
    weights = jnp.where(y == 1, pos_weight, 1.0)
    per = jnp.maximum(logits, 0) - logits * y + jnp.log1p(jnp.exp(-jnp.abs(logits)))
    l2 = sum(jnp.sum(w ** 2) for w, _ in params)
    return jnp.mean(weights * per) + 1e-4 * l2


@jax.jit
def adam_step(params, opt, x, y, pos_weight, lr):
    m, v, t = opt
    loss, grads = jax.value_and_grad(loss_fn)(params, x, y, pos_weight)
    t = t + 1
    m = jax.tree_util.tree_map(lambda m_, g: 0.9 * m_ + 0.1 * g, m, grads)
    v = jax.tree_util.tree_map(lambda v_, g: 0.999 * v_ + 0.001 * g * g, v, grads)
    mhat = jax.tree_util.tree_map(lambda m_: m_ / (1 - 0.9 ** t), m)
    vhat = jax.tree_util.tree_map(lambda v_: v_ / (1 - 0.999 ** t), v)
    params = jax.tree_util.tree_map(lambda p, mh, vh: p - lr * mh / (jnp.sqrt(vh) + 1e-8), params, mhat, vhat)
    return params, (m, v, t), loss


def augment(rng: np.random.Generator, x: np.ndarray) -> np.ndarray:
    # Imagery has no preferred orientation: random 90-degree rotations and flips per batch,
    # plus brightness/contrast jitter because lakes differ a lot.
    x = np.rot90(x, int(rng.integers(4)), axes=(1, 2))
    if rng.random() < 0.5:
        x = x[:, :, ::-1]
    x = (x - 0.5) * rng.uniform(0.8, 1.2) + 0.5 + rng.uniform(-0.08, 0.08)
    return np.clip(x, 0, 1)


def progress(text: str) -> None:
    """One-line status; train_round.py shows these in place and keeps them out of the log."""
    print(f"progress: {text}", flush=True)


def train(x: np.ndarray, y: np.ndarray, epochs: int = 30, seed: int = 0, batch: int = 64, label: str = "training"):
    rng = np.random.default_rng(seed)
    params = init_params(jax.random.PRNGKey(seed))
    opt = (jax.tree_util.tree_map(jnp.zeros_like, params), jax.tree_util.tree_map(jnp.zeros_like, params), 0)
    xf = x.astype(np.float32) / 255
    yf = y.astype(np.float32)
    pos_weight = float((len(y) - y.sum()) / max(1, y.sum()))
    steps = epochs * (len(y) // batch)
    step = 0
    started = time.time()
    for epoch in range(epochs):
        perm = rng.permutation(len(y))
        losses = []
        for i in range(0, len(y) - batch + 1, batch):
            idx = perm[i:i + batch]
            lr = 2e-3 * 0.5 * (1 + np.cos(np.pi * step / steps))
            params, opt, loss = adam_step(params, opt, jnp.asarray(augment(rng, xf[idx])), jnp.asarray(yf[idx]), pos_weight, lr)
            losses.append(float(loss))
            step += 1
        elapsed = time.time() - started
        left = elapsed / (epoch + 1) * (epochs - epoch - 1)
        progress(f"{label}: epoch {epoch + 1}/{epochs}, loss {np.mean(losses):.3f}, {elapsed:.0f} s, about {left:.0f} s left")
    return params


def predict(params, x: np.ndarray) -> np.ndarray:
    xf = x.astype(np.float32) / 255
    fwd = jax.jit(forward)
    out = [np.asarray(fwd(params, jnp.asarray(xf[i:i + 256]))) for i in range(0, len(xf), 256)]
    return 1 / (1 + np.exp(-np.concatenate(out)))


def auc(scores: np.ndarray, labels: np.ndarray) -> float:
    order = np.argsort(scores)
    ranks = np.empty(len(scores)); ranks[order] = np.arange(1, len(scores) + 1)
    pos = labels == 1
    return float((ranks[pos].sum() - pos.sum() * (pos.sum() + 1) / 2) / max(1, pos.sum() * (~pos).sum()))


def save_params(params, path: Path) -> None:
    flat = {}
    for i, (w, b) in enumerate(params):
        flat[f"w{i}"] = np.asarray(w); flat[f"b{i}"] = np.asarray(b)
    np.savez(path, **flat)


def main(npz: Path, out: Path, seed: int = 0) -> None:
    """Five-fold CV by park (the split never changes), then the final model; `seed` varies the weights and the batches."""
    data = np.load(npz)
    x, y, parks, kinds = data["x"], data["y"], data["park"], data["kind"]
    unique = np.unique(parks)
    np.random.default_rng(0).shuffle(unique)
    folds = np.array_split(unique, 5)
    cv = np.zeros(len(y))
    for f, held in enumerate(folds):
        test = np.isin(parks, held)
        params = train(x[~test], y[~test], seed=seed, label=f"fold {f + 1}/5")
        save_params(params, out.with_name(f"{out.stem}.fold{f}.npz"))
        json.dump([str(p) for p in held], open(out.with_name(f"{out.stem}.fold{f}.json"), "w"))
        cv[test] = predict(params, x[test])
        obj = test & (y == 0) & (kinds == "object")
        print(f"fold {f}: {list(held)} AUC {auc(cv[test], y[test]):.3f} recall@0.5 {np.mean(cv[test][y[test] == 1] > 0.5):.2f} "
              f"objects flagged {np.mean(cv[obj] > 0.5) if obj.any() else float('nan'):.2f}", flush=True)
    report = {"auc": auc(cv, y), "recall_bends": float(np.mean(cv[y == 1] > 0.5))}
    for kind in ("object", "water", "land", "falsepeak", "rejected"):
        sel = (y == 0) & (kinds == kind)
        if sel.any():
            report[f"fpr_{kind}"] = float(np.mean(cv[sel] > 0.5))
    report["recall_per_park"] = {p: round(float(np.mean(cv[(parks == p) & (y == 1)] > 0.5)), 2) for p in np.unique(parks)}
    print(json.dumps(report, indent=1))
    np.save(out.with_suffix(".cv-scores.npy"), cv)
    params = train(x, y, seed=seed, label="final model")
    save_params(params, out)
    print("params:", sum(int(np.prod(w.shape)) + int(np.prod(b.shape)) for w, b in params))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 0)
