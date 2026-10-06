#!/usr/bin/env python3
"""Prepare a release build from a GitHub release tag (Xcode Cloud + GitHub preflight).

Called from ci_scripts/ci_post_clone.sh when Xcode Cloud builds a release, and from
.github/workflows/release-preflight.yml with --check-only when a release is published.
Xcode Cloud starts from the branch release/X.Y.Z (one Build Group per version), which
.github/workflows/release-branch.yml pushes using --release-branch. A branch build has no
CI_TAG: --branch finds the release tag that points at the built commit.

Build mode (default), for tag X.Y.Z, vX.Y.Z or either with a -suffix (2026.9.1, v2026.9.1-beta.1):
  1. Validate the tag and derive the marketing version X.Y.Z (suffix dropped).
  2. Require the tagged commit to be on main (GitHub compare API, skipped when unreachable).
  3. Set every MARKETING_VERSION in Rppl.xcodeproj (iPhone and Watch must match).
  4. Write the GitHub release body as TestFlight/WhatToTest.en-US.txt (plain text, 4000 chars).
  5. Stamp RpplBuildDate, RpplReleaseTag (tag without the v) and RpplGitCommit (short SHA of
     CI_COMMIT, else git HEAD) in Rppl/Info.plist. The About screen shows them.
The build number is left alone: Xcode Cloud assigns it (CI_BUILD_NUMBER).

--check-only does steps 1-2 plus a non-empty release body check, writes nothing and
prints the What to Test preview (also to $GITHUB_STEP_SUMMARY when set).

--release-branch does steps 1-2, writes nothing and reports the branch name release/X.Y.Z
("branch=..." in $GITHUB_OUTPUT when set).

Environment:
  RPPL_GITHUB_TOKEN / GITHUB_TOKEN   read access to the release (repo is private)
  RPPL_GITHUB_REPO / GITHUB_REPOSITORY   owner/name, default DCSBL/rppl
  RPPL_RELEASE_JSON                  path to a release JSON fixture; no network calls at all
  RPPL_RELEASE_RETRIES / RPPL_RELEASE_RETRY_DELAY   wait for the release to appear (6 x 10s)

Python 3.9 compatible on purpose (Xcode command line tools ship 3.9).
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

DEFAULT_REPO = "DCSBL/rppl"
NOTES_LOCALE = "en-US"
NOTES_LIMIT = 4000
TAG_RE = re.compile(r"^v?(\d+\.\d+\.\d+)(?:-([0-9A-Za-z][0-9A-Za-z.-]*))?$")
BRANCH_PREFIX = "release/"
BRANCH_RE = re.compile(r"^release/(\d+\.\d+\.\d+)$")
TAGS_PER_PAGE = 100
TAGS_MAX_PAGES = 5
MARKETING_VERSION_RE = re.compile(r"MARKETING_VERSION = [^;]+;")
SHA_RE = re.compile(r"[0-9a-f]{7,64}")
SHORT_SHA_LENGTH = 7
PBXPROJ = Path("Rppl.xcodeproj/project.pbxproj")
APP_INFO_PLIST = Path("Rppl/Info.plist")
FALLBACK_COMMITS = 10


class ReleaseError(Exception):
    """A problem that must stop the release build."""


def annotate(level: str, message: str) -> None:
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print("::%s::%s" % (level, message), flush=True)
    else:
        print("%s: %s" % (level, message), file=sys.stderr, flush=True)


def parse_tag(tag: str) -> Tuple[str, Optional[str]]:
    """Return (marketing version, suffix) or raise ReleaseError."""
    match = TAG_RE.fullmatch(tag)
    if not match:
        raise ReleaseError(
            "Tag %r is not a release tag. Use X.Y.Z or vX.Y.Z, optionally with a -beta.N suffix "
            "(App Store versions are three integers)." % tag
        )
    return match.group(1), match.group(2)


def release_branch(version: str) -> str:
    """The branch Xcode Cloud builds for a marketing version: every build of X.Y.Z shares it."""
    return BRANCH_PREFIX + version


def parse_release_branch(branch: str) -> str:
    """Return the marketing version of release/X.Y.Z or raise ReleaseError."""
    match = BRANCH_RE.fullmatch(branch)
    if not match:
        raise ReleaseError("Branch %r is not a release branch. Expected release/X.Y.Z." % branch)
    return match.group(1)


def bump_marketing_version(pbxproj_text: str, version: str) -> Tuple[str, int]:
    """Set every MARKETING_VERSION to version; return (new text, occurrences)."""
    new_text, count = MARKETING_VERSION_RE.subn("MARKETING_VERSION = %s;" % version, pbxproj_text)
    if count == 0:
        raise ReleaseError("No MARKETING_VERSION found in the Xcode project.")
    return new_text, count


def stamp_plist_string(plist_text: str, key: str, value: str) -> Tuple[str, bool]:
    """Set the <string> after <key>key</key>. Values are tag, SHA or date text: no XML escaping needed."""
    pattern = re.compile(r"(<key>%s</key>\s*<string>)[^<]*(</string>)" % re.escape(key))
    new_text, count = pattern.subn(lambda match: match.group(1) + value + match.group(2), plist_text)
    return new_text, count > 0


def stamp_build_date(plist_text: str, date: str) -> Tuple[str, bool]:
    return stamp_plist_string(plist_text, "RpplBuildDate", date)


def release_label(tag: str) -> str:
    """The tag as shown in the app: without the leading v."""
    return tag[1:] if tag.startswith("v") else tag


def commit_sha(root: Path) -> Optional[str]:
    """Full SHA of the commit being built: Xcode Cloud's CI_COMMIT, else git HEAD. None if unknown."""
    sha = (os.environ.get("CI_COMMIT") or "").strip().lower()
    if not sha:
        try:
            head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=str(root), check=False, capture_output=True, text=True, timeout=30,
            )
            sha = head.stdout.strip().lower() if head.returncode == 0 else ""
        except (OSError, subprocess.SubprocessError):
            sha = ""
    return sha if SHA_RE.fullmatch(sha) else None


def short_commit(root: Path) -> Optional[str]:
    sha = commit_sha(root)
    return sha[:SHORT_SHA_LENGTH] if sha else None


def markdown_to_plain(markdown: str) -> str:
    """Flatten GitHub markdown to plain text. TestFlight shows What to Test literally."""
    text = markdown.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)
    text = re.sub(r"^[ \t]*```.*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"^[ \t]*(-{3,}|\*{3,}|_{3,})[ \t]*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"^#{1,6}[ \t]+", "", text, flags=re.MULTILINE)
    text = re.sub(r"^([ \t]*)[*+-][ \t]+", lambda m: "%s- " % m.group(1), text, flags=re.MULTILINE)
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\*\*(.+?)\*\*|__(.+?)__", lambda m: m.group(1) or m.group(2), text)
    text = re.sub(r"(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])", r"\1", text)
    text = text.replace("`", "")
    text = "\n".join(line.rstrip() for line in text.split("\n"))
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def truncate(text: str, limit: int = NOTES_LIMIT) -> str:
    if len(text) <= limit:
        return text
    cut = text[: limit - 1]
    newline = cut.rfind("\n")
    if newline > limit - 300:
        cut = cut[:newline]
    return cut.rstrip() + "…"


def http_get_json(url: str, token: Optional[str]) -> Tuple[int, Any]:
    """GET a GitHub API URL. Returns (status, parsed JSON or None); status 0 = network error."""
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "rppl-release-prep",
    }
    if token:
        headers["Authorization"] = "Bearer %s" % token
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        return error.code, None
    except (urllib.error.URLError, OSError, ValueError):
        return 0, None


def fetch_release(repo: str, tag: str, token: Optional[str], retries: int, delay: float) -> Optional[Dict[str, Any]]:
    """Return the GitHub release for tag, waiting for it to appear. None if unavailable."""
    url = "https://api.github.com/repos/%s/releases/tags/%s" % (repo, tag)
    for attempt in range(1, retries + 1):
        status, payload = http_get_json(url, token)
        if status == 200 and isinstance(payload, dict):
            return payload
        if status in (401, 403):
            annotate("warning", "GitHub API refused the token (HTTP %d). Token expired or missing Contents: read?" % status)
            return None
        if status == 404 and not token:
            annotate("warning", "Release lookup got 404 without a token. The repo is private: set RPPL_GITHUB_TOKEN.")
            return None
        if attempt < retries:
            time.sleep(delay)
    annotate("warning", "No GitHub release found for tag %s." % tag)
    return None


def pick_tag(candidates: list) -> str:
    """One tag when several release tags share a commit: the final one (no suffix), else the last by name."""
    final = [name for name in candidates if parse_tag(name)[1] is None]
    return sorted(final or candidates)[-1]


def find_release_tag(repo: str, version: str, commit: str, token: Optional[str], retries: int, delay: float) -> str:
    """The release tag of `version` that points at `commit` (GitHub tags API), waiting for it to appear.

    A branch build has no CI_TAG. The tags API lists the commit an annotated tag points at too.
    Raises ReleaseError when no tag matches or the API cannot be read.
    """
    url = "https://api.github.com/repos/%s/tags?per_page=%d" % (repo, TAGS_PER_PAGE)
    status = 0
    for attempt in range(1, retries + 1):
        candidates = []
        for page in range(1, TAGS_MAX_PAGES + 1):
            status, payload = http_get_json("%s&page=%d" % (url, page), token)
            if status != 200 or not isinstance(payload, list):
                break
            for item in payload:
                name = item.get("name") or ""
                if (item.get("commit") or {}).get("sha", "").lower() != commit or not TAG_RE.fullmatch(name):
                    continue
                if parse_tag(name)[0] == version:
                    candidates.append(name)
            if len(payload) < TAGS_PER_PAGE:
                break
        if candidates:
            return pick_tag(candidates)
        if status in (401, 403):
            break
        if attempt < retries:
            time.sleep(delay)
    if status == 200:
        raise ReleaseError(
            "No release tag for %s points at commit %s. Publish the GitHub release first; "
            "its tag must be on the commit release/%s points at." % (version, commit[:SHORT_SHA_LENGTH], version)
        )
    raise ReleaseError(
        "Could not list tags to find the release for %s (HTTP %d). Token expired or missing Contents: read?"
        % (version, status)
    )


def check_on_main(repo: str, tag: str, token: Optional[str]) -> None:
    """Raise ReleaseError when the tagged commit is not in main's history. Skips if unreachable."""
    url = "https://api.github.com/repos/%s/compare/main...%s" % (repo, tag)
    status, payload = http_get_json(url, token)
    if status != 200 or not isinstance(payload, dict):
        annotate("warning", "Could not verify the tag is on main (HTTP %d); continuing." % status)
        return
    compare_status = payload.get("status")
    if compare_status not in ("identical", "behind"):
        raise ReleaseError(
            "Tag %s is not on main (compare status: %s). Release from main only." % (tag, compare_status)
        )


def fallback_notes(root: Path, tag: str) -> str:
    """Never ship an empty What to Test: tag plus recent commit subjects (best effort)."""
    lines = ["Rppl %s" % tag]
    try:
        subprocess.run(
            ["git", "fetch", "--quiet", "--deepen", str(FALLBACK_COMMITS)],
            cwd=str(root), check=False, capture_output=True, timeout=60,
        )
        log = subprocess.run(
            ["git", "log", "-%d" % FALLBACK_COMMITS, "--pretty=format:- %s"],
            cwd=str(root), check=False, capture_output=True, text=True, timeout=30,
        )
        if log.returncode == 0 and log.stdout.strip():
            lines += ["", "Recent changes:", log.stdout.strip()]
    except (OSError, subprocess.SubprocessError):
        pass
    return "\n".join(lines)


def load_release(repo: str, tag: str, token: Optional[str], retries: int, delay: float) -> Optional[Dict[str, Any]]:
    fixture = os.environ.get("RPPL_RELEASE_JSON")
    if fixture:
        return json.loads(Path(fixture).read_text(encoding="utf-8"))
    return fetch_release(repo, tag, token, retries, delay)


def write_summary(title: str, notes: str) -> None:
    print("----- %s -----\n%s\n----- end -----" % (title, notes), flush=True)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("### %s\n\n```text\n%s\n```\n" % (title, notes))


def run(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    tag = args.tag
    repo = os.environ.get("RPPL_GITHUB_REPO") or os.environ.get("GITHUB_REPOSITORY") or DEFAULT_REPO
    token = os.environ.get("RPPL_GITHUB_TOKEN") or os.environ.get("GITHUB_TOKEN")
    offline = bool(os.environ.get("RPPL_RELEASE_JSON"))
    retries = 1 if args.check_only or args.release_branch else int(os.environ.get("RPPL_RELEASE_RETRIES", "6"))
    delay = float(os.environ.get("RPPL_RELEASE_RETRY_DELAY", "10"))

    if not tag and args.branch:
        branch_version = parse_release_branch(args.branch)
        commit = commit_sha(root)
        if not commit:
            raise ReleaseError("Could not determine the commit being built, so no release tag can be found.")
        tag = find_release_tag(repo, branch_version, commit, token, retries, delay)
        print("Branch %s at %s -> release tag %s" % (args.branch, commit[:SHORT_SHA_LENGTH], tag))

    version, suffix = parse_tag(tag)
    print("Release tag %s -> marketing version %s%s" % (tag, version, " (suffix %s)" % suffix if suffix else ""))

    if not offline:
        check_on_main(repo, tag, token)

    if args.release_branch:
        branch = release_branch(version)
        print("Release branch for %s: %s" % (tag, branch))
        output = os.environ.get("GITHUB_OUTPUT")
        if output:
            with open(output, "a", encoding="utf-8") as handle:
                handle.write("branch=%s\n" % branch)
        return

    release = load_release(repo, tag, token, retries, delay)
    body = markdown_to_plain((release or {}).get("body") or "")

    if args.check_only:
        if not body:
            raise ReleaseError(
                "Release %s has no description. Testers would see the commit-list fallback. "
                "Edit the release, then Rebuild in Xcode Cloud." % tag
            )
        write_summary("What to Test preview (%d/%d chars)" % (len(body), NOTES_LIMIT), truncate(body))
        return

    notes = truncate(body or fallback_notes(root, tag))

    pbxproj = root / PBXPROJ
    text, count = bump_marketing_version(pbxproj.read_text(encoding="utf-8"), version)
    pbxproj.write_text(text, encoding="utf-8")
    print("Set MARKETING_VERSION = %s in %d build configurations." % (version, count))

    stamps = {
        "RpplBuildDate": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
        "RpplReleaseTag": release_label(tag),
    }
    commit = short_commit(root)
    if commit:
        stamps["RpplGitCommit"] = commit
    else:
        annotate("warning", "Could not determine the commit SHA; About will not show it.")
    plist = root / APP_INFO_PLIST
    text = plist.read_text(encoding="utf-8")
    for key, value in stamps.items():
        text, stamped = stamp_plist_string(text, key, value)
        if stamped:
            print("Set %s = %s." % (key, value))
        else:
            annotate("warning", "%s not found in Info.plist; not stamped." % key)
    plist.write_text(text, encoding="utf-8")

    notes_path = root / "TestFlight" / ("WhatToTest.%s.txt" % NOTES_LOCALE)
    notes_path.parent.mkdir(parents=True, exist_ok=True)
    notes_path.write_text(notes + "\n", encoding="utf-8")
    write_summary("What to Test (%d/%d chars) -> %s" % (len(notes), NOTES_LIMIT, notes_path.name), notes)


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tag", default=os.environ.get("CI_TAG", ""), help="release tag (default: $CI_TAG)")
    parser.add_argument(
        "--branch", default=os.environ.get("CI_BRANCH", ""),
        help="release/X.Y.Z branch to find the tag for when there is no tag (default: $CI_BRANCH)",
    )
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[2]), help="repository root")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check-only", action="store_true", help="validate and preview, write nothing")
    modes.add_argument(
        "--release-branch", action="store_true",
        help="validate the tag and report the release/X.Y.Z branch to push, write nothing",
    )
    args = parser.parse_args(argv)
    try:
        run(args)
    except (ReleaseError, OSError, ValueError) as error:
        annotate("error", str(error))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
