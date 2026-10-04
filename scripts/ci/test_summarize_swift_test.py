"""Tests for summarize_swift_test.py. Run from the repo root:

    python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
"""

import contextlib
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import summarize_swift_test as sst  # noqa: E402

PASSED = [
    "◇ Test run started.",
    "✔ Test aFastOne() passed after 0.001 seconds.",
    "✔ Test run with 594 tests in 102 suites passed after 2.064 seconds.",
]

FAILED = [
    '✘ Test slowOne() recorded an issue at DeadlineTests.swift:37:9: Expectation failed: (a → 2.5) < (2 → 2.0)',
    '✘ Test slowOne() failed after 2.9 seconds with 1 issue.',
    '✘ Test param(name:) recorded an issue with 1 argument name → "a|b" at StoreTests.swift:62:9: boom',
    '✘ Test param(name:) with 2 test cases failed after 0.2 seconds with 1 issue.',
    '✘ Test cancelled() recorded an issue at StoreTests.swift:771:25: Issue recorded',
    '↳ Expected CancellationError from cancelled JSONL read',
    '✘ Test cancelled() failed after 0.1 seconds with 1 issue.',
    '✘ Suite "Store" failed after 3 seconds with 2 issues.',
    '✘ Test run with 594 tests in 102 suites failed after 3.840 seconds with 3 issues.',
]


class SummarizeTests(unittest.TestCase):
    def test_all_passed(self):
        text = sst.summarize(PASSED, sha="46bd12455b80", run_url="https://example/run/1")
        self.assertIn(sst.MARKER, text)
        self.assertIn("✅ RpplCore tests (Linux): 594 passed", text)
        self.assertIn("102 suites · 2.064 s · `46bd124` · [run](https://example/run/1)", text)
        self.assertNotIn("|", text)

    def test_failures_list_tests_and_counts(self):
        text = sst.summarize(FAILED)
        self.assertIn("❌ RpplCore tests (Linux): 3 failed, 591 passed", text)
        self.assertIn("594 tests · 3 issues", text)
        self.assertIn("| `slowOne()` | `DeadlineTests.swift:37` | Expectation failed: (a → 2.5) < (2 → 2.0) |", text)
        self.assertEqual(text.count("`slowOne()`"), 1)  # a suite line is not a test row

    def test_parameterized_arguments_and_pipes_are_kept_table_safe(self):
        text = sst.summarize(FAILED)
        self.assertIn("`param(name:)`", text)
        self.assertIn('[name → "a\\|b"] boom', text)

    def test_generic_issue_text_is_replaced_by_the_detail_line(self):
        text = sst.summarize(FAILED)
        self.assertIn("Expected CancellationError from cancelled JSONL read", text)
        self.assertNotIn("Issue recorded", text)

    def test_issues_without_a_failed_line_still_count_as_failed(self):
        lines = [FAILED[0], "✘ Test run with 10 tests in 2 suites failed after 1.0 seconds with 1 issue."]
        self.assertIn("1 failed, 9 passed", sst.summarize(lines))

    def test_rows_are_capped(self):
        lines = [
            f"✘ Test many{i}() recorded an issue at A.swift:{i}:1: nope" for i in range(sst.MAX_ROWS + 5)
        ]
        lines.append("✘ Test run with 100 tests in 3 suites failed after 1.0 seconds with 35 issues.")
        text = sst.summarize(lines)
        self.assertEqual(text.count("| `many"), sst.MAX_ROWS)
        self.assertIn("… and 5 more issues", text)

    def test_build_failure_reports_compiler_errors_once(self):
        lines = [
            "/src/A.swift:1:8: error: no such module 'Compression'",
            "/src/A.swift:1:8: error: no such module 'Compression'",
            "error: fatalError",
        ]
        text = sst.summarize(lines)
        self.assertIn("build failed", text)
        self.assertEqual(text.count("no such module"), 1)

    def test_empty_log_says_no_results(self):
        text = sst.summarize([])
        self.assertIn("no test results", text)
        self.assertIn(sst.MARKER, text)

    def test_missing_log_file_does_not_raise(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(sst.main(["/nonexistent/swift-test.log"]), 0)


if __name__ == "__main__":
    unittest.main()
