"""Pure helpers of the runner: JUnit and orphan parsing, pins, version parsing, warnings policy, process timeout."""

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import check, cli, common, gdunit, pins

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


# Excerpt of a real GdUnit4 6.2.1 console log (tools/out/logs/test.log, 2026-09-29) from two suites that leaked a
# Node on purpose: one in a test body, one in before(). Colour codes kept; blank and repeated lines dropped.
E = "\x1b"
ORPHAN_LOG = "\n".join(
    [
        f"{E}[38;2;0;206;209mRun Test Suite: {E}[0m{E}[38;2;250;235;215mres://tests/unit/leak_probe_test.gd{E}[0m",
        f"  {E}[38;2;250;235;215mres://tests/unit/leak_probe_test.gd{E}[0m{E}[38;2;128;128;128m > {E}[0m"
        f"{E}[38;2;250;235;215mtest_clean{E}[0m{E}[38;2;34;139;34m PASSED{E}[0m{E}[38;2;100;149;237m 4ms{E}[0m",
        f"  {E}[38;2;250;235;215mres://tests/unit/leak_probe_test.gd{E}[0m{E}[38;2;128;128;128m > {E}[0m"
        f"{E}[38;2;250;235;215mtest_leaks_a_node{E}[0m{E}[38;2;34;139;34m PASSED{E}[0m{E}[38;2;100;149;237m 3ms{E}[0m",
        f"  {E}[38;2;0;206;209m{E}[1m{E}[4mReport:{E}[0m",
        f"  {E}[38;2;128;128;128m{E}[38;2;184;134;11mWARNING:{E}[0m Detected {E}[38;2;30;144;255m1{E}[0m"
        " possible orphan nodes.",
        f"\t{E}[38;2;184;134;11m⚠️No details available. Run tests in debug mode to collect details.{E}[0m",
        f"{E}[38;2;30;144;255mStatistics:{E}[0m{E}[38;2;128;128;128m 2 test cases | 0 errors | 0 failures | 0 flaky"
        f" | 0 skipped | 1 orphans |{E}[0m{E}[38;2;34;139;34m PASSED{E}[0m",
        f"{E}[38;2;0;206;209mRun Test Suite: {E}[0m{E}[38;2;250;235;215mres://tests/unit/leak_hook_probe_test.gd{E}[0m",
        f"  {E}[38;2;250;235;215mres://tests/unit/leak_hook_probe_test.gd{E}[0m{E}[38;2;128;128;128m > {E}[0m"
        f"{E}[38;2;250;235;215mtest_nothing{E}[0m{E}[38;2;34;139;34m PASSED{E}[0m{E}[38;2;100;149;237m 3ms{E}[0m",
        f"  {E}[38;2;250;235;215mleak_hook_probe_test{E}[0m{E}[38;2;128;128;128m > {E}[0m"
        f"{E}[38;2;250;235;215mfinalize(){E}[0m  {E}[38;2;0;206;209m{E}[1m{E}[4mReport:{E}[0m",
        f"  {E}[38;2;128;128;128m{E}[38;2;184;134;11mWARNING:{E}[0m Detected {E}[38;2;30;144;255m1{E}[0m"
        " possible orphan nodes.",
        f"{E}[38;2;218;165;32mExit code: 101{E}[0m",
    ]
)


class OrphanTest(unittest.TestCase):
    def test_names_the_leaking_test_and_suite_hook(self) -> None:
        self.assertEqual(
            gdunit.parse_orphans(ORPHAN_LOG),
            [
                "res://tests/unit/leak_probe_test.gd > test_leaks_a_node: 1 orphan node(s)",
                "res://tests/unit/leak_hook_probe_test.gd > before()/after(): 1 orphan node(s)",
            ],
        )

    def test_clean_log_has_no_orphans(self) -> None:
        clean = "\n".join(line for line in ORPHAN_LOG.splitlines() if "orphan nodes" not in line)
        self.assertEqual(gdunit.parse_orphans(clean), [])


class PinsTest(unittest.TestCase):
    def test_linux_checksum_is_a_sha512(self) -> None:
        self.assertRegex(pins.GODOT_LINUX_SHA512, r"^[0-9a-f]{128}$")
        self.assertTrue(pins.GODOT_LINUX_URL.endswith(f"/{pins.GODOT}-stable/{pins.GODOT_LINUX_ZIP}"))

    def test_pins_get_prints_one_value(self) -> None:
        # CI reads the checksum this way: tools/run.sh pins --get godot_linux_sha512
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = cli.main(["pins", "--get", "godot_linux_sha512"])
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue().strip(), pins.GODOT_LINUX_SHA512)


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
