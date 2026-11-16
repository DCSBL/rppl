#!/usr/bin/env python3
"""Open GitHub issues for parks whose opening hours marker fired.

Usage:
    python3 scripts/ci/hours_watch_issues.py RESULTS.json [--dry-run] [--run-url URL] [--repo OWNER/NAME]

RESULTS.json is written by `scripts/hours_watch.py --results`. Only parks with status
"markers" get an issue ("page changed" and "unreachable" are too noisy and stay in the run
summary). Per park there is at most one open issue labelled `hours-watch`, titled
`parks: check opening hours of <park-id>`. When one is open, a comment is added only if the
set of fired markers differs from the last one reported there. Nothing is closed
automatically: a maintainer closes the issue after refreshing the park.

--dry-run prints what would happen and needs neither `gh` nor a token. Otherwise `gh` is used
with GH_TOKEN. Exit code is 1 when any issue could not be created or commented.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

LABEL = "hours-watch"
LABEL_COLOR = "fbca04"
SKILL_PATH = ".claude/skills/park-data-collection/SKILL.md"
SIGNATURE = re.compile(r"<!-- hours-watch-markers: ([0-9a-f]{12}) -->")


def title(park_id: str) -> str:
    return f"parks: check opening hours of {park_id}"


def signature(markers: list[str]) -> str:
    return hashlib.sha256("\n".join(sorted(markers)).encode()).hexdigest()[:12]


def fired_parks(results: list[dict]) -> list[dict]:
    """Parks with a fired marker. Page-changed and unreachable parks never get an issue."""
    return [r for r in results if r.get("status") == "markers" and r.get("markers")]


def last_signature(texts: list[str]) -> str | None:
    """Signature from the newest text (issue body first, then comments in order) that has one."""
    found = None
    for text in texts:
        matches = SIGNATURE.findall(text or "")
        if matches:
            found = matches[-1]
    return found


def markers_block(markers: list[str]) -> str:
    return "\n".join(f"- {m}" for m in markers)


def issue_body(park: dict, name: str | None, run_url: str | None, today: str) -> str:
    label = f"{name} (`{park['id']}`)" if name else f"`{park['id']}`"
    lines = [
        f"The weekly opening hours watch found that the hours page of {label} no longer matches "
        f"what we recorded, so its opening hours may be out of date.",
        "",
        f"Hours page (`opening.source_url`): {park['url']}",
        "",
        f"Markers that fired on {today}:",
        "",
        markers_block(park["markers"]),
        "",
        "A `present` marker is text that should be on the page and is gone; an `absent` marker is "
        "text that should not be there and showed up. The markers live in "
        "`ops/hours-watch/markers.yaml`.",
        "",
        f"To refresh the park, follow `{SKILL_PATH}` (official site only, no guessing), update "
        "the park YAML and the marker if the wording changed, then close this issue.",
    ]
    if run_url:
        lines += ["", f"Workflow run: {run_url}"]
    lines += ["", f"<!-- hours-watch-markers: {signature(park['markers'])} -->"]
    return "\n".join(lines)


def comment_body(park: dict, run_url: str | None, today: str) -> str:
    lines = [
        f"The set of fired markers changed. As of {today}:",
        "",
        markers_block(park["markers"]),
    ]
    if run_url:
        lines += ["", f"Workflow run: {run_url}"]
    lines += ["", f"<!-- hours-watch-markers: {signature(park['markers'])} -->"]
    return "\n".join(lines)


def plan(parks: list[dict], open_issues: dict[str, dict]) -> list[tuple[str, dict, dict | None]]:
    """(action, park, issue) per fired park: create, comment or skip. `open_issues` maps title to
    {"number", "texts"} where texts are the issue body followed by its comments."""
    actions = []
    for park in parks:
        issue = open_issues.get(title(park["id"]))
        if issue is None:
            actions.append(("create", park, None))
        elif last_signature(issue["texts"]) == signature(park["markers"]):
            actions.append(("skip", park, issue))
        else:
            actions.append(("comment", park, issue))
    return actions


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def load_open_issues(repo_args: list[str]) -> dict[str, dict]:
    out = gh("issue", "list", *repo_args, "--label", LABEL, "--state", "open", "--limit", "200",
             "--json", "number,title,body,comments")
    return {
        i["title"]: {"number": i["number"], "texts": [i["body"], *[c["body"] for c in i["comments"]]]}
        for i in json.loads(out)
    }


def ensure_label(repo_args: list[str]) -> None:
    gh("label", "create", LABEL, *repo_args, "--color", LABEL_COLOR, "--force",
       "--description", "Opening hours page changed, park data may be stale")


def park_names() -> dict[str, str]:
    import yaml  # same dependency as hours_watch.py

    from_dir = Path(__file__).resolve().parents[2] / "RpplCore" / "Sources" / "RpplCore" / "Resources" / "Parks"
    names = {}
    for path in from_dir.glob("*.yaml"):
        data = yaml.safe_load(path.read_text())
        names[data["id"]] = data.get("name")
    return names


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("results", type=Path)
    parser.add_argument("--dry-run", action="store_true", help="print the plan, touch nothing")
    parser.add_argument("--run-url", help="link to the workflow run")
    parser.add_argument("--repo", help="OWNER/NAME (default: the current checkout)")
    parser.add_argument("--summary", type=Path, help="append an outcome section to this file")
    args = parser.parse_args()

    parks = fired_parks(json.loads(args.results.read_text()))
    try:
        names = park_names()
    except ImportError:
        names = {}
    today = datetime.date.today().isoformat()
    repo_args = ["--repo", args.repo] if args.repo else []

    open_issues: dict[str, dict] = {}
    if not args.dry_run and parks:
        ensure_label(repo_args)
        open_issues = load_open_issues(repo_args)

    report = ["## Issues", ""]
    failures = 0
    for action, park, issue in plan(parks, open_issues):
        pid = park["id"]
        try:
            if action == "create":
                body = issue_body(park, names.get(pid), args.run_url, today)
                if args.dry_run:
                    print(f"--- would create: {title(pid)}\n{body}\n")
                else:
                    url = gh("issue", "create", *repo_args, "--title", title(pid), "--label", LABEL,
                             "--body", body).strip()
                    report.append(f"- {pid}: opened {url}")
            elif action == "comment":
                body = comment_body(park, args.run_url, today)
                if args.dry_run:
                    print(f"--- would comment on #{issue['number']} ({title(pid)})\n{body}\n")
                else:
                    gh("issue", "comment", str(issue["number"]), *repo_args, "--body", body)
                    report.append(f"- {pid}: markers changed, commented on #{issue['number']}")
            else:
                report.append(f"- {pid}: open issue #{issue['number']} already lists these markers")
        except subprocess.CalledProcessError as error:
            failures += 1
            report.append(f"- {pid}: **failed** ({error.stderr.strip() or error})")
    if not parks:
        report.append("No marker fired, no issues needed.")

    text = "\n".join(report) + "\n"
    if not args.dry_run:
        print(text)
    if args.summary:
        with args.summary.open("a") as handle:
            handle.write(text + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
