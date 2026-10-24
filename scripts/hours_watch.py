#!/usr/bin/env python3
"""Weekly scan of every park's opening hours page (`opening.source_url`).

Usage:
    python3 scripts/hours_watch.py [--state PATH] [--summary PATH] [--only park-id ...]

Informational only: prints a Markdown report (also appended to --summary, e.g.
$GITHUB_STEP_SUMMARY) and never fails the run for a changed or unreachable park.
Per park it reports which markers fired (see ops/hours-watch/markers.yaml) and whether the
page text hash changed since the previous run (kept in --state). Fetching uses plain HTTP
with browser-like headers first and falls back to Playwright when that yields no usable page.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import html
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:
    print("error: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parent.parent
PARKS_DIR = REPO_ROOT / "RpplCore" / "Sources" / "RpplCore" / "Resources" / "Parks"
MARKERS_PATH = REPO_ROOT / "ops" / "hours-watch" / "markers.yaml"

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
    "Version/17.5 Safari/605.1.15 RpplHoursWatch (+https://github.com/DCSBL/rppl)"
)
HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "nl-NL,nl;q=0.9,en;q=0.5",
}
MIN_TEXT_CHARS = 300  # shorter than this: an empty JS shell or a block page, not a usable page
ATTEMPTS = 3
BACKOFF_SECONDS = (0, 20, 90)


def normalize(raw_html: str) -> str:
    """HTML to lowercase, whitespace-collapsed text without scripts, styles and tags."""
    text = re.sub(r"(?is)<(script|style|noscript|svg)\b.*?</\1>", " ", raw_html)
    text = re.sub(r"(?s)<!--.*?-->", " ", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", html.unescape(text)).strip().lower()


def fetch_curl(url: str) -> str:
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read(5_000_000).decode(charset, errors="replace")


def fetch_browser(url: str, selector: str | None) -> str:
    from playwright.sync_api import sync_playwright  # optional dependency

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        try:
            page = browser.new_page(user_agent=USER_AGENT, locale="nl-NL")
            page.goto(url, wait_until="networkidle", timeout=45_000)
            if selector:
                return page.locator(selector).first.inner_html(timeout=10_000)
            return page.content()
        finally:
            browser.close()


def fetch(url: str, entry: dict) -> tuple[str, str]:
    """Return (normalized text, method used). Raises RuntimeError with a reason when both fail."""
    selector = entry.get("selector")
    errors: list[str] = []
    methods = ["browser"] if entry.get("fetch") == "browser" else ["curl", "browser"]
    for method in methods:
        for attempt in range(ATTEMPTS):
            time.sleep(BACKOFF_SECONDS[attempt])
            try:
                raw = fetch_curl(url) if method == "curl" else fetch_browser(url, selector)
            except ImportError:
                errors.append("browser: playwright not installed")
                break
            except urllib.error.HTTPError as error:
                errors.append(f"{method}: HTTP {error.code}")
                if error.code in (401, 403, 404, 410):
                    break  # retrying will not help
            except Exception as error:  # noqa: BLE001 - any network/browser failure is just a reason
                errors.append(f"{method}: {type(error).__name__}")
            else:
                text = normalize(raw)
                if len(text) >= MIN_TEXT_CHARS:
                    return text, method
                errors.append(f"{method}: page too short ({len(text)} chars)")
                break  # a retry will not fill an empty shell; try the next method
    raise RuntimeError("; ".join(dict.fromkeys(errors)) or "no result")


def check_park(park_id: str, url: str, overrides: dict, state: dict, next_year: int) -> dict:
    entry = overrides.get(park_id) or {}
    result: dict = {"id": park_id, "url": url}
    try:
        text, method = fetch(url, entry)
    except RuntimeError as error:
        result.update(status="unreachable", detail=str(error))
        return result

    absent = [str(m).lower() for m in entry.get("absent", [str(next_year)])]
    present = [str(m).lower() for m in entry.get("present", [])]
    fired = [f"`{m}` now on the page" for m in absent if m in text]
    fired += [f"`{m}` missing from the page" for m in present if m not in text]

    digest = hashlib.sha256(text.encode()).hexdigest()[:16]
    previous = state.get(park_id, {}).get("hash")
    result.update(
        status="markers" if fired else "ok",
        method=method,
        markers=fired,
        hash=digest,
        hash_changed=previous is not None and previous != digest,
    )
    return result


def load_urls() -> dict[str, str]:
    urls: dict[str, str] = {}
    for path in sorted(PARKS_DIR.glob("*.yaml")):
        data = yaml.safe_load(path.read_text())
        url = (data.get("opening") or {}).get("source_url")
        if url:
            urls[data["id"]] = url
    return urls


def render(results: list[dict]) -> str:
    lines = [f"# Opening hours watch ({datetime.date.today().isoformat()})", ""]
    sections = [
        ("Markers triggered", [r for r in results if r["status"] == "markers"]),
        ("Page changed, no marker", [r for r in results if r["status"] == "ok" and r["hash_changed"]]),
        ("Unreachable", [r for r in results if r["status"] == "unreachable"]),
    ]
    for title, rows in sections:
        if not rows:
            continue
        lines += [f"## {title}", ""]
        for row in rows:
            lines.append(f"- **{row['id']}** ({row['url']})")
            for marker in row.get("markers", []):
                lines.append(f"  - {marker}")
            if row["status"] == "ok" or row["status"] == "markers":
                if row["hash_changed"]:
                    lines.append("  - page text changed since last run")
            if row["status"] == "unreachable":
                lines.append(f"  - {row['detail']}")
        lines.append("")
    quiet = [r["id"] for r in results if r["status"] == "ok" and not r["hash_changed"]]
    if quiet:
        lines += [f"## Unchanged ({len(quiet)})", "", ", ".join(quiet), ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--state", type=Path, help="JSON file with page hashes from the previous run")
    parser.add_argument("--summary", type=Path, help="append the Markdown report to this file")
    parser.add_argument("--only", nargs="*", default=[], help="limit to these park ids")
    args = parser.parse_args()

    overrides = yaml.safe_load(MARKERS_PATH.read_text()) or {}
    urls = {k: v for k, v in load_urls().items() if not args.only or k in args.only}
    state = json.loads(args.state.read_text()) if args.state and args.state.exists() else {}
    next_year = datetime.date.today().year + 1

    results = [check_park(pid, url, overrides, state, next_year) for pid, url in urls.items()]
    report = render(results)
    print(report)
    if args.summary:
        with args.summary.open("a") as handle:
            handle.write(report + "\n")
    if args.state:
        for row in results:
            if row.get("hash"):
                state[row["id"]] = {"hash": row["hash"], "checked": datetime.date.today().isoformat()}
        args.state.parent.mkdir(parents=True, exist_ok=True)
        args.state.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
