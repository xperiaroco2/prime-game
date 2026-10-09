"""Quiet `lint`, `check` and `wait` (#590, part 1 of #572): a summary on success, a capped excerpt and the log's path on
failure, the exit code and the failing step always shown, `--verbose` for today's whole output."""

import contextlib
import io
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import check, cli, common, lint, verify, wait

GREEN_LINT = [
    "lint",
    "  ok    gdformat (594 files)",
    "  ok    gdlint (594 files)",
    "lint: passed",
]
SCRIPT_WARNING = "  warn  res://client/a.gd:{n}: Integer division. Decimal part will be discarded. (INTEGER_DIVISION)"


def printed(function, *args, **kwargs):  # type: ignore[no-untyped-def]
    """(return value, what it printed) with stdout captured."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        value = function(*args, **kwargs)
    return value, out.getvalue()


class QuietTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        for patch in (
            mock.patch.object(common, "ROOT", self.root),
            mock.patch.object(common, "OUT", self.root / "tools" / "out"),
            mock.patch.object(common, "LOGS", self.root / "tools" / "out" / "logs"),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def body(self, lines: list[str], rc: int):  # type: ignore[no-untyped-def]
        def run() -> int:
            for line in lines:
                common.say(line)
            return rc

        return run

    def log(self, name: str) -> str:
        return (self.root / "tools" / "out" / "logs" / f"{name}-output.log").read_text(encoding="utf-8")

    def test_a_green_run_prints_its_summary_and_the_log_path_under_the_cap(self) -> None:
        rc, out = printed(common.quiet, "lint", self.body(GREEN_LINT, 0))
        self.assertEqual(rc, 0)
        self.assertEqual(out.splitlines()[: len(GREEN_LINT)], GREEN_LINT)
        self.assertIn("full output: tools/out/logs/lint-output.log", out.splitlines()[-1])
        self.assertLessEqual(len(out.encode()), common.SUCCESS_CAP)
        self.assertEqual(self.log("lint"), "\n".join(GREEN_LINT) + "\n")  # the log keeps the whole output

    def test_a_green_run_over_the_cap_is_cut_and_says_how_many_lines_were_left_out(self) -> None:
        lines = ["x"] + [f"  ok    step {n} " + "y" * 60 for n in range(100)]
        rc, out = printed(common.quiet, "lint", self.body(lines, 0))
        self.assertEqual(rc, 0)
        self.assertLessEqual(len(out.encode()), common.SUCCESS_CAP + 300)
        self.assertRegex(out, r"\.\.\. \d+ more lines; full output: tools/out/logs/lint-output\.log")
        self.assertEqual(len(self.log("lint").splitlines()), 101)

    def test_bulk_lines_are_counted_after_the_first_few_and_other_warnings_stay(self) -> None:
        lines = ["check", "  ok    UID lint"] + [SCRIPT_WARNING.format(n=n) for n in range(40)]
        lines += ["  warn  GODOT CRASHED AT EXIT: access violation", "check: passed"]
        rc, out = printed(common.quiet, "check", self.body(lines, 0), bulk=check.SCRIPT_WARNING)
        self.assertEqual(rc, 0)
        self.assertEqual(out.count("res://client/a.gd"), common.BULK_SHOWN)
        self.assertIn("and 37 more of those lines (40 in all)", out)
        shown = out.splitlines()
        self.assertIn("more of those lines", shown[shown.index(SCRIPT_WARNING.format(n=common.BULK_SHOWN - 1)) + 1])
        self.assertIn("GODOT CRASHED AT EXIT", out)  # a warning of another kind is never collapsed
        self.assertEqual(self.log("check").count("res://client/a.gd"), 40)

    def test_a_red_run_prints_the_failing_lines_the_exit_code_and_the_log_path_but_no_ok_lines(self) -> None:
        lines = ["lint", "  ok    gdformat (3 files)", "  FAIL  net/a.gd:3: bad name", "        -> fix it", "lint: FAILED"]
        rc, out = printed(common.quiet, "lint", self.body(lines, 1))
        self.assertEqual(rc, 1)
        self.assertIn("  FAIL  net/a.gd:3: bad name", out)
        self.assertIn("        -> fix it", out)
        self.assertNotIn("gdformat", out)
        self.assertEqual(out.splitlines()[-1].split(";")[0], "lint: FAILED, exit=1")
        self.assertIn("tools/out/logs/lint-output.log", out.splitlines()[-1])

    def test_a_red_run_is_capped_at_about_4_kb_with_a_count_of_the_lines_left_out(self) -> None:
        lines = ["lint"] + [f"  FAIL  net/a.gd:{n}: " + "z" * 120 for n in range(200)] + ["lint: FAILED"]
        rc, out = printed(common.quiet, "lint", self.body(lines, 1))
        self.assertEqual(rc, 1)
        self.assertLessEqual(len(out.encode()), common.FAILURE_CAP + 400)
        self.assertIn("net/a.gd:0:", out)
        self.assertRegex(out, r"\.\.\. \d+ more lines; full output: tools/out/logs/lint-output\.log")
        self.assertIn("lint: FAILED, exit=1", out)
        self.assertEqual(len(self.log("lint").splitlines()), 202)

    def test_a_red_check_counts_its_script_warnings_so_a_later_fail_line_still_prints(self) -> None:
        warnings = [SCRIPT_WARNING.format(n=n) for n in range(40)]
        lines = ["check", *warnings, "  FAIL  res://tests/x.gd:1: Parse Error", "check: FAILED"]
        rc, out = printed(common.quiet, "check", self.body(lines, 1), bulk=check.SCRIPT_WARNING)
        self.assertEqual(rc, 1)
        self.assertIn("  FAIL  res://tests/x.gd:1: Parse Error", out)
        self.assertIn("... and 37 more of those lines (40 in all)", out)
        self.assertNotIn("more lines;", out)  # nothing cut by the cap
        self.assertEqual(self.log("check").count("res://client/a.gd"), 40)

    def test_a_very_long_line_is_cut(self) -> None:
        _, out = printed(common.quiet, "lint", self.body(["lint", "  FAIL  " + "q" * 5000, "lint: FAILED"], 1))
        self.assertLess(len(out), 1000)

    def test_an_exception_prints_what_the_body_had_printed_and_goes_on_up(self) -> None:
        def run() -> int:
            common.say("check")
            common.bad("project check crashed")
            raise common.Failure("boom")

        out = io.StringIO()
        with contextlib.redirect_stdout(out), self.assertRaises(common.Failure):
            common.quiet("check", run)
        self.assertIn("  FAIL  project check crashed", out.getvalue())
        self.assertIn("check: FAILED, Failure;", out.getvalue())
        self.assertIn("project check crashed", self.log("check"))

    def test_verbose_prints_everything_and_writes_no_log(self) -> None:
        lines = ["lint"] + [f"  ok    step {n}" for n in range(200)] + ["lint: passed"]
        rc, out = printed(common.quiet, "lint", self.body(lines, 0), verbose=True)
        self.assertEqual(rc, 0)
        self.assertEqual(out.splitlines(), lines)
        self.assertFalse((self.root / "tools" / "out" / "logs" / "lint-output.log").exists())


class LintCheckWiringTest(unittest.TestCase):
    """lint.main and check.main go through quiet unless verbose; verify (out of scope of #590) keeps the whole output."""

    def test_lint_main_is_quiet_unless_verbose(self) -> None:
        with mock.patch.object(lint, "quiet", return_value=0) as quiet:
            lint.main(files=["net"])
            lint.main(verbose=True)
        self.assertEqual([call.args[0] for call in quiet.call_args_list], ["lint", "lint"])
        self.assertEqual([call.args[2] for call in quiet.call_args_list], [False, True])

    def test_check_main_is_quiet_unless_verbose_and_counts_script_warnings(self) -> None:
        with mock.patch.object(check, "quiet", return_value=0) as quiet:
            check.main()
            check.main(verbose=True)
        self.assertEqual([call.args[2] for call in quiet.call_args_list], [False, True])
        self.assertIs(quiet.call_args.kwargs["bulk"], check.SCRIPT_WARNING)
        self.assertTrue(check.SCRIPT_WARNING.match(SCRIPT_WARNING.format(n=1)))
        self.assertFalse(check.SCRIPT_WARNING.match("  warn  NOT STARTED: godot"))

    def test_verify_runs_lint_and_check_verbose(self) -> None:
        with mock.patch.object(verify.lint, "main", return_value=0) as lint_main:
            verify.steps()["lint"]()
        self.assertTrue(lint_main.call_args.kwargs["verbose"])
        with mock.patch.object(verify.check, "main", return_value=0) as check_main:
            verify.steps()["check"]()
        self.assertTrue(check_main.call_args.kwargs["verbose"])

    def test_the_cli_passes_verbose_on(self) -> None:
        with mock.patch.object(lint, "main", return_value=0) as lint_main:
            cli.main(["lint", "--verbose"])
            cli.main(["lint"])
        self.assertEqual([c.kwargs["verbose"] for c in lint_main.call_args_list], [True, False])
        with mock.patch.object(check, "main", return_value=0) as check_main:
            cli.main(["check", "--verbose"])
            cli.main(["check"])
        self.assertEqual([c.kwargs["verbose"] for c in check_main.call_args_list], [True, False])
        with mock.patch.object(wait, "main", return_value=0) as wait_main:
            cli.main(["wait", "x.log", "--verbose"])
            cli.main(["wait", "x.log"])
        self.assertEqual([c.kwargs["verbose"] for c in wait_main.call_args_list], [True, False])


STEPS = [f"  passed  step{n:<10} {n}.0s" for n in range(3)]


class QuietWaitTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.log = Path(tmp.name) / "verify-1.log"

    def wait(self, lines: list[str], verbose: bool = False) -> tuple[int, list[str]]:
        self.log.write_text("\n".join(lines) + "\n", encoding="utf-8")
        rc, out = printed(wait.main, str(self.log), 5, verbose=verbose)
        return rc, out.splitlines()

    def test_a_long_green_summary_is_capped_and_closes_with_the_finish_line(self) -> None:
        summary = ["verify summary"] + [f"  passed  step{n:<10} {n}.0s " + "n" * 80 for n in range(60)]
        rc, out = self.wait(summary + ["verify: passed in 1.0s", "exit=0"])
        self.assertEqual(rc, 0)
        self.assertLessEqual(len("\n".join(out[:-1]).encode()), common.SUCCESS_CAP + 200)
        self.assertRegex(out[-2], r"\.\.\. \d+ more lines; whole log: .*verify-1\.log")
        self.assertRegex(out[-1], r"^wait: verify-1\.log finished: exit=0 \(whole log: .*verify-1\.log\)$")

    def test_a_red_log_adds_the_first_failing_lines_before_its_summary_under_4_kb(self) -> None:
        body = ["== lint (python lane, 4.1s, FAILED)", "lint", "  FAIL  net/a.gd:3: bad name", "  ok    gdlint"]
        body += ["== test", *[f"  FAIL  suite{n} failed" for n in range(40)], "  ok    other"]
        summary = ["verify summary", *STEPS, "  FAILED  lint   4.1s", "verify: FAILED in 2.0s"]
        rc, out = self.wait(body + summary + ["exit=1"])
        self.assertEqual(rc, 1)
        self.assertEqual(out[: len(summary)], summary)
        text = "\n".join(out)
        self.assertIn("first failing lines of the log", text)
        self.assertIn("  FAIL  net/a.gd:3: bad name", text)
        self.assertEqual(text.count("FAIL  suite"), wait.FAILING_SHOWN - 2)  # after the two before it
        self.assertNotIn("ok    gdlint", text)
        self.assertLessEqual(len(text.encode()), common.FAILURE_CAP + 400)
        self.assertRegex(out[-1], r"finished: exit=1 \(whole log: .*verify-1\.log\)$")

    def test_a_red_log_without_a_summary_block_prints_its_last_lines_and_the_exit_code(self) -> None:
        rc, out = self.wait(["publish: rebase failed", "exit=3"])
        self.assertEqual(rc, 3)
        self.assertEqual(out[0], "publish: rebase failed")
        self.assertIn("exit=3", out[-1])

    def test_verbose_keeps_the_whole_summary(self) -> None:
        summary = ["verify summary"] + [f"  passed  step{n:<10} {n}.0s " + "n" * 80 for n in range(60)]
        rc, out = self.wait(summary + ["verify: passed in 1.0s", "exit=0"], verbose=True)
        self.assertEqual(rc, 0)
        self.assertEqual(out[: len(summary) + 1], summary + ["verify: passed in 1.0s"])
        self.assertFalse(any(re.search(r"more lines", line) for line in out))


if __name__ == "__main__":
    unittest.main()
