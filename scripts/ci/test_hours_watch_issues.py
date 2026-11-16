"""Tests for hours_watch_issues.py. Run from the repo root:

    python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hours_watch_issues as hwi  # noqa: E402

FIRED = {"id": "a-park", "url": "https://a.example/hours", "status": "markers",
         "markers": ["`openingstijden 2026` missing from the page"]}
CHANGED = {"id": "b-park", "url": "https://b.example", "status": "ok", "markers": [], "hash_changed": True}
DOWN = {"id": "c-park", "url": "https://c.example", "status": "unreachable", "detail": "HTTP 404"}


class HoursWatchIssuesTests(unittest.TestCase):
    def test_only_fired_markers_get_issues(self):
        self.assertEqual(hwi.fired_parks([FIRED, CHANGED, DOWN]), [FIRED])

    def test_signature_ignores_order(self):
        self.assertEqual(hwi.signature(["a", "b"]), hwi.signature(["b", "a"]))
        self.assertNotEqual(hwi.signature(["a"]), hwi.signature(["a", "b"]))

    def test_new_park_creates(self):
        self.assertEqual([a for a, _, _ in hwi.plan([FIRED], {})], ["create"])

    def test_same_markers_skip(self):
        body = hwi.issue_body(FIRED, "A Park", None, "2026-11-16")
        issue = {"number": 7, "texts": [body]}
        self.assertEqual([a for a, _, _ in hwi.plan([FIRED], {hwi.title("a-park"): issue})], ["skip"])

    def test_changed_markers_comment_then_skip(self):
        body = hwi.issue_body(FIRED, "A Park", None, "2026-11-16")
        more = {**FIRED, "markers": FIRED["markers"] + ["`gesloten` now on the page"]}
        issue = {"number": 7, "texts": [body]}
        self.assertEqual([a for a, _, _ in hwi.plan([more], {hwi.title("a-park"): issue})], ["comment"])
        issue["texts"].append(hwi.comment_body(more, None, "2026-11-23"))
        self.assertEqual([a for a, _, _ in hwi.plan([more], {hwi.title("a-park"): issue})], ["skip"])

    def test_body_mentions_the_essentials(self):
        body = hwi.issue_body(FIRED, "A Park", "https://run", "2026-11-16")
        for text in ("A Park", "a-park", "https://a.example/hours", "missing from the page",
                     "2026-11-16", "https://run", hwi.SKILL_PATH):
            self.assertIn(text, body)


if __name__ == "__main__":
    unittest.main()
