"""One training round of the tower net, start to finish, with progress in the terminal.

    python3 train_round.py --sets <training-set> [<training-set> ...] --work <dir> [--copy-to <dir>]

`--sets` are exported training sets (each a folder with training-set.json and PNGs), merged in order;
a later set replaces an earlier row for the same park. Steps: merge, patches, train (5-fold CV + final
model), mine the confident false peaks as extra negatives, train again, evaluate the loop fit on the
traced parks with the per-fold models. Every step's full output goes to <work>/<step>.log; the
terminal shows one status line per step and a summary at the end. `--copy-to` copies the weights,
fold models and logs there (e.g. the iCloud folder), not the patches or images.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
TTY = sys.stdout.isatty()


def merge(sets: list[Path], out: Path) -> str:
    out.mkdir(parents=True, exist_ok=True)
    rows: dict[str, dict] = {}
    for folder in sets:
        # The first export kept its training-set.json next to the folder instead of inside it.
        index = folder / "training-set.json"
        if not index.exists() and folder.with_suffix(".json").exists():
            index = folder.with_suffix(".json")
        for row in json.loads(index.read_text()):
            rows[row["parkID"]] = row
        for png in folder.glob("*.png"):
            shutil.copy2(png, out / png.name)
    (out / "training-set.json").write_text(json.dumps(list(rows.values())))
    labelled = sum(1 for r in rows.values() if r.get("towers"))
    traced = sum(1 for r in rows.values() if any(len((c.get("geometry") or {}).get("pointsXY") or []) >= 2 for c in r.get("cables") or []))
    return f"{len(rows)} parks ({traced} traced, {labelled} with tower labels)"


def status(text: str) -> None:
    if TTY:
        print(f"\r\033[K  {text[:110]}", end="", flush=True)


def run(step: str, args: list[str], log: Path) -> list[str]:
    """Runs one pipeline script; progress lines update in place, everything else goes to the log."""
    kept: list[str] = []
    with log.open("w") as handle, subprocess.Popen(
        [sys.executable, "-u", *args], cwd=HERE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    ) as process:
        assert process.stdout is not None
        for line in process.stdout:
            if line.startswith("progress: "):
                status(line[len("progress: "):].rstrip())
                continue
            handle.write(line)
            handle.flush()
            kept.append(line.rstrip())
            if not TTY and not line.startswith("{"):
                print(f"  {line.rstrip()}", flush=True)
    if TTY:
        print("\r\033[K", end="")
    if process.returncode != 0:
        print(f"\n{step} failed (exit {process.returncode}); last lines of {log}:")
        print("\n".join(kept[-15:]))
        sys.exit(process.returncode)
    return kept


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sets", type=Path, nargs="+", required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--copy-to", type=Path)
    parser.add_argument("--name", default="towernet", help="file stem of the trained weights")
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    ts, name = work / "training-set", args.name
    patches, mined = work / "patches.npz", work / "patches-mined.npz"
    first, final = work / f"{name}-a.npz", work / f"{name}.npz"

    steps = [
        ("Patches", ["cabledetect/towerpatches.py", ts, patches]),
        ("Train, round 1", ["cabledetect/towertrain.py", patches, first]),
        ("Mine false peaks", ["cabledetect/towermine.py", ts, patches, first, mined]),
        ("Train, round 2", ["cabledetect/towertrain.py", mined, final]),
        ("Evaluate loops", ["run.py", ts, "--out", work / "eval", "--towers", final, "--given-others"]),
    ]
    total = len(steps) + 1
    started = time.time()

    print(f"[1/{total}] Merge training sets")
    print(f"  {merge([s.resolve() for s in args.sets], ts)}")
    outputs: dict[str, list[str]] = {}
    for number, (step, step_args) in enumerate(steps, 2):
        step_started = time.time()
        print(f"[{number}/{total}] {step}")
        log = work / f"{number}-{step.lower().replace(',', '').replace(' ', '-')}.log"
        outputs[step] = run(step, [str(a) for a in step_args], log)
        print(f"  done in {time.time() - step_started:.0f} s ({log.name})")

    report = "\n".join(outputs["Train, round 2"])
    summary = json.JSONDecoder().raw_decode(report[report.index("{"):])[0] if "{" in report else {}
    print(f"\nFinished in {(time.time() - started) / 60:.1f} min. Tower net, parks held out (5-fold CV):")
    for key in ("auc", "recall_bends", "fpr_rejected", "fpr_falsepeak", "fpr_object", "fpr_water"):
        if key in summary:
            print(f"  {key:15s} {summary[key]:.3f}")
    print("Loop fit on the traced parks:")
    print("  " + next((line for line in reversed(outputs["Evaluate loops"]) if "parks with a proposal" in line), "no summary line"))

    if args.copy_to:
        target = args.copy_to.resolve()
        target.mkdir(parents=True, exist_ok=True)
        for path in [final, *work.glob(f"{name}.fold*"), work / f"{name}.cv-scores.npy", work / "eval" / "results.json", *work.glob("*.log")]:
            if path.exists():
                shutil.copy2(path, target / (path.name if path.parent == work else f"eval-{path.name}"))
        print(f"Copied weights, fold models and logs to {target}")


if __name__ == "__main__":
    main()
