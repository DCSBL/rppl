#!/usr/bin/env python3
"""Run the RpplCore tests with coverage and refuse a drop below the recorded baseline.

    scripts/check-core-coverage.py                 # run tests, compare with the baseline
    scripts/check-core-coverage.py --no-run        # compare an existing coverage run
    scripts/check-core-coverage.py --update        # raise the baseline after improving coverage

Measured over `RpplCore/Sources/RpplCore` only (test files and package checkouts are excluded, so
well-covered tests cannot inflate the number). Two rules, both in `RpplCore/coverage-baseline.json`:

  * total line and function coverage may not drop more than `tolerance` points below the baseline;
  * each critical file (session store, transfer, detection, ...) may not gain more than
    `criticalMissedLinesAllowed` uncovered lines compared with the baseline.

The baseline only ratchets up: `--update` never lowers a value unless `--allow-lower` is given,
which belongs in a PR that explains why. Exit code 1 on a violation, 2 when the run itself fails.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PACKAGE = REPO / "RpplCore"
BASELINE = PACKAGE / "coverage-baseline.json"
SOURCES_MARKER = "/RpplCore/Sources/RpplCore/"

DEFAULT_TOLERANCE = 0.2
DEFAULT_CRITICAL_MISSED_ALLOWED = 2

# Data durability, transfer and detection: a regression here costs a rider's session.
CRITICAL_FILES = [
    "Session/SessionFileStore.swift",
    "Session/SessionFlushWriter.swift",
    "Session/CompressedJSONLFrames.swift",
    "Session/StoreIO.swift",
    "Session/SampleRequeue.swift",
    "Session/SessionRecovery.swift",
    "Session/SessionPackageLocator.swift",
    "Session/SessionRootMigrator.swift",
    "Session/SessionImportLimits.swift",
    "Session/SessionIdValidator.swift",
    "Session/MotionRecordingPolicy.swift",
    "Session/TransferStateMachine.swift",
    "Session/SessionStatsBuilder.swift",
    "Session/SessionLoader.swift",
    "Sync/SessionImportFailure.swift",
    "Sync/TransferRetryPolicy.swift",
    "Sync/TransferPendingFilter.swift",
    "Sync/WatchViewDeletePolicy.swift",
    "Sync/WatchViewSyncCodec.swift",
    "Detection/DetectionEngine.swift",
    "Detection/DetectionHoldClock.swift",
    "Detection/Detectors.swift",
    "Detection/GpsSignalFilter.swift",
    "Detection/LocationFixSequencer.swift",
]


def run_tests() -> None:
    print("==> swift test --enable-code-coverage (RpplCore)", flush=True)
    result = subprocess.run(["swift", "test", "--enable-code-coverage", "--no-parallel"], cwd=PACKAGE)
    if result.returncode != 0:
        print("Tests failed; coverage not evaluated.", file=sys.stderr)
        sys.exit(2)


def codecov_json_path() -> Path:
    result = subprocess.run(
        ["swift", "test", "--show-codecov-path"], cwd=PACKAGE, capture_output=True, text=True
    )
    path = Path(result.stdout.strip().splitlines()[-1]) if result.stdout.strip() else None
    if not path or not path.exists():
        print("No coverage data found. Run without --no-run first.", file=sys.stderr)
        sys.exit(2)
    return path


def measure(path: Path) -> dict:
    data = json.loads(path.read_text())["data"][0]
    total = {"lines": [0, 0], "functions": [0, 0]}
    files: dict[str, dict] = {}
    for entry in data["files"]:
        name = entry["filename"]
        if SOURCES_MARKER not in name or "/.build/" in name:
            continue
        short = name.split(SOURCES_MARKER, 1)[1]
        lines = entry["summary"]["lines"]
        funcs = entry["summary"]["functions"]
        files[short] = {"lines": lines["count"], "missed": lines["count"] - lines["covered"]}
        total["lines"][0] += lines["covered"]
        total["lines"][1] += lines["count"]
        total["functions"][0] += funcs["covered"]
        total["functions"][1] += funcs["count"]
    pct = lambda pair: round(100.0 * pair[0] / pair[1], 2) if pair[1] else 0.0  # noqa: E731
    return {
        "lines": pct(total["lines"]),
        "functions": pct(total["functions"]),
        "files": files,
    }


def load_baseline() -> dict | None:
    return json.loads(BASELINE.read_text()) if BASELINE.exists() else None


def compare(current: dict, baseline: dict) -> tuple[list[str], list[str]]:
    failures: list[str] = []
    notes: list[str] = []
    tolerance = baseline.get("tolerance", DEFAULT_TOLERANCE)
    for metric in ("lines", "functions"):
        floor = baseline[metric]
        value = current[metric]
        if value < floor - tolerance:
            failures.append(f"total {metric} coverage {value:.2f}% is below the baseline {floor:.2f}% (tolerance {tolerance})")
        elif value > floor + 0.5:
            notes.append(f"total {metric} coverage is {value:.2f}% (baseline {floor:.2f}%): run --update to ratchet")
    allowed = baseline.get("criticalMissedLinesAllowed", DEFAULT_CRITICAL_MISSED_ALLOWED)
    for name, recorded in baseline.get("critical", {}).items():
        now = current["files"].get(name)
        if now is None:
            failures.append(f"critical file {name} is no longer measured (renamed or removed?): update the baseline")
            continue
        if now["missed"] > recorded["missed"] + allowed:
            failures.append(
                f"{name}: {now['missed']} lines uncovered, baseline {recorded['missed']} (+{allowed} allowed): "
                "add tests for the new code"
            )
        elif now["missed"] < recorded["missed"] - 5:
            notes.append(f"{name}: {now['missed']} uncovered (baseline {recorded['missed']}): run --update to ratchet")
    return failures, notes


def new_baseline(current: dict, previous: dict | None, allow_lower: bool) -> dict:
    baseline = {
        "_comment": "Written by scripts/check-core-coverage.py --update. Only ratchets up; see the script.",
        "tolerance": (previous or {}).get("tolerance", DEFAULT_TOLERANCE),
        "criticalMissedLinesAllowed": (previous or {}).get("criticalMissedLinesAllowed", DEFAULT_CRITICAL_MISSED_ALLOWED),
        "lines": current["lines"],
        "functions": current["functions"],
        "critical": {
            name: {"lines": current["files"][name]["lines"], "missed": current["files"][name]["missed"]}
            for name in CRITICAL_FILES
            if name in current["files"]
        },
    }
    if previous and not allow_lower:
        for metric in ("lines", "functions"):
            baseline[metric] = max(baseline[metric], previous[metric])
        for name, recorded in previous.get("critical", {}).items():
            if name in baseline["critical"]:
                baseline["critical"][name]["missed"] = min(baseline["critical"][name]["missed"], recorded["missed"])
    return baseline


def write_summary(current: dict, baseline: dict | None, failures: list[str]) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    lines = ["### RpplCore coverage", "", "| | now | baseline |", "|---|---|---|"]
    for metric in ("lines", "functions"):
        recorded = f"{baseline[metric]:.2f}%" if baseline else "-"
        lines.append(f"| {metric} | {current[metric]:.2f}% | {recorded} |")
    lines.append("")
    if failures:
        lines.extend(f"- ❌ {failure}" for failure in failures)
    else:
        lines.append("✅ no regression")
    with open(path, "a", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-run", action="store_true", help="evaluate the last coverage run instead of running tests")
    parser.add_argument("--update", action="store_true", help="write the current numbers as the new baseline")
    parser.add_argument("--allow-lower", action="store_true", help="with --update: allow lowering a value (explain in the PR)")
    parser.add_argument("--package-dir", type=Path, help="RpplCore directory to measure (default: this repo)")
    args = parser.parse_args()

    global PACKAGE, BASELINE
    if args.package_dir:
        PACKAGE = args.package_dir.resolve()
        BASELINE = PACKAGE / "coverage-baseline.json"

    if not args.no_run:
        run_tests()
    current = measure(codecov_json_path())
    baseline = load_baseline()
    print(f"\nRpplCore coverage (Sources only): lines {current['lines']:.2f}%  functions {current['functions']:.2f}%")

    if args.update:
        updated = new_baseline(current, baseline, args.allow_lower)
        BASELINE.write_text(json.dumps(updated, indent=2, sort_keys=False) + "\n")
        print(f"Baseline written to {BASELINE.relative_to(REPO) if BASELINE.is_relative_to(REPO) else BASELINE}: "
              f"lines {updated['lines']:.2f}%  functions {updated['functions']:.2f}%  "
              f"({len(updated['critical'])} critical files)")
        return 0

    if baseline is None:
        print("No baseline yet. Create one with --update.", file=sys.stderr)
        return 1
    failures, notes = compare(current, baseline)
    write_summary(current, baseline, failures)
    for note in notes:
        print(f"note: {note}")
    if failures:
        print("\n✘ Coverage regression:")
        for failure in failures:
            print(f"  - {failure}")
        print("\nAdd tests, or (with a reason in the PR) --update --allow-lower.")
        return 1
    print(f"✔ coverage at or above the baseline (lines {baseline['lines']:.2f}%, functions {baseline['functions']:.2f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
