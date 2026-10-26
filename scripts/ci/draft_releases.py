#!/usr/bin/env python3
"""Keep two draft GitHub releases up to date: the next beta and the next final.

Called from .github/workflows/release-drafts.yml on every push to main and every published
release. Publishing a draft creates its tag and starts the release workflows (Docs/Release.md);
this script only writes drafts.

  beta   X.Y.Z-beta.N  prerelease, notes = changes since the previous beta (or final, if newer)
  final  X.Y.Z         notes = changes since the previous final release

X.Y.Z is the version in progress: the highest version that has a beta but no final yet, or, when
the highest version has its final, the next one (N + 1 in the current month, .1 in a new month).
So publishing the final immediately produces the next pair of drafts, with "No changes" notes
when nothing was merged. Duo test tags (-duo.N) and other suffixes are ignored.

Notes are the first-parent commit subjects of origin/main between the base tag and main, i.e. the
squash-merged PR titles. They are grouped by the type of the PR title (<component>(<type>): ...).

Environment: GITHUB_TOKEN / GH_TOKEN (gh CLI), GITHUB_REPOSITORY. --dry-run prints and writes nothing.

Python 3.9 compatible on purpose, like the other scripts in scripts/ci.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from typing import Dict, List, Optional, Sequence, Tuple

Version = Tuple[int, int, int]

TAG_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$")
TITLE_RE = re.compile(r"^[a-z]+\((?P<type>[a-z]+)\):\s*\S")
MAIN_REF = "origin/main"
MAX_ENTRIES = 200
SECTIONS = (
    ("New", ("feat",)),
    ("Fixed", ("fix",)),
    ("Under the hood", ("refactor", "test", "docs", "chore")),
)
OTHER_SECTION = "Other"


def parse_tag(tag: str) -> Optional[Tuple[Version, Optional[int]]]:
    """(version, beta number or None for a final), or None for any other tag (duo, rc, v-prefix...)."""
    match = TAG_RE.fullmatch(tag)
    if not match:
        return None
    major, minor, patch, beta = match.groups()
    return (int(major), int(minor), int(patch)), (int(beta) if beta is not None else None)


def version_text(version: Version) -> str:
    return "%d.%d.%d" % version


def order_key(tag: str) -> Tuple[Version, int, int]:
    """Release order: betas of a version in order, then its final."""
    version, beta = parse_tag(tag)  # type: ignore[misc]
    return (version, 0, beta) if beta is not None else (version, 1, 0)


def next_version(highest: Version, now: datetime.datetime) -> Version:
    if (highest[0], highest[1]) >= (now.year, now.month):
        return (highest[0], highest[1], highest[2] + 1)
    return (now.year, now.month, 1)


def plan(tags: Sequence[str], now: datetime.datetime) -> Dict[str, Optional[str]]:
    """The drafts that should exist: final and beta tags, and the tag each one's notes start from."""
    parsed = [(tag, parse_tag(tag)) for tag in tags]
    release_tags = [tag for tag, info in parsed if info is not None]
    finals = {info[0] for _, info in parsed if info is not None and info[1] is None}
    betas = [info for _, info in parsed if info is not None and info[1] is not None]
    seen = {info[0] for _, info in parsed if info is not None}

    if not seen:
        version = (now.year, now.month, 1)
    else:
        highest = max(seen)
        version = next_version(highest, now) if highest in finals else highest
    beta_number = max([n for v, n in betas if v == version] or [0]) + 1
    final_tag = version_text(version)
    beta_tag = "%s-beta.%d" % (final_tag, beta_number)

    final_bases = [tag for tag in release_tags if parse_tag(tag)[1] is None]  # type: ignore[index]
    return {
        "final": final_tag,
        "beta": beta_tag,
        "final_base": max(final_bases, key=order_key) if final_bases else None,
        "beta_base": max(release_tags, key=order_key) if release_tags else None,
    }


def render_notes(subjects: Sequence[str], base: Optional[str]) -> str:
    """Markdown release notes from squash-merge subjects, newest first."""
    since = "since %s" % base if base else "yet"
    if not subjects:
        return "No changes %s." % since
    groups = {name: [] for name, _ in SECTIONS}  # type: Dict[str, List[str]]
    groups[OTHER_SECTION] = []
    for subject in subjects[:MAX_ENTRIES]:
        match = TITLE_RE.match(subject)
        kind = match.group("type") if match else ""
        section = next((name for name, kinds in SECTIONS if kind in kinds), OTHER_SECTION)
        groups[section].append("- " + subject)
    blocks = ["## %s\n\n%s" % (name, "\n".join(lines)) for name, lines in groups.items() if lines]
    if len(subjects) > MAX_ENTRIES:
        blocks.append("_%d older changes not listed._" % (len(subjects) - MAX_ENTRIES))
    return "\n\n".join(blocks)


def run(*args: str) -> str:
    result = subprocess.run(args, check=True, capture_output=True, text=True, timeout=120)
    return result.stdout


def git_tags() -> List[str]:
    return [line for line in run("git", "tag", "--list").splitlines() if line]


def main_subjects(base: Optional[str]) -> List[str]:
    """First-parent subjects on main after base; the whole history when base is unknown or not on main."""
    rev = "%s..%s" % (base, MAIN_REF) if base else MAIN_REF
    try:
        out = run("git", "log", "--first-parent", "--format=%s", rev)
    except subprocess.CalledProcessError:
        out = run("git", "log", "--first-parent", "--format=%s", MAIN_REF)
    return [line.strip() for line in out.splitlines() if line.strip()]


def gh_json(method: str, path: str, payload: Optional[dict] = None):
    cmd = ["gh", "api", "-X", method, path]
    if payload is not None:
        cmd += ["--input", "-"]
    result = subprocess.run(
        cmd, check=True, capture_output=True, text=True, timeout=120,
        input=json.dumps(payload) if payload is not None else None,
    )
    return json.loads(result.stdout) if result.stdout.strip() else None


def list_releases(repo: str) -> List[dict]:
    pages = run("gh", "api", "--paginate", "--slurp", "repos/%s/releases?per_page=100" % repo)
    return [release for page in json.loads(pages) for release in page]


def sync_draft(repo: str, releases: Sequence[dict], tag: str, prerelease: bool, body: str, dry_run: bool) -> str:
    """Create the managed draft of this kind, or update it in place (a stale tag is renamed)."""
    drafts = [
        r for r in releases
        if r.get("draft") and parse_tag(r["tag_name"]) is not None
        and (parse_tag(r["tag_name"])[1] is not None) == prerelease  # type: ignore[index]
    ]
    wanted = {"tag_name": tag, "name": tag, "body": body, "prerelease": prerelease, "draft": True,
              "target_commitish": "main"}
    existing = next((r for r in drafts if r["tag_name"] == tag), drafts[0] if drafts else None)
    if existing is None:
        action = "create"
    elif all(existing.get(key) == value for key, value in wanted.items() if key != "target_commitish") \
            and existing.get("target_commitish") == "main":
        return "%s: up to date" % tag
    else:
        action = "update"
    print("%s draft %s:\n%s\n" % (action, tag, body), flush=True)
    if dry_run:
        return "%s: would %s" % (tag, action)
    if existing is None:
        gh_json("POST", "repos/%s/releases" % repo, wanted)
    else:
        gh_json("PATCH", "repos/%s/releases/%d" % (repo, existing["id"]), wanted)
    return "%s: %sd" % (tag, action)


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="print the drafts, change nothing")
    args = parser.parse_args(argv)
    repo = os.environ.get("GITHUB_REPOSITORY", "DCSBL/rppl")

    releases = list_releases(repo)
    published = [r["tag_name"] for r in releases if not r.get("draft")]
    tags = sorted(set(git_tags()) | set(published))
    drafts = plan(tags, datetime.datetime.now(datetime.timezone.utc))

    summary = [
        sync_draft(repo, releases, drafts["beta"], True,
                   render_notes(main_subjects(drafts["beta_base"]), drafts["beta_base"]), args.dry_run),
        sync_draft(repo, releases, drafts["final"], False,
                   render_notes(main_subjects(drafts["final_base"]), drafts["final_base"]), args.dry_run),
    ]
    text = "### Draft releases\n\n" + "\n".join("- " + line for line in summary) + "\n"
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as handle:
            handle.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
