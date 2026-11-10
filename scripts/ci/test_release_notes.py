"""Tests for release_notes.py. Run from the repo root:

    python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v

No network and no git: filtering, prompt building and validation are pure functions.
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release_notes as rn  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class FilterTests(unittest.TestCase):
    def test_parse_change(self):
        self.assertEqual(rn.parse_change("watch(feat): Water Lock reminder (#12)"),
                         ("watch", "feat", "Water Lock reminder"))
        self.assertEqual(rn.parse_change("Fix something"), ("", "", "Fix something"))

    def test_keeps_features_and_fixes(self):
        self.assertTrue(rn.is_candidate("phone(feat): Statistics tab (#636)"))
        self.assertTrue(rn.is_candidate("core(fix): Count laps at the dock (#1)"))

    def test_drops_technical_work(self):
        for subject in ("ci(chore): Cache builds (#2)", "repo(feat): Park the ML work (#3)",
                        "docs(docs): Explain release (#4)", "core(refactor): Extract hold logic (#5)",
                        "phone(test): More UI tests (#6)", "phone(chore): Bump deps (#7)"):
            self.assertFalse(rn.is_candidate(subject), subject)

    def test_unknown_format_stays_for_the_model(self):
        self.assertTrue(rn.is_candidate("Add Statistics tab"))


class PromptTests(unittest.TestCase):
    def test_prompt_has_titles_without_pr_numbers(self):
        prompt = rn.build_user_prompt("2026.11.1", [("phone(feat): Statistics tab (#636)", "Shows totals.")])
        self.assertIn("2026.11.1", prompt)
        self.assertIn("phone(feat): Statistics tab", prompt)
        self.assertNotIn("#636", prompt)
        self.assertIn("Shows totals.", prompt)

    def test_tool_requires_every_locale(self):
        schema = rn.notes_tool()["input_schema"]["properties"]["notes"]
        self.assertEqual(sorted(schema["required"]), sorted(rn.LOCALES))


class ValidationTests(unittest.TestCase):
    def texts(self, text="- Something new"):
        return {locale: text for locale in rn.LOCALES}

    def test_ok(self):
        self.assertEqual(rn.validate_notes(self.texts("  - Hi \r\n- Yo ")), self.texts("- Hi \n- Yo"))

    def test_missing_locale(self):
        notes = self.texts()
        del notes["nl-NL"]
        with self.assertRaises(ValueError):
            rn.validate_notes(notes)

    def test_too_long(self):
        with self.assertRaises(ValueError):
            rn.validate_notes(self.texts("x" * (rn.WHATS_NEW_LIMIT + 1)))


class LocaleTests(unittest.TestCase):
    def test_match_locale(self):
        self.assertEqual(rn.match_locale(["en-US", "nl"], "nl-NL"), "nl")
        self.assertEqual(rn.match_locale(["en-US", "nl-NL"], "nl-NL"), "nl-NL")
        self.assertIsNone(rn.match_locale(["en-US"], "de-DE"))

    def test_every_app_language_has_a_locale(self):
        with open(os.path.join(ROOT, "Rppl", "Localizable.xcstrings"), encoding="utf-8") as handle:
            catalog = json.load(handle)
        languages = {lang for entry in catalog["strings"].values() for lang in entry.get("localizations", {})}
        covered = {locale.split("-")[0] for locale in rn.LOCALES}
        self.assertEqual(languages - covered, set(), "add the missing language to LOCALES in release_notes.py")


if __name__ == "__main__":
    unittest.main()
