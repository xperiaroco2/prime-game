"""The project check's exit codes (#442): Godot 4.7.2 sometimes dies of an access violation (0xC0000005) while it
shuts down after check_project.gd printed a clean summary. Only that case passes, with a loud warning; a crash before
the summary, a crash after errors, another crash code and a timeout stay red."""

import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import check, common
from runner.common import Failure, Result

WINDOWS_ACCESS_VIOLATION = 3221225477  # 0xC0000005, as Python reports the exit code on Windows
POSIX_SIGSEGV = -11
DLL_INIT_FAILED = 3221225794  # 0xC0000142: Windows could not start the process (#441), not an exit-time crash

WARNINGS = (
    'CHECK warning res://a_test.gd:26: The local variable "ready" is shadowing a signal. (SHADOWED_VARIABLE)\n'
    "CHECK warning res://b_test.gd:41: Integer division. (INTEGER_DIVISION)\n"
)
CLEAN = WARNINGS + "CHECK summary files=612 errors=0 warnings=2\n"
SHUTDOWN = (
    "WARNING: 212 ObjectDB instances were leaked at exit (run with `--verbose` for details).\n"
    "   at: cleanup (core/object/object.cpp:2536)\n"
    "ERROR: 175 resources still in use at exit (run with --verbose for details).\n"
    "   at: clear (core/io/resource.cpp:822)\n"
)
WITH_ERRORS = (
    WARNINGS
    + "CHECK error res://core/x.gd:3: Identifier \"Foo\" not declared in the current scope. [_parse]\n"
    + "CHECK summary files=612 errors=1 warnings=2\n"
)


class ProjectCheckExitTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.logs = Path(tmp.name)

    def run_check(self, rc: int, out: str, *, timed_out: bool = False) -> tuple[bool, str]:
        """project_check over a faked Godot run: (passed, what it printed). Failure propagates."""
        printed = io.StringIO()
        with mock.patch.object(check, "godot", return_value=Result(rc, out, timed_out, 20.0)), \
                mock.patch.object(check, "ensure_out"), mock.patch.object(common, "LOGS", self.logs), \
                mock.patch("sys.stdout", printed):  # fmt: skip
            passed = check.project_check()
        return passed, printed.getvalue()

    def crash_log(self) -> Path:
        return self.logs / f"{check.EXIT_CRASH_LOG}.log"

    def test_a_clean_run_passes_without_a_crash_warning(self) -> None:
        passed, said = self.run_check(0, CLEAN + SHUTDOWN)
        self.assertTrue(passed)
        self.assertIn("  ok    files=612 errors=0 warnings=2", said)
        self.assertNotIn("CRASHED", said)
        self.assertFalse(self.crash_log().exists())

    def test_errors_fail_as_before(self) -> None:
        passed, said = self.run_check(1, WITH_ERRORS + SHUTDOWN)
        self.assertFalse(passed)
        self.assertIn('  FAIL  res://core/x.gd:3: Identifier "Foo" not declared', said)

    def test_an_access_violation_at_exit_after_a_clean_summary_passes_loudly(self) -> None:
        # The evidence of #442: the summary is the last line; the shutdown lines never came.
        passed, said = self.run_check(WINDOWS_ACCESS_VIOLATION, CLEAN)
        self.assertTrue(passed)
        self.assertIn("  ok    files=612 errors=0 warnings=2", said)
        warning = next(line for line in said.splitlines() if "CRASHED" in line)
        self.assertTrue(warning.startswith("  warn  GODOT CRASHED AT EXIT: access violation"), warning)
        self.assertIn("exit 3221225477, 0xC0000005", warning)
        self.assertIn("files=612 errors=0 warnings=2", warning)
        self.assertIn("#442", warning)
        self.assertEqual(self.crash_log().read_text(encoding="utf-8"), CLEAN)

    def test_a_posix_segfault_at_exit_after_a_clean_summary_passes_loudly(self) -> None:
        passed, said = self.run_check(POSIX_SIGSEGV, CLEAN)
        self.assertTrue(passed)
        self.assertIn("GODOT CRASHED AT EXIT: access violation (signal 11)", said)

    def test_an_access_violation_before_the_summary_fails(self) -> None:
        # A crash mid-run: the check never finished, so some files were never loaded.
        with self.assertRaises(Failure) as caught:
            self.run_check(WINDOWS_ACCESS_VIOLATION, WARNINGS)
        self.assertIn("project check crashed (exit 3221225477)", str(caught.exception))
        self.assertFalse(self.crash_log().exists())

    def test_an_access_violation_after_errors_fails(self) -> None:
        with self.assertRaises(Failure) as caught:
            self.run_check(WINDOWS_ACCESS_VIOLATION, WITH_ERRORS)
        self.assertIn("project check crashed (exit 3221225477)", str(caught.exception))
        self.assertFalse(self.crash_log().exists())

    def test_an_access_violation_after_an_error_line_fails_even_with_a_zero_count(self) -> None:
        out = WARNINGS + "CHECK error res://core/x.gd:3: broken [_parse]\nCHECK summary files=612 errors=0 warnings=2\n"
        with self.assertRaises(Failure):
            self.run_check(WINDOWS_ACCESS_VIOLATION, out)

    def test_an_access_violation_with_check_lines_after_the_summary_fails(self) -> None:
        # The summary is check_project.gd's last print: a CHECK line after it means the script had not finished.
        with self.assertRaises(Failure):
            self.run_check(WINDOWS_ACCESS_VIOLATION, CLEAN + "CHECK warning res://c.gd:1: late. (X)\n")

    def test_another_crash_code_after_a_clean_summary_fails(self) -> None:
        for rc in (DLL_INIT_FAILED, 3, -6):
            with self.subTest(rc=rc), self.assertRaises(Failure) as caught:
                self.run_check(rc, CLEAN)
            self.assertIn(f"project check crashed (exit {rc})", str(caught.exception))

    def test_a_timeout_after_a_clean_summary_fails(self) -> None:
        with self.assertRaises(Failure) as caught:
            self.run_check(WINDOWS_ACCESS_VIOLATION, CLEAN, timed_out=True)
        self.assertIn("project check timed out", str(caught.exception))


class CrashedAfterCleanRunTest(unittest.TestCase):
    def test_the_summary_without_an_error_count_is_not_clean(self) -> None:
        res = Result(WINDOWS_ACCESS_VIOLATION, "CHECK summary files=3\n", False, 1.0)
        self.assertIsNone(check.crashed_after_clean_run(res))

    def test_a_normal_exit_is_not_an_exit_crash(self) -> None:
        self.assertIsNone(check.crashed_after_clean_run(Result(0, CLEAN, False, 1.0)))

    def test_the_clean_summary_is_returned(self) -> None:
        res = Result(WINDOWS_ACCESS_VIOLATION, CLEAN, False, 1.0)
        self.assertEqual(check.crashed_after_clean_run(res), "CHECK summary files=612 errors=0 warnings=2")


if __name__ == "__main__":
    unittest.main()
