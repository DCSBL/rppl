"""The whole tower training from the phone's zip, for a long unattended run (on a Mac it takes a few
hours). Every stage writes its own folder under --work and is skipped when it already finished, so
stop it any time (Ctrl-C, sleep, reboot) and start the same command again to carry on.

    python3 overnight.py --zip tower-review-....zip --old-sets <set> [<set> ...] --work <dir> [--copy-to <dir>]

Stages:
1. phone set: the zip -> training set with the map's water (phone_set.py)
2. close-up check: the zoomed second look, leave-parks-out (cabledetect/closeupcheck.py)
3. coarse net on 64 px patches with the real water (train_round.py, what the app runs)
4. coarse net on 128 px patches (train_round.py --patch 128)
Then REPORT.md in --work sums it up against the shipped net. --copy-to gets the report, the logs,
the weights and the pictures after every stage (e.g. the iCloud folder), so nothing is lost.
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

# The shipped net (v3 at 0.7) on the traced parks, from RESULTS.md, for comparison.
SHIPPED = "median IoU 0.75, IoU >= 0.7 for 22 of 35, median bend error 21.5 m"


def stage(name: str, done: Path, command: list, log: Path) -> None:
    if done.exists():
        print(f"== {name}: already done", flush=True)
        return
    print(f"== {name}", flush=True)
    started = time.time()
    with log.open("a") as handle:
        result = subprocess.run([sys.executable, "-u", *map(str, command)], cwd=HERE, stdout=handle, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        print(f"{name} failed (exit {result.returncode}); see {log}. Start the same command again to retry it.")
        sys.exit(result.returncode)
    done.touch()
    print(f"   done in {(time.time() - started) / 60:.0f} min ({log.name})", flush=True)


def last_json(log: Path) -> dict:
    text = log.read_text() if log.exists() else ""
    start = text.rfind("\n{")
    try:
        return json.JSONDecoder().raw_decode(text[start + 1:])[0] if start >= 0 else {}
    except json.JSONDecodeError:
        return {}


def round_summary(log: Path) -> list[str]:
    if not log.exists():
        return ["not run yet"]
    lines = log.read_text().splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.startswith("Finished in"))
    except StopIteration:
        return ["not finished yet"]
    return [line.strip() for line in lines[start:start + 10] if line.strip()]


def report(work: Path) -> str:
    check = last_json(work / "2-closeup-check.log")
    out = ["# Tower training report", ""]
    out += ["## Close-up check (zoomed second look, parks held out)", ""]
    if check:
        out += [
            f"- {check['closeups']} close-ups from {check['parks']} parks: {check['towers']} towers, {check['rejected']} rejected guesses.",
            f"- AUC {check['auc']:.3f}. At 0.5 it keeps {check['towers_kept@0.5']:.0%} of the towers and removes {check['rejected_removed@0.5']:.0%} of the rejected guesses.",
            f"- Keeping 98% of the towers (threshold {check['threshold_keep98']:.2f}) it still removes {check['rejected_removed@keep98']:.0%} of the rejected guesses.",
        ]
        if "coarse_auc_same_guesses" in check:
            out.append(f"- On the same detector guesses the coarse net's own probability has AUC {check['coarse_auc_same_guesses']:.3f}; the check {check['check_auc_same_guesses']:.3f}.")
        out.append("- Worst held-out mistakes: closeup/closeupcheck-mistakes.png; every score: closeup/closeupcheck-scores.csv.")
    else:
        out.append("not run yet")
    for patch in (64, 128):
        out += ["", f"## Coarse net, {patch} px patches, with the map's water", ""]
        out += [f"    {line}" for line in round_summary(work / f"{2 + patch // 64}-round-{patch}.log")]
    out += ["", f"Shipped net (v3 at 0.7) on the same traced parks: {SHIPPED}.", ""]
    return "\n".join(out)


def copy_results(work: Path, target: Path | None) -> None:
    (work / "REPORT.md").write_text(report(work))
    if target is None:
        return
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(work / "REPORT.md", target / "REPORT.md")
    for path in work.glob("*.log"):
        shutil.copy2(path, target / path.name)
    closeup = work / "closeup"
    if closeup.is_dir():
        (target / "closeup").mkdir(exist_ok=True)
        for path in [*closeup.glob("closeupcheck*.npz"), *closeup.glob("*.csv"), *closeup.glob("*.png")]:
            shutil.copy2(path, target / "closeup" / path.name)
    for patch in (64, 128):
        folder = work / f"round-{patch}"
        if not folder.is_dir():
            continue
        (target / f"round-{patch}").mkdir(exist_ok=True)
        for path in [*folder.glob("towernet.*"), *folder.glob("*.log"), folder / "eval" / "results.json"]:
            if path.is_file():
                shutil.copy2(path, target / f"round-{patch}" / path.name)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zip", type=Path, required=True)
    parser.add_argument("--old-sets", type=Path, nargs="+", required=True, help="older exported training sets (Mac renders)")
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--copy-to", type=Path)
    parser.add_argument("--skip-128", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    target = args.copy_to.resolve() if args.copy_to else None
    phone = work / "phone-set"

    stage("1/4 phone set", work / "1.done", ["phone_set.py", args.zip.resolve(), phone], work / "1-phone-set.log")
    copy_results(work, target)
    stage("2/4 close-up check", work / "2.done", ["cabledetect/closeupcheck.py", phone, work / "closeup", "--resume"], work / "2-closeup-check.log")
    copy_results(work, target)
    sets = [s.resolve() for s in args.old_sets] + [phone]
    for number, patch in ((3, 64), (4, 128)):
        if patch == 128 and args.skip_128:
            continue
        stage(f"{number}/4 coarse net {patch} px", work / f"{number}.done",
              ["train_round.py", "--sets", *sets, "--work", work / f"round-{patch}", "--patch", patch, "--resume"],
              work / f"{number}-round-{patch}.log")
        copy_results(work, target)
    print((work / "REPORT.md").read_text())


if __name__ == "__main__":
    main()
