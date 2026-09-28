"""Pure helpers of the runner: JUnit parsing, version parsing, warnings policy, process timeout."""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import check, common, gdunit

JUNIT_FAIL = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites><testsuite name="s" tests="2" failures="1">
<testcase name="test_ok" classname="tests.unit.test_x"/>
<testcase name="test_bad" classname="tests.unit.test_x">
<failure message="Expecting: '3' but was '2'" type="FAILURE">line 7</failure></testcase>
</testsuite></testsuites>
"""


class JUnitTest(unittest.TestCase):
    def test_failures_are_counted_even_if_console_says_passed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "results.xml"
            path.write_text(JUNIT_FAIL, encoding="utf-8")
            result = gdunit.parse_junit(path)
        self.assertEqual(result.tests, 2)
        self.assertEqual(len(result.failures), 1)
        self.assertIn("test_bad", result.failures[0])
        self.assertIn("Expecting: '3'", result.failures[0])


class VersionTest(unittest.TestCase):
    def test_parses_first_dotted_number(self) -> None:
        self.assertEqual(common.version_tuple("gh version 2.101.0 (2026-09-15)"), (2, 101, 0))
        self.assertEqual(common.version_tuple("2.1.284 (Claude Code)"), (2, 1, 284))
        self.assertEqual(common.version_tuple("no version"), ())


class WarningsPolicyTest(unittest.TestCase):
    def policy_for(self, text: str) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "project.godot").write_text(text, encoding="utf-8")
            with mock.patch.object(check, "ROOT", Path(tmp)):
                return check.warnings_policy()

    def test_all_required_at_error_passes(self) -> None:
        lines = "\n".join(f"gdscript/warnings/{name}=2" for name in check.REQUIRED_WARNINGS)
        self.assertEqual(self.policy_for(f"config_version=5\n\n[debug]\n\n{lines}\n"), [])

    def test_lowered_warning_fails(self) -> None:
        lines = "\n".join(f"gdscript/warnings/{name}=2" for name in check.REQUIRED_WARNINGS[1:])
        text = f"config_version=5\n\n[debug]\n\ngdscript/warnings/untyped_declaration=1\n{lines}\n"
        problems = self.policy_for(text)
        self.assertEqual(len(problems), 1)
        self.assertIn("untyped_declaration is 1", problems[0])


class ProcessTest(unittest.TestCase):
    def test_timeout_kills_and_reports(self) -> None:
        res = common.run([sys.executable, "-c", "import time; time.sleep(30)"], timeout=1)
        self.assertTrue(res.timed_out)
        self.assertLess(res.seconds, 20)

    def test_output_is_captured(self) -> None:
        # Godot writes UTF-8 (localized editor output), so the runner decodes UTF-8.
        child = "import sys; sys.stdout.buffer.write('h\\u00e9llo\\n'.encode('utf-8'))"
        res = common.run([sys.executable, "-c", child], timeout=30)
        self.assertEqual(res.rc, 0)
        self.assertIn("héllo", res.out)


if __name__ == "__main__":
    unittest.main()
