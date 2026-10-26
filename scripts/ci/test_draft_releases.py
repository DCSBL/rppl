"""Tests for draft_releases.py. Run from the repo root:

    python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v

No network and no git: planning and note rendering are pure functions.
"""

import datetime
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import draft_releases as dr  # noqa: E402

OCT = datetime.datetime(2026, 10, 26, tzinfo=datetime.timezone.utc)


class PlanTests(unittest.TestCase):
    def test_beta_series_in_progress(self):
        plan = dr.plan(["2026.10.6", "2026.10.7-beta.1", "2026.10.7-beta.4"], OCT)
        self.assertEqual(plan["beta"], "2026.10.7-beta.5")
        self.assertEqual(plan["final"], "2026.10.7")
        self.assertEqual(plan["beta_base"], "2026.10.7-beta.4")
        self.assertEqual(plan["final_base"], "2026.10.6")

    def test_publishing_final_drafts_next_version(self):
        plan = dr.plan(["2026.10.7-beta.4", "2026.10.7"], OCT)
        self.assertEqual((plan["beta"], plan["final"]), ("2026.10.8-beta.1", "2026.10.8"))
        self.assertEqual(plan["beta_base"], "2026.10.7")
        self.assertEqual(plan["final_base"], "2026.10.7")

    def test_final_without_betas_and_skipped_versions(self):
        plan = dr.plan(["2026.10.6", "2026.10.8-beta.13", "2026.10.8"], OCT)
        self.assertEqual(plan["final"], "2026.10.9")

    def test_new_month_restarts_counter(self):
        nov = datetime.datetime(2026, 11, 2, tzinfo=datetime.timezone.utc)
        self.assertEqual(dr.plan(["2026.10.8"], nov)["final"], "2026.11.1")

    def test_unfinished_version_from_old_month_keeps_its_number(self):
        nov = datetime.datetime(2026, 11, 2, tzinfo=datetime.timezone.utc)
        self.assertEqual(dr.plan(["2026.10.8-beta.2"], nov)["final"], "2026.10.8")

    def test_no_releases_yet(self):
        plan = dr.plan([], OCT)
        self.assertEqual((plan["beta"], plan["final"]), ("2026.10.1-beta.1", "2026.10.1"))
        self.assertIsNone(plan["beta_base"])
        self.assertIsNone(plan["final_base"])

    def test_duo_and_other_tags_are_ignored(self):
        plan = dr.plan(["2026.10.8", "2026.10.9-duo.1", "v2026.10.9", "2026.10.9-rc.1", "latest"], OCT)
        self.assertEqual(plan["final"], "2026.10.9")
        self.assertEqual(plan["beta_base"], "2026.10.8")

    def test_beta_numbers_sort_numerically(self):
        plan = dr.plan(["2026.10.8-beta.9", "2026.10.8-beta.10", "2026.10.8-beta.2"], OCT)
        self.assertEqual(plan["beta"], "2026.10.8-beta.11")
        self.assertEqual(plan["beta_base"], "2026.10.8-beta.10")


class NotesTests(unittest.TestCase):
    def test_no_changes(self):
        self.assertEqual(dr.render_notes([], "2026.10.7"), "No changes since 2026.10.7.")
        self.assertEqual(dr.render_notes([], None), "No changes yet.")

    def test_groups_by_pr_title_type(self):
        notes = dr.render_notes([
            "phone(fix): Keep map in sidebar (#576)",
            "slang(feat): Add French (#572)",
            "docs(docs): Clarify (#570)",
            "slang: use sessie (#569)",
        ], "2026.10.7")
        self.assertEqual(notes, "\n\n".join([
            "## New\n\n- slang(feat): Add French (#572)",
            "## Fixed\n\n- phone(fix): Keep map in sidebar (#576)",
            "## Under the hood\n\n- docs(docs): Clarify (#570)",
            "## Other\n\n- slang: use sessie (#569)",
        ]))

    def test_long_history_is_capped(self):
        notes = dr.render_notes(["core(feat): x (#%d)" % i for i in range(dr.MAX_ENTRIES + 3)], None)
        self.assertIn("3 older changes not listed.", notes)


if __name__ == "__main__":
    unittest.main()
