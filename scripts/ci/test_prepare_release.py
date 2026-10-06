"""Tests for prepare_release.py. Run from the repo root:

    python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v

No network: GitHub calls are patched or bypassed with RPPL_RELEASE_JSON.
"""

import contextlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prepare_release as pr  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
COMMIT = "abcdef0123456789abcdef0123456789abcdef01"


def tag_item(name, sha):
    """One entry of GitHub's list-tags response."""
    return {"name": name, "commit": {"sha": sha}}


def run_main(argv, env=None):
    """Run pr.main with a clean release env; return (exit code, stdout, stderr)."""
    clean = {
        key: value for key, value in os.environ.items()
        if not key.startswith(("RPPL_", "GITHUB_", "CI_"))
    }
    clean.update(env or {})
    out, err = io.StringIO(), io.StringIO()
    with mock.patch.dict(os.environ, clean, clear=True), \
            contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = pr.main(argv)
    return code, out.getvalue(), err.getvalue()


class ParseTagTests(unittest.TestCase):
    def test_valid_tags(self):
        self.assertEqual(pr.parse_tag("v1.2.3"), ("1.2.3", None))
        self.assertEqual(pr.parse_tag("v10.0.12"), ("10.0.12", None))
        self.assertEqual(pr.parse_tag("v1.2.3-beta.1"), ("1.2.3", "beta.1"))
        self.assertEqual(pr.parse_tag("v1.2.3-rc1"), ("1.2.3", "rc1"))

    def test_valid_tags_without_v_prefix(self):
        self.assertEqual(pr.parse_tag("2026.9.1"), ("2026.9.1", None))
        self.assertEqual(pr.parse_tag("2026.10.0-beta.1"), ("2026.10.0", "beta.1"))
        self.assertEqual(pr.parse_tag("1.2.3"), ("1.2.3", None))

    def test_invalid_tags(self):
        for tag in ("", "1.2", "2026.9", "v1.2", "v1", "vNext", "latest", "v1.2.3.4", "2026.9.1.1",
                    "v1.2.3-", "2026.9.1-", "v1.2.3-$(x)", "v1.2.3 beta", "V1.2.3", "v1.2.3\n", "vv1.2.3"):
            with self.subTest(tag=tag):
                with self.assertRaises(pr.ReleaseError):
                    pr.parse_tag(tag)


class VersionTests(unittest.TestCase):
    def test_bump_replaces_every_occurrence(self):
        text = "a\n\t\t\t\tMARKETING_VERSION = 1.0;\n b\n\t\t\t\tMARKETING_VERSION = 2.5.1;\n"
        new_text, count = pr.bump_marketing_version(text, "1.2.3")
        self.assertEqual(count, 2)
        self.assertEqual(new_text.count("MARKETING_VERSION = 1.2.3;"), 2)
        self.assertNotIn("1.0;", new_text)

    def test_bump_without_setting_fails(self):
        with self.assertRaises(pr.ReleaseError):
            pr.bump_marketing_version("nothing here", "1.2.3")

    def test_real_project_file_matches(self):
        """Guards the regex against pbxproj format changes; iOS and Watch must both be hit."""
        text = (REPO_ROOT / pr.PBXPROJ).read_text(encoding="utf-8")
        new_text, count = pr.bump_marketing_version(text, "9.8.7")
        self.assertGreaterEqual(count, 4)
        self.assertEqual(new_text.count("MARKETING_VERSION = 9.8.7;"), count)
        self.assertEqual(new_text.count("MARKETING_VERSION"), count)

    def test_stamp_build_date(self):
        plist = "<key>RpplBuildDate</key>\n\t<string>2026-08-23</string>\n"
        new_text, stamped = pr.stamp_build_date(plist, "2026-10-01")
        self.assertTrue(stamped)
        self.assertIn("<string>2026-10-01</string>", new_text)
        _, stamped = pr.stamp_build_date("<dict/>", "2026-10-01")
        self.assertFalse(stamped)

    def test_stamp_plist_string_fills_empty_and_replaces_values(self):
        plist = "<key>RpplGitCommit</key>\n\t<string></string>\n<key>RpplReleaseTag</key>\n\t<string>old</string>\n"
        text, stamped = pr.stamp_plist_string(plist, "RpplGitCommit", "abc1234")
        self.assertTrue(stamped)
        text, stamped = pr.stamp_plist_string(text, "RpplReleaseTag", "2026.10.1-beta.2")
        self.assertTrue(stamped)
        self.assertIn("<string>abc1234</string>", text)
        self.assertIn("<string>2026.10.1-beta.2</string>", text)
        _, stamped = pr.stamp_plist_string(plist, "Missing", "x")
        self.assertFalse(stamped)

    def test_release_label_drops_leading_v(self):
        self.assertEqual(pr.release_label("v2026.10.1-beta.2"), "2026.10.1-beta.2")
        self.assertEqual(pr.release_label("2026.10.1"), "2026.10.1")

    def test_real_info_plist_has_all_stamp_keys(self):
        text = (REPO_ROOT / pr.APP_INFO_PLIST).read_text(encoding="utf-8")
        for key in ("RpplBuildDate", "RpplReleaseTag", "RpplGitCommit"):
            with self.subTest(key=key):
                _, stamped = pr.stamp_plist_string(text, key, "x")
                self.assertTrue(stamped)

    def test_real_info_plist_has_build_date(self):
        text = (REPO_ROOT / pr.APP_INFO_PLIST).read_text(encoding="utf-8")
        _, stamped = pr.stamp_build_date(text, "2026-10-01")
        self.assertTrue(stamped)


class NotesTests(unittest.TestCase):
    def test_markdown_to_plain(self):
        md = (
            "## What's Changed\r\n"
            "* **watch(feat):** Water temp by @duco in https://github.com/x/y/pull/1\r\n"
            "* Fix [the map](https://example.com) with `code`\r\n\r\n\r\n\r\n"
            "---\r\n"
            "_Full_ *changelog*: https://github.com/x/y/compare/v1...v2\r\n"
            "<!-- hidden -->\r\n"
        )
        plain = pr.markdown_to_plain(md)
        self.assertEqual(
            plain,
            "What's Changed\n"
            "- watch(feat): Water temp by @duco in https://github.com/x/y/pull/1\n"
            "- Fix the map with code\n\n"
            "_Full_ changelog: https://github.com/x/y/compare/v1...v2",
        )

    def test_truncate_keeps_short_text(self):
        self.assertEqual(pr.truncate("short"), "short")

    def test_truncate_caps_length(self):
        text = "\n".join("line %04d" % i for i in range(1000))
        out = pr.truncate(text)
        self.assertLessEqual(len(out), pr.NOTES_LIMIT)
        self.assertTrue(out.endswith("…"))

    def test_truncate_without_newlines(self):
        out = pr.truncate("x" * 10000)
        self.assertEqual(len(out), pr.NOTES_LIMIT)


class RunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        (self.tmp / "Rppl.xcodeproj").mkdir()
        (self.tmp / "Rppl").mkdir()
        shutil.copy(REPO_ROOT / pr.PBXPROJ, self.tmp / pr.PBXPROJ)
        shutil.copy(REPO_ROOT / pr.APP_INFO_PLIST, self.tmp / pr.APP_INFO_PLIST)
        # CI stamps the real plist before these tests run; start from unstamped values.
        plist = self.tmp / pr.APP_INFO_PLIST
        plist.write_text(
            re.sub(
                r"(<key>Rppl(?:GitCommit|ReleaseTag)</key>\s*<string>)[^<]*",
                r"\1",
                plist.read_text(),
            )
        )
        self.fixture = self.tmp / "release.json"
        self.fixture.write_text(json.dumps({"body": "## Notes\n* Faster **sets**\n"}))
        self.env = {"RPPL_RELEASE_JSON": str(self.fixture)}
        self.notes = self.tmp / "TestFlight" / "WhatToTest.en-US.txt"

    def test_build_mode_writes_version_notes_and_date(self):
        code, _, _ = run_main(["--tag", "v1.2.3-beta.2", "--root", str(self.tmp)], self.env)
        self.assertEqual(code, 0)
        project = (self.tmp / pr.PBXPROJ).read_text()
        self.assertNotIn("MARKETING_VERSION = 1.0;", project)
        self.assertIn("MARKETING_VERSION = 1.2.3;", project)
        self.assertEqual(self.notes.read_text(), "Notes\n- Faster sets\n")
        self.assertNotIn("2026-08-23", (self.tmp / pr.APP_INFO_PLIST).read_text())

    def test_build_mode_accepts_tag_without_v(self):
        code, _, _ = run_main(["--tag", "2026.9.1", "--root", str(self.tmp)], self.env)
        self.assertEqual(code, 0)
        self.assertIn("MARKETING_VERSION = 2026.9.1;", (self.tmp / pr.PBXPROJ).read_text())

    def test_build_mode_stamps_tag_and_commit(self):
        env = dict(self.env, CI_COMMIT="ABCDEF0123456789ABCDEF0123456789ABCDEF01")
        code, _, _ = run_main(["--tag", "v1.2.3-beta.2", "--root", str(self.tmp)], env)
        self.assertEqual(code, 0)
        plist = (self.tmp / pr.APP_INFO_PLIST).read_text()
        self.assertRegex(plist, r"<key>RpplReleaseTag</key>\s*<string>1\.2\.3-beta\.2</string>")
        self.assertRegex(plist, r"<key>RpplGitCommit</key>\s*<string>abcdef0</string>")

    def test_build_mode_without_a_commit_leaves_it_empty_and_warns(self):
        with mock.patch.object(pr, "short_commit", return_value=None):
            code, _, err = run_main(["--tag", "v1.2.3", "--root", str(self.tmp)], self.env)
        self.assertEqual(code, 0)
        self.assertRegex((self.tmp / pr.APP_INFO_PLIST).read_text(), r"<key>RpplGitCommit</key>\s*<string></string>")
        self.assertIn("commit SHA", err)

    def test_build_mode_reads_tag_from_env(self):
        code, _, _ = run_main(["--root", str(self.tmp)], dict(self.env, CI_TAG="v3.0.0"))
        self.assertEqual(code, 0)
        self.assertIn("MARKETING_VERSION = 3.0.0;", (self.tmp / pr.PBXPROJ).read_text())

    def test_invalid_tag_fails_and_writes_nothing(self):
        before = (self.tmp / pr.PBXPROJ).read_text()
        code, _, err = run_main(["--tag", "vNext", "--root", str(self.tmp)], self.env)
        self.assertEqual(code, 2)
        self.assertIn("not a release tag", err)
        self.assertEqual((self.tmp / pr.PBXPROJ).read_text(), before)
        self.assertFalse(self.notes.exists())

    def test_check_only_writes_nothing(self):
        before = (self.tmp / pr.PBXPROJ).read_text()
        code, out, _ = run_main(["--tag", "v1.2.3", "--root", str(self.tmp), "--check-only"], self.env)
        self.assertEqual(code, 0)
        self.assertIn("Faster sets", out)
        self.assertEqual((self.tmp / pr.PBXPROJ).read_text(), before)
        self.assertFalse(self.notes.exists())

    def test_check_only_fails_on_empty_body(self):
        self.fixture.write_text(json.dumps({"body": "  \n"}))
        code, _, err = run_main(["--tag", "v1.2.3", "--root", str(self.tmp), "--check-only"], self.env)
        self.assertEqual(code, 2)
        self.assertIn("no description", err)

    def test_missing_release_falls_back_to_tag_notes(self):
        env = {"RPPL_RELEASE_RETRIES": "2", "RPPL_RELEASE_RETRY_DELAY": "0"}
        with mock.patch.object(pr, "http_get_json", return_value=(404, None)), \
                mock.patch.object(pr, "fallback_notes", return_value="Rppl v1.2.3\n\n- commit"):
            code, _, err = run_main(["--tag", "v1.2.3", "--root", str(self.tmp)], env)
        self.assertEqual(code, 0)
        self.assertEqual(self.notes.read_text(), "Rppl v1.2.3\n\n- commit\n")
        self.assertIn("warning", err)

    def test_release_body_fetched_with_retry(self):
        env = {"RPPL_RELEASE_RETRIES": "3", "RPPL_RELEASE_RETRY_DELAY": "0", "RPPL_GITHUB_TOKEN": "t"}
        # 1st call is the on-main check, then the release appears on the second attempt.
        responses = [(200, {"status": "identical"}), (404, None), (200, {"body": "Late notes"})]
        with mock.patch.object(pr, "http_get_json", side_effect=responses):
            code, _, _ = run_main(["--tag", "v1.2.3", "--root", str(self.tmp)], env)
        self.assertEqual(code, 0)
        self.assertEqual(self.notes.read_text(), "Late notes\n")

    def test_branch_build_finds_the_tag_at_the_commit(self):
        env = {"RPPL_GITHUB_TOKEN": "t", "RPPL_RELEASE_RETRY_DELAY": "0", "CI_COMMIT": COMMIT}
        # tags list, on-main check, then the release body.
        responses = [
            (200, [tag_item("2026.10.3", "f" * 40), tag_item("v1.2.3-beta.2", COMMIT)]),
            (200, {"status": "identical"}),
            (200, {"body": "Branch notes"}),
        ]
        with mock.patch.object(pr, "http_get_json", side_effect=responses) as get:
            code, out, _ = run_main(["--branch", "release/1.2.3", "--root", str(self.tmp)], env)
        self.assertEqual(code, 0)
        self.assertIn("release tag v1.2.3-beta.2", out)
        self.assertIn("compare/main...v1.2.3-beta.2", get.call_args_list[1][0][0])
        self.assertIn("releases/tags/v1.2.3-beta.2", get.call_args_list[2][0][0])
        self.assertIn("MARKETING_VERSION = 1.2.3;", (self.tmp / pr.PBXPROJ).read_text())
        self.assertEqual(self.notes.read_text(), "Branch notes\n")
        self.assertRegex((self.tmp / pr.APP_INFO_PLIST).read_text(), r"<key>RpplReleaseTag</key>\s*<string>1\.2\.3-beta\.2</string>")

    def test_branch_build_reads_branch_from_env(self):
        env = dict(self.env, CI_BRANCH="release/3.0.0", CI_COMMIT=COMMIT)
        with mock.patch.object(pr, "http_get_json", return_value=(200, [tag_item("3.0.0", COMMIT)])):
            code, _, _ = run_main(["--root", str(self.tmp)], env)
        self.assertEqual(code, 0)
        self.assertIn("MARKETING_VERSION = 3.0.0;", (self.tmp / pr.PBXPROJ).read_text())

    def test_branch_build_without_a_tag_fails_and_writes_nothing(self):
        before = (self.tmp / pr.PBXPROJ).read_text()
        env = {"RPPL_RELEASE_RETRIES": "1", "CI_COMMIT": COMMIT}
        with mock.patch.object(pr, "http_get_json", return_value=(200, [tag_item("1.2.3", "f" * 40)])):
            code, _, err = run_main(["--branch", "release/1.2.3", "--root", str(self.tmp)], env)
        self.assertEqual(code, 2)
        self.assertIn("No release tag", err)
        self.assertEqual((self.tmp / pr.PBXPROJ).read_text(), before)
        self.assertFalse(self.notes.exists())

    def test_branch_build_rejects_other_branches(self):
        for branch in ("main", "release/1.2", "release/1.2.3-beta.1", "feature/release/1.2.3", "release/"):
            with self.subTest(branch=branch):
                code, _, err = run_main(["--branch", branch, "--root", str(self.tmp)], self.env)
                self.assertEqual(code, 2)
                self.assertIn("not a release branch", err)
                self.assertFalse(self.notes.exists())

    def test_release_branch_mode_reports_the_branch_and_writes_nothing(self):
        before = (self.tmp / pr.PBXPROJ).read_text()
        output = self.tmp / "github_output"
        env = dict(self.env, GITHUB_OUTPUT=str(output))
        code, out, _ = run_main(["--tag", "v2026.10.4-beta.1", "--root", str(self.tmp), "--release-branch"], env)
        self.assertEqual(code, 0)
        self.assertIn("release/2026.10.4", out)
        self.assertEqual(output.read_text(), "branch=release/2026.10.4\n")
        self.assertEqual((self.tmp / pr.PBXPROJ).read_text(), before)
        self.assertFalse(self.notes.exists())

    def test_release_branch_mode_rejects_a_bad_tag(self):
        code, _, err = run_main(["--tag", "latest", "--root", str(self.tmp), "--release-branch"], self.env)
        self.assertEqual(code, 2)
        self.assertIn("not a release tag", err)

    def test_release_branch_mode_stops_on_a_tag_off_main(self):
        with mock.patch.object(pr, "http_get_json", return_value=(200, {"status": "diverged"})):
            code, _, err = run_main(["--tag", "v1.2.3", "--root", str(self.tmp), "--release-branch"])
        self.assertEqual(code, 2)
        self.assertIn("not on main", err)


class ReleaseBranchTests(unittest.TestCase):
    def test_release_branch(self):
        self.assertEqual(pr.release_branch("2026.10.4"), "release/2026.10.4")

    def test_parse_release_branch(self):
        self.assertEqual(pr.parse_release_branch("release/2026.10.4"), "2026.10.4")
        self.assertEqual(pr.parse_release_branch("release/1.0.0"), "1.0.0")

    def test_parse_release_branch_rejects_everything_else(self):
        for branch in ("", "main", "release", "release/", "release/1.2", "release/1.2.3.4", "release/v1.2.3",
                       "release/1.2.3-beta.1", "release/1.2.3/x", "Release/1.2.3", "feature/release/1.2.3"):
            with self.subTest(branch=branch):
                with self.assertRaises(pr.ReleaseError):
                    pr.parse_release_branch(branch)


class FindReleaseTagTests(unittest.TestCase):
    def find(self, responses, retries=1, version="1.2.3", commit=COMMIT):
        with mock.patch.object(pr, "http_get_json", side_effect=responses) as get, \
                mock.patch.object(pr.time, "sleep"):
            result = pr.find_release_tag("o/r", version, commit, "t", retries, 0)
        return result, get

    def test_matches_version_and_commit(self):
        tags = [
            tag_item("1.2.3-beta.1", "e" * 40),
            tag_item("1.2.4-beta.1", COMMIT),  # right commit, other version
            tag_item("v1.2.3-beta.2", COMMIT),
            tag_item("latest", COMMIT),  # not a release tag
        ]
        result, _ = self.find([(200, tags)])
        self.assertEqual(result, "v1.2.3-beta.2")

    def test_sha_comparison_ignores_case(self):
        result, _ = self.find([(200, [tag_item("1.2.3", COMMIT.upper())])])
        self.assertEqual(result, "1.2.3")

    def test_prefers_the_final_tag_then_the_last_name(self):
        both = [tag_item("1.2.3-rc.1", COMMIT), tag_item("1.2.3", COMMIT), tag_item("1.2.3-beta.1", COMMIT)]
        self.assertEqual(self.find([(200, both)])[0], "1.2.3")
        betas = [tag_item("1.2.3-beta.1", COMMIT), tag_item("1.2.3-beta.2", COMMIT)]
        self.assertEqual(self.find([(200, betas)])[0], "1.2.3-beta.2")

    def test_follows_pages(self):
        full = [tag_item("0.0.%d" % n, "e" * 40) for n in range(pr.TAGS_PER_PAGE)]
        result, get = self.find([(200, full), (200, [tag_item("1.2.3-beta.1", COMMIT)])])
        self.assertEqual(result, "1.2.3-beta.1")
        self.assertEqual(get.call_count, 2)
        self.assertIn("page=2", get.call_args_list[1][0][0])

    def test_waits_for_the_tag_to_appear(self):
        result, get = self.find([(200, []), (200, [tag_item("1.2.3", COMMIT)])], retries=3)
        self.assertEqual(result, "1.2.3")
        self.assertEqual(get.call_count, 2)

    def test_no_match_names_the_commit(self):
        with self.assertRaisesRegex(pr.ReleaseError, "No release tag for 1.2.3 points at commit abcdef0"):
            self.find([(200, [tag_item("1.2.3", "e" * 40)])])

    def test_api_failure_is_an_error_not_a_missing_tag(self):
        with self.assertRaisesRegex(pr.ReleaseError, "HTTP 401"):
            self.find([(401, None)], retries=5)
        with self.assertRaisesRegex(pr.ReleaseError, "HTTP 0"):
            self.find([(0, None)])


class ShortCommitTests(unittest.TestCase):
    def commit(self, env, git_stdout=None, git_code=0):
        """short_commit with a controlled environment and a fake `git rev-parse HEAD`."""
        fake = mock.Mock(stdout=git_stdout or "", returncode=git_code)
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(pr.subprocess, "run", return_value=fake):
            return pr.short_commit(Path("."))

    def test_ci_commit_is_shortened_and_lowercased(self):
        self.assertEqual(self.commit({"CI_COMMIT": "ABCDEF0123456789ABCDEF0123456789ABCDEF01"}), "abcdef0")

    def test_falls_back_to_git_head(self):
        self.assertEqual(self.commit({}, git_stdout="1234567890abcdef\n"), "1234567")

    def test_garbage_is_ignored(self):
        self.assertIsNone(self.commit({"CI_COMMIT": "not-a-sha"}))
        self.assertIsNone(self.commit({}, git_stdout="fatal: not a git repository\n", git_code=128))
        self.assertIsNone(self.commit({}, git_stdout=""))


class OnMainTests(unittest.TestCase):
    def test_accepts_identical_and_behind(self):
        for status in ("identical", "behind"):
            with self.subTest(status=status), \
                    mock.patch.object(pr, "http_get_json", return_value=(200, {"status": status})):
                pr.check_on_main("o/r", "v1.0.0", "t")

    def test_rejects_ahead_and_diverged(self):
        for status in ("ahead", "diverged"):
            with self.subTest(status=status), \
                    mock.patch.object(pr, "http_get_json", return_value=(200, {"status": status})):
                with self.assertRaises(pr.ReleaseError):
                    pr.check_on_main("o/r", "v1.0.0", "t")

    def test_unreachable_api_is_only_a_warning(self):
        with mock.patch.object(pr, "http_get_json", return_value=(0, None)):
            pr.check_on_main("o/r", "v1.0.0", None)

    def test_token_rejected_stops_retrying(self):
        with mock.patch.object(pr, "http_get_json", return_value=(401, None)) as get, \
                mock.patch.object(pr.time, "sleep") as sleep:
            self.assertIsNone(pr.fetch_release("o/r", "v1.0.0", "bad", retries=5, delay=10))
        self.assertEqual(get.call_count, 1)
        sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
