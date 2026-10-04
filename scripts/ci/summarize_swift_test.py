#!/usr/bin/env python3
"""Turn `swift test` output (Swift Testing) into a Markdown summary for a PR.

Used by .github/workflows/core-tests.yml: the test job keeps the raw log as an artifact and
the report job feeds it here, then appends the result to the job summary and a sticky PR comment.

    summarize_swift_test.py LOG [--sha SHA] [--run-url URL]

Prints Markdown on stdout. Always exits 0 (a test failure is reported, not raised here); the
test job's own status carries pass/fail. A missing or empty log is reported as "no results".
"""

import argparse
import re
import sys
from pathlib import Path

MARKER = "<!-- core-tests-summary -->"
MAX_ROWS = 30
MAX_MESSAGE = 200

RESULT = re.compile(
    r"^[✔✘] Test run with (?P<tests>\d+) tests? in (?P<suites>\d+) suites? "
    r"(?P<outcome>passed|failed) after (?P<seconds>[\d.]+) seconds"
    r"(?: with (?P<issues>\d+) issues?)?"
)
# `✘ Test name() recorded an issue at File.swift:12:5: message`
# `✘ Test name(x:) recorded an issue with 1 argument x → "a" at File.swift:12:5: message`
ISSUE = re.compile(
    r"^✘ Test (?P<name>.+?) recorded an issue(?: with \d+ arguments? (?P<args>.*?))?"
    r" at (?P<file>[^\s:]+):(?P<line>\d+):\d+: (?P<message>.*)$"
)
# `✘ Test name() failed after 0.1 seconds with 2 issues.` (parameterized: `… with 6 test cases failed after …`)
FAILED_TEST = re.compile(r"^✘ Test (?P<name>.+?) (?:with \d+ test cases? )?failed after ")
BUILD_ERROR = re.compile(r"^(?P<where>\S+?:\d+(?::\d+)?): error: (?P<message>.*)$")
GENERIC_MESSAGE = "Issue recorded"


def parse(lines):
    """Return (result, failed, issues, build_errors) from the log lines."""
    result = None
    failed = []  # test names, first-seen order
    issues = {}  # test name -> list of (location, message)
    build_errors = []
    last_issue = None
    for raw in lines:
        line = raw.rstrip("\n")
        if match := RESULT.match(line):
            result = match.groupdict()
            last_issue = None
        elif match := ISSUE.match(line):
            where = f"{match['file']}:{match['line']}"
            message = match["message"]
            if match["args"]:
                message = f"[{match['args']}] {message}"
            entry = [where, message]
            issues.setdefault(match["name"], []).append(entry)
            last_issue = entry
        elif match := FAILED_TEST.match(line):
            last_issue = None
            if match["name"] not in failed:
                failed.append(match["name"])
        elif line.startswith("↳ ") and last_issue is not None:
            # Detail line under `Issue.record(...)`: the useful text is here, not in the headline.
            if GENERIC_MESSAGE in last_issue[1]:
                last_issue[1] = last_issue[1].replace(GENERIC_MESSAGE, line[2:].strip())
            last_issue = None
        elif match := BUILD_ERROR.match(line):
            last_issue = None
            error = f"{match['where']}: {match['message']}"
            if error not in build_errors:
                build_errors.append(error)
        else:
            last_issue = None
    # A test can record issues and (rarely) miss its own `failed after` line in the output.
    for name in issues:
        if name not in failed:
            failed.append(name)
    return result, failed, issues, build_errors


def cell(text):
    """Make text safe for a one-line Markdown table cell."""
    text = " ".join(text.split())
    if len(text) > MAX_MESSAGE:
        text = text[: MAX_MESSAGE - 1] + "…"
    return text.replace("|", "\\|").replace("`", "'")


def footer(result, sha, run_url):
    parts = []
    if result:
        parts += [f"{result['suites']} suites", f"{result['seconds']} s"]
    if sha:
        parts.append(f"`{sha[:7]}`")
    if run_url:
        parts.append(f"[run]({run_url})")
    return " · ".join(parts)


def summarize(lines, sha="", run_url=""):
    result, failed, issues, build_errors = parse(lines)
    title = "RpplCore tests (Linux)"
    out = [MARKER]

    if result is None:
        if build_errors:
            out.append(f"### ❌ {title}: build failed")
            out.append("")
            out.append("No tests ran. Compiler errors:")
            out.append("")
            out += [f"- `{cell(error)}`" for error in build_errors[:10]]
            if len(build_errors) > 10:
                out.append(f"- … and {len(build_errors) - 10} more")
        else:
            out.append(f"### ⚠️ {title}: no test results")
            out.append("")
            out.append("The log has no `Test run with …` line (build or runner problem, or the job crashed). See the run log.")
        if footer(None, sha, run_url):
            out += ["", footer(None, sha, run_url)]
        return "\n".join(out) + "\n"

    total = int(result["tests"])
    if result["outcome"] == "passed" and not failed:
        out.append(f"### ✅ {title}: {total} passed")
        out.append("")
        out.append(footer(result, sha, run_url))
        return "\n".join(out) + "\n"

    passed = max(total - len(failed), 0)
    out.append(f"### ❌ {title}: {len(failed)} failed, {passed} passed")
    out.append("")
    count = f"{total} tests"
    if result["issues"]:
        count += f" · {result['issues']} issues"
    out.append(f"{count} · {footer(result, sha, run_url)}")
    out.append("")
    out.append("| Test | Where | Issue |")
    out.append("|---|---|---|")
    rows = 0
    for name in failed:
        entries = issues.get(name) or [["", "(no issue line captured, see the run log)"]]
        for where, message in entries:
            if rows >= MAX_ROWS:
                break
            out.append(f"| `{cell(name)}` | {f'`{cell(where)}`' if where else ''} | {cell(message)} |")
            rows += 1
    total_rows = sum(len(issues.get(name) or [None]) for name in failed)
    if total_rows > rows:
        out.append("")
        out.append(f"… and {total_rows - rows} more issues, see the run log.")
    return "\n".join(out) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("log")
    parser.add_argument("--sha", default="")
    parser.add_argument("--run-url", default="")
    args = parser.parse_args(argv)
    path = Path(args.log)
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines() if path.is_file() else []
    sys.stdout.write(summarize(lines, args.sha, args.run_url))
    return 0


if __name__ == "__main__":
    sys.exit(main())
