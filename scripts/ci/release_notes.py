#!/usr/bin/env python3
"""Turn the merged PRs of a final release into human-readable "What's New" texts and put them in App Store Connect.

Called from .github/workflows/release-notes.yml when a final release (X.Y.Z, no -beta) is published.

  1. Collect the squash-merged PRs between the previous final release and the new tag.
  2. Drop what is never user-facing (ci, repo, docs, tests, chores, refactors).
  3. Ask Claude to write short notes in every App Store language, only for new features and bug fixes
     (no debug, ML, tooling or other technical items). One call, one language per key.
  4. Write the texts to the job summary and, when the App Store Connect secrets exist, to the
     "What's New" field of the App Store version X.Y.Z (the version is created when it does not exist).

Without ANTHROPIC_API_KEY the script fails. Without the ASC_* secrets it stops after step 3, so the notes can
be pasted by hand. --dry-run never writes to App Store Connect. Nothing is submitted for review.

Environment: ANTHROPIC_API_KEY, optional RELEASE_NOTES_MODEL; ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (the .p8
contents); GITHUB_TOKEN / GH_TOKEN (gh CLI) and GITHUB_REPOSITORY; PyJWT + cryptography for App Store Connect.

Python 3.9 compatible on purpose, like the other scripts in scripts/ci.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import draft_releases as dr  # noqa: E402

DEFAULT_MODEL = "claude-sonnet-5-5"
ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
ASC_URL = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "nl.dcsbl.rppl"
WHATS_NEW_LIMIT = 4000
BODY_LIMIT = 1500

# App Store Connect locale -> language name for the prompt. Keep in step with the app's languages: the unit test
# fails when a language in Rppl/Localizable.xcstrings has no entry here.
LOCALES = {
    "en-US": "English",
    "nl-NL": "Dutch (Netherlands)",
    "de-DE": "German",
    "fr-FR": "French (Belgium and France)",
}

# Version states in which App Store Connect still accepts new metadata.
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW",
    "INVALID_BINARY",
}

SKIP_TYPES = {"refactor", "test", "docs", "chore"}
SKIP_COMPONENTS = {"ci", "repo", "docs"}
TITLE_RE = re.compile(r"^(?P<component>[a-z]+)\((?P<type>[a-z]+)\):\s*(?P<text>\S.*)$")
PR_RE = re.compile(r"\(#(?P<number>\d+)\)\s*$")

SYSTEM_PROMPT = """You write the "What's New" text of Rppl, a free cable park tracker for wakeboard and waterski \
riders (Apple Watch records, iPhone shows). You get the pull requests merged since the last release.

Write for riders, not developers:
- Only new features and bug fixes a rider can notice. Say what is better for them, in plain words.
- Leave out everything technical or internal: debug tools and debug toggles, experimental features, machine learning \
and detection training, CI, tests, refactors, docs, dependencies, data tooling. Leave out park data additions \
unless they are a rider-facing feature. Never mention pull request numbers, titles or component names.
- Merge related changes into one line. At most 8 lines, ideally 3 to 6. One short sentence each, no emoji, no \
marketing words.
- Format: plain text, one line per item, each starting with "- ". No heading, no version number, no markdown.
- Voice: direct and friendly, in the app's own voice. Keep wakeboard slang in English in every language (session, \
set, lap, riding, cable, dock, rider, Water Lock). Write natural text for each language, do not translate word for \
word. Informal "je" in Dutch, "du" in German, "tu" in French.
- If nothing is rider-facing, write one line saying that this version has small improvements and bug fixes.
- Every text must stay under 3000 characters."""


def parse_change(subject: str) -> Tuple[str, str, str]:
    """(component, type, text) of a PR title; empty component and type when it does not follow the format."""
    text = PR_RE.sub("", subject).strip()
    match = TITLE_RE.match(text)
    if not match:
        return "", "", text
    return match.group("component"), match.group("type"), match.group("text")


def is_candidate(subject: str) -> bool:
    """False for PRs that are never user-facing, by component and type. Unknown formats stay for the model."""
    component, kind, _ = parse_change(subject)
    return component not in SKIP_COMPONENTS and kind not in SKIP_TYPES


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=120).stdout


def tag_subjects(base: Optional[str], tag: str) -> List[str]:
    """First-parent subjects (the squash-merged PR titles) after base up to and including tag."""
    rev = "%s..%s" % (base, tag) if base else tag
    out = run("git", "log", "--first-parent", "--format=%s", rev)
    return [line.strip() for line in out.splitlines() if line.strip()]


def pr_body(repo: str, subject: str) -> str:
    """The PR description for a subject ending in (#N), cut to BODY_LIMIT; empty when unavailable."""
    match = PR_RE.search(subject)
    if not match:
        return ""
    try:
        data = json.loads(run("gh", "api", "repos/%s/pulls/%s" % (repo, match.group("number"))))
    except (subprocess.SubprocessError, ValueError):
        return ""
    body = re.sub(r"<!--.*?-->", "", data.get("body") or "", flags=re.S).strip()
    return body[:BODY_LIMIT]


def build_user_prompt(tag: str, changes: Sequence[Tuple[str, str]]) -> str:
    parts = ["Release %s. Merged pull requests:" % tag]
    for subject, body in changes:
        parts.append("\n### %s" % PR_RE.sub("", subject).strip())
        if body:
            parts.append(body)
    return "\n".join(parts)


def notes_tool() -> dict:
    return {
        "name": "save_release_notes",
        "description": "Save the What's New text for every App Store language.",
        "input_schema": {
            "type": "object",
            "properties": {"notes": {
                "type": "object",
                "description": "App Store Connect locale -> What's New text",
                "properties": {locale: {"type": "string"} for locale in LOCALES},
                "required": list(LOCALES),
            }},
            "required": ["notes"],
        },
    }


def validate_notes(notes: Dict[str, str]) -> Dict[str, str]:
    """The cleaned texts, one per locale. Raises ValueError when a language is missing, empty or too long."""
    cleaned = {}
    for locale in LOCALES:
        text = (notes.get(locale) or "").replace("\r\n", "\n").strip()
        if not text:
            raise ValueError("no text for %s" % locale)
        if len(text) > WHATS_NEW_LIMIT:
            raise ValueError("%s text is %d characters, the limit is %d" % (locale, len(text), WHATS_NEW_LIMIT))
        cleaned[locale] = text
    return cleaned


def http_json(method: str, url: str, headers: Dict[str, str], payload: Optional[dict] = None) -> dict:
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(url, data=data, method=method,
                                     headers=dict(headers, **{"Content-Type": "application/json"}))
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        raise RuntimeError("%s %s failed: HTTP %d %s" % (method, url, error.code, error.read().decode()[:500]))
    return json.loads(raw) if raw else {}


def generate_notes(tag: str, changes: Sequence[Tuple[str, str]], api_key: str, model: str) -> Dict[str, str]:
    payload = {
        "model": model,
        "max_tokens": 4000,
        "system": SYSTEM_PROMPT,
        "tools": [notes_tool()],
        "tool_choice": {"type": "tool", "name": "save_release_notes"},
        "messages": [{"role": "user", "content": build_user_prompt(tag, changes)}],
    }
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01"}
    response = http_json("POST", ANTHROPIC_URL, headers, payload)
    for block in response.get("content", []):
        if block.get("type") == "tool_use":
            return validate_notes(block["input"]["notes"])
    raise RuntimeError("the model returned no release notes")


# --- App Store Connect -------------------------------------------------------------------------------------------


def asc_headers() -> Dict[str, str]:
    import jwt  # PyJWT with the cryptography package; only needed when uploading

    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )
    return {"Authorization": "Bearer " + token}


def asc(method: str, path: str, payload: Optional[dict] = None) -> dict:
    return http_json(method, ASC_URL + path, asc_headers(), payload)


def match_locale(existing: Sequence[str], wanted: str) -> Optional[str]:
    """The locale of an existing localization that is the same language (nl for nl-NL), or None."""
    lowered = {locale.lower(): locale for locale in existing}
    if wanted.lower() in lowered:
        return lowered[wanted.lower()]
    language = wanted.split("-")[0].lower()
    for locale in existing:
        if locale.split("-")[0].lower() == language:
            return locale
    return None


def upload_notes(version: str, notes: Dict[str, str]) -> List[str]:
    """Write the texts to App Store version X.Y.Z. Returns one summary line per locale or problem."""
    lines = []
    apps = asc("GET", "/v1/apps?filter[bundleId]=%s" % BUNDLE_ID)["data"]
    if not apps:
        raise RuntimeError("no app with bundle id %s in App Store Connect" % BUNDLE_ID)
    app_id = apps[0]["id"]

    found = asc("GET", "/v1/apps/%s/appStoreVersions?filter[versionString]=%s&filter[platform]=IOS" % (app_id, version))
    if found["data"]:
        store_version = found["data"][0]
        state = store_version["attributes"].get("appStoreState")
        if state not in EDITABLE_STATES:
            return ["Version %s is in state %s: texts not uploaded, paste them by hand." % (version, state)]
        lines.append("Found App Store version %s (%s)." % (version, state))
    else:
        store_version = asc("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }})["data"]
        lines.append("Created App Store version %s." % version)
    version_id = store_version["id"]

    localizations = asc("GET", "/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % version_id)["data"]
    by_locale = {item["attributes"]["locale"]: item["id"] for item in localizations}
    for locale, text in notes.items():
        existing = match_locale(list(by_locale), locale)
        try:
            if existing:
                asc("PATCH", "/v1/appStoreVersionLocalizations/%s" % by_locale[existing], {"data": {
                    "type": "appStoreVersionLocalizations", "id": by_locale[existing],
                    "attributes": {"whatsNew": text},
                }})
                lines.append("%s: updated (%s)" % (locale, existing))
            else:
                asc("POST", "/v1/appStoreVersionLocalizations", {"data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {"locale": locale, "whatsNew": text},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
                }})
                lines.append("%s: created" % locale)
        except RuntimeError as error:
            # e.g. the first version of an app cannot have What's New text.
            lines.append("%s: not uploaded (%s)" % (locale, error))
    return lines


def render_summary(tag: str, notes: Dict[str, str], upload: Sequence[str]) -> str:
    blocks = ["### What's New for %s\n" % tag]
    blocks += ["**%s**\n\n```\n%s\n```\n" % (locale, text) for locale, text in notes.items()]
    blocks.append("**App Store Connect**\n\n" + "\n".join("- " + line for line in upload) + "\n")
    return "\n".join(blocks)


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--tag", required=True, help="final release tag, X.Y.Z")
    parser.add_argument("--dry-run", action="store_true", help="write the texts, never touch App Store Connect")
    parser.add_argument("--output", help="also write the texts as JSON to this file")
    args = parser.parse_args(argv)
    repo = os.environ.get("GITHUB_REPOSITORY", "DCSBL/rppl")

    parsed = dr.parse_tag(args.tag)
    if parsed is None or parsed[1] is not None:
        print("%s is not a final release tag (X.Y.Z): nothing to do." % args.tag)
        return 0

    finals = [t for t in dr.git_tags() if dr.parse_tag(t) is not None and dr.parse_tag(t)[1] is None  # type: ignore[index]
              and dr.order_key(t) < dr.order_key(args.tag)]
    base = max(finals, key=dr.order_key) if finals else None
    subjects = [s for s in tag_subjects(base, args.tag) if is_candidate(s)]
    print("%d candidate PRs since %s" % (len(subjects), base or "the start"), flush=True)

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        print("ANTHROPIC_API_KEY is not set.", file=sys.stderr)
        return 1
    changes = [(s, pr_body(repo, s)) for s in subjects]
    notes = generate_notes(args.tag, changes, api_key, os.environ.get("RELEASE_NOTES_MODEL", DEFAULT_MODEL))
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            json.dump(notes, handle, ensure_ascii=False, indent=2)

    if args.dry_run:
        upload = ["Dry run: App Store Connect not touched."]
    elif not all(os.environ.get(key) for key in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY")):
        upload = ["ASC_KEY_ID, ASC_ISSUER_ID or ASC_PRIVATE_KEY is not set: paste the texts in App Store Connect by hand."]
    else:
        upload = upload_notes(args.tag, notes)

    text = render_summary(args.tag, notes, upload)
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as handle:
            handle.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
