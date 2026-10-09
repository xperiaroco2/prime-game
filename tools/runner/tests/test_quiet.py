"""Quiet `lint`, `check` and `wait` (#590, part 1 of #572): a summary on success, a capped excerpt and the log's path on
failure, the exit code and the failing step always shown, `--verbose` for today's whole output."""

import contextlib
import io
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import check, cli, common, lint, merge, metrics, publish, verify, wait, wave

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

    def test_cap_lines_can_keep_its_last_lines_and_cut_the_middle(self) -> None:
        lines = [f"line {n} " + "x" * 90 for n in range(50)] + ["the outcome"]
        kept = common.cap_lines(lines, 1000, "see the log", keep_end=1)
        self.assertEqual(kept[0], lines[0])
        self.assertRegex(kept[-2], r"^  \.\.\. \d+ more lines; see the log$")
        self.assertEqual(kept[-1], "the outcome")
        self.assertLessEqual(common.line_bytes(kept), 1000 + 60)
        self.assertEqual(common.cap_lines(lines[:3], 1000, "see the log", keep_end=1), lines[:3])

    def test_cap_lines_keeps_every_line_when_keep_end_is_more_than_there_are(self) -> None:
        lines = ["a" * 300, "b" * 300]
        self.assertEqual(common.cap_lines(lines, 100, "see the log", keep_end=3), lines)

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

    def test_the_log_holds_this_runs_lines_as_they_are_printed_never_the_previous_runs(self) -> None:
        log = self.root / "tools" / "out" / "logs" / "check-output.log"
        log.parent.mkdir(parents=True)
        log.write_text("check\n  ok    UID lint\ncheck: passed\n", encoding="utf-8")  # an earlier green run
        seen: list[str] = []

        def run() -> int:
            common.say("check")
            common.bad("project check: Parse Error")
            seen.append(log.read_text(encoding="utf-8"))  # a run killed here (a shell timeout) leaves this
            raise KeyboardInterrupt

        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(KeyboardInterrupt):
            common.quiet("check", run)
        self.assertEqual(seen, ["check\n  FAIL  project check: Parse Error\n"])
        self.assertNotIn("check: passed", self.log("check"))

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
        with mock.patch.object(check, "quiet", return_value=0) as quiet, mock.patch.object(
            check, "changed_scripts", return_value=[]
        ):
            check.main()
            check.main(verbose=True)
        self.assertEqual([call.args[2] for call in quiet.call_args_list], [False, True])
        self.assertIs(quiet.call_args.kwargs["bulk"], check.SCRIPT_WARNING)
        self.assertTrue(check.SCRIPT_WARNING.match(SCRIPT_WARNING.format(n=1)))
        self.assertFalse(check.SCRIPT_WARNING.match("  warn  NOT STARTED: godot"))

    def test_a_quiet_check_never_counts_the_warnings_of_a_file_the_branch_changes(self) -> None:
        mine = "  warn  res://client/mine.gd:7: The local variable \"x\" is declared but never used. (UNUSED_VARIABLE)"
        with mock.patch.object(check, "quiet", return_value=0) as quiet, mock.patch.object(
            check, "changed_scripts", return_value=["client/mine.gd", "net/b+c.gd"]
        ):
            check.main()
        bulk = quiet.call_args.kwargs["bulk"]
        self.assertTrue(bulk.match(SCRIPT_WARNING.format(n=1)))  # client/a.gd: counted
        self.assertFalse(bulk.match(mine))
        self.assertFalse(bulk.match("  warn  res://net/b+c.gd:1: x"))
        self.assertTrue(bulk.match("  warn  res://client/mine.gd.uid:1: x"))  # another file
        self.assertFalse(bulk.match("  warn  NOT STARTED: godot"))

    def test_changed_scripts_are_the_branchs_and_the_uncommitted_gd_files(self) -> None:
        diff = common.Result(0, "client/a.gd\ndocs/x.md\n", False, 0.0)
        status = {" M net/b.gd", "?? tests/new_test.gd", "R  old.gd -> core/moved.gd", " M tools/x.py"}
        with mock.patch.object(common, "git", return_value=diff), mock.patch.object(
            check, "git_status", return_value=status
        ):
            self.assertEqual(
                check.changed_scripts(), ["client/a.gd", "core/moved.gd", "net/b.gd", "tests/new_test.gd"]
            )
        with mock.patch.object(common, "git", return_value=common.Result(128, "fatal", False, 0.0)), mock.patch.object(
            check, "git_status", return_value=set()
        ):
            self.assertEqual(check.changed_scripts(), [])

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


CLEAN_CHECK = [
    "merge-check",
    "  ok    fetched origin",
    "  ok    2 open PRs: release/m6.2 (2)",
    "",
    "### release/m6.2 (origin/release/m6.2 at 38f028f84c): #663, #664",
    "",
    "| check | textual | semantic |",
    "|---|---|---|",
    "| #663 onto release/m6.2 | clean | clean |",
    "| #664 onto release/m6.2 | clean | clean |",
    "| #663 + #664 | clean | clean |",
    "",
    "merge-check: clean (0 textual conflicts and 0 overlaps in 3 checks)",
]
RED_CHECK = [
    *CLEAN_CHECK[:10],
    "| #663 + #664 | conflict: a.gd | clean |",
    "",
    "### across bases (main, release/m6.2): pairs that both change files under tools/ (textual: the files both change)",
    "",
    "| check | shared files | textual | semantic |",
    "|---|---|---|---|",
    "| #663 + #700 | tools/x.py | clean | clean |",
    "| #664 + #700 | tools/x.py | clean | overlap: `f` |",
    "",
    "#664 + #700:",
    "- `f` changed in tools/x.py:3, used in tools/y.py:9",
    "",
    "merge-check: 1 textual conflicts and 1 overlaps in 5 checks. Order the merges so ...",
    "Across bases: name the pair on both tracks' plan issues; ...",
]


class QuietMergeTest(unittest.TestCase):
    """merge-check and merge quiet (#572): merge-check's clean rows counted, merge's ok lines left out; the verdict,
    the wave: line and the exit code as before; --verbose and wave get every line."""

    setUp = QuietTest.setUp  # the logs in a temporary folder
    body = QuietTest.body
    log = QuietTest.log

    def check_with(self, lines: list[str], rc: int):  # type: ignore[no-untyped-def]
        return mock.patch.object(merge, "check", side_effect=lambda *_a, **_k: self.body(lines, rc)())

    def test_clean_rows_are_counted_and_a_clean_table_is_one_line(self) -> None:
        self.assertEqual(merge.clean_rows_counted(CLEAN_CHECK), [
            "merge-check", "", "### release/m6.2 (origin/release/m6.2 at 38f028f84c): #663, #664", "",
            "3 checks, all clean (--verbose lists them)", "",
            "merge-check: clean (0 textual conflicts and 0 overlaps in 3 checks)",
        ])  # fmt: skip
        red = merge.clean_rows_counted(RED_CHECK)
        self.assertIn("| #663 + #664 | conflict: a.gd | clean |", red)
        self.assertIn("| #664 + #700 | tools/x.py | clean | overlap: `f` |", red)
        self.assertNotIn("| #663 onto release/m6.2 | clean | clean |", red)
        self.assertNotIn("| #663 + #700 | tools/x.py | clean | clean |", red)
        self.assertEqual(red.count("| check | textual | semantic |"), 1)
        self.assertIn("2 more clean (--verbose lists them)", red)
        self.assertIn("1 more clean (--verbose lists them)", red)
        self.assertEqual(merge.clean_rows_counted(CLEAN_CHECK[6:9]), ["1 check, all clean (--verbose lists them)"])
        self.assertIn("- `f` changed in tools/x.py:3, used in tools/y.py:9", red)

    def test_a_clean_merge_check_prints_the_verdict_and_the_log_path(self) -> None:
        with self.check_with(CLEAN_CHECK, 0):
            rc, out = printed(merge.check_command, [], None)
        lines = out.splitlines()
        self.assertEqual(rc, 0)
        self.assertEqual(lines[-2], CLEAN_CHECK[-1])
        self.assertIn("full output: tools/out/logs/merge-check-all-output.log", lines[-1])
        self.assertNotIn("| #663 + #664 | clean | clean |", out)
        self.assertIn("| #663 + #664 | clean | clean |", self.log("merge-check-all"))

    def test_a_red_merge_check_keeps_its_flagged_rows_its_verdict_and_its_exit_code(self) -> None:
        with self.check_with(RED_CHECK, 1):
            rc, out = printed(merge.check_command, [], None)
        lines = out.splitlines()
        self.assertEqual(rc, 1)
        self.assertEqual(lines[-3:-1], RED_CHECK[-2:])
        self.assertTrue(lines[-1].startswith("merge-check: FAILED, exit=1; full output: "))
        self.assertIn("| #663 + #664 | conflict: a.gd | clean |", lines)

    def test_verbose_merge_check_prints_every_line(self) -> None:
        with self.check_with(CLEAN_CHECK, 0):
            _rc, out = printed(merge.check_command, [], None, verbose=True)
        self.assertEqual(out.splitlines(), CLEAN_CHECK)

    def test_merge_drops_its_ok_lines_and_keeps_its_wave_line(self) -> None:
        lines = ["merge #5 --base main", "  ok    #5: the gate passed; merging through GitHub at abc",
                 "wave: merged #5 (tooling/5-x) into main as 123 through GitHub; gate: CI green"]  # fmt: skip
        with mock.patch.object(merge, "merge", side_effect=lambda *_a, **_k: self.body(lines, 0)()):
            rc, out = printed(merge.merge_command, 5, "main")
        self.assertEqual(rc, 0)
        self.assertEqual(out.splitlines()[:-1], [lines[0], lines[2]])
        self.assertIn("full output: tools/out/logs/merge-5-output.log", out.splitlines()[-1])

    def test_overlapping_merge_runs_each_keep_their_own_log(self) -> None:
        """Two managers merging at once (#572 review): one fixed log would be truncated by the second run."""
        for number in (5, 6):
            lines = [f"merge #{number} --base main", f"  ok    #{number}: the gate passed", f"wave: merged #{number}"]
            with mock.patch.object(merge, "merge", side_effect=lambda *_a, _l=lines, **_k: self.body(_l, 0)()):
                printed(merge.merge_command, number, "main")
        self.assertIn("wave: merged #5", self.log("merge-5"))
        self.assertIn("wave: merged #6", self.log("merge-6"))
        with self.check_with(CLEAN_CHECK, 0):
            printed(merge.check_command, [664, 663], None)
            printed(merge.check_command, [700], None)
        self.assertIn("### release/m6.2", self.log("merge-check-663-664"))
        self.assertIn("### release/m6.2", self.log("merge-check-700"))

    def test_a_refused_merge_raises_as_before_after_its_excerpt(self) -> None:
        def refuse(*_a: object, **_k: object) -> int:
            common.say("merge #5 --base release/m6")
            raise common.Failure("#5 is a draft. Nothing was changed.")

        with mock.patch.object(merge, "merge", side_effect=refuse), self.assertRaises(common.Failure):
            printed(merge.merge_command, 5, "release/m6")
        with mock.patch.object(merge, "merge", side_effect=refuse):
            rc, out = printed(cli.main, ["merge", "5", "--base", "release/m6"])
        self.assertEqual(rc, 1)
        self.assertEqual(out.splitlines()[-1], "  FAIL  #5 is a draft. Nothing was changed.")

    def test_the_cli_passes_verbose_on(self) -> None:
        with mock.patch.object(merge, "check_command", return_value=0) as check_command:
            cli.main(["merge-check"])
            cli.main(["merge-check", "--verbose"])
        self.assertEqual([c.kwargs["verbose"] for c in check_command.call_args_list], [False, True])
        with mock.patch.object(merge, "merge_command", return_value=0) as merge_command:
            cli.main(["merge", "5", "--base", "main"])
            cli.main(["merge", "5", "--base", "main", "--verbose"])
        self.assertEqual([c.kwargs["verbose"] for c in merge_command.call_args_list], [False, True])
        with mock.patch.object(publish, "main", return_value=0) as publish_main:
            cli.main(["publish"])
            cli.main(["publish", "--verbose"])
        self.assertEqual([c.kwargs["verbose"] for c in publish_main.call_args_list], [False, True])

    def test_wave_still_reads_every_line_of_merge_check(self) -> None:
        with self.check_with(CLEAN_CHECK, 0):
            found = wave.capture_merge_check(lambda numbers, base: merge.check(numbers, base=base), "main")
        self.assertEqual(found.verdict, CLEAN_CHECK[-1])


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
        self.assertRegex(out[-3], r"\.\.\. \d+ more lines; whole log: .*verify-1\.log")
        self.assertEqual(out[-2], "verify: passed in 1.0s")  # the cut is in the middle: the end line stays
        self.assertRegex(out[-1], r"^wait: verify-1\.log finished: exit=0 \(whole log: .*verify-1\.log\)$")

    def test_a_green_publish_keeps_its_verify_block_and_its_push_lines_after_it(self) -> None:
        rows = [f"  passed  step{n:<12} {n}.0s" for n in range(30)]
        block = ["verify summary", *rows, "  lanes: python 1.0s, godot 2.0s; 16 CPUs", "verify: passed in 3.0s"]
        push = [
            "publish: verify runs: a new tree",
            *[f"        remote: line {n} of the push " + "r" * 40 for n in range(8)],
            "  ok    pushed tooling/590-x at 0123456789 (new)",
            "publish: done",
        ]
        self.assertGreater(len("\n".join(block + push).encode()), common.SUCCESS_CAP)
        rc, out = self.wait(["== doctor", *block, *push, "exit=0"])
        self.assertEqual(rc, 0)
        self.assertEqual(out[: len(block)], block)  # whole, for metrics.parse_verify
        self.assertEqual(out[-3:-1], ["  ok    pushed tooling/590-x at 0123456789 (new)", "publish: done"])
        self.assertIsNotNone(metrics.parse_verify("\n".join(out)))
        self.assertLessEqual(len("\n".join(out[:-1]).encode()), common.SUCCESS_CAP + 200)  # one cap for both parts

    def test_a_red_publish_with_a_long_push_stays_under_4_kb(self) -> None:
        block = ["verify summary", *STEPS, "  FAILED  lint   1.0s", "verify: FAILED in 3.0s"]
        push = [f"        remote: line {n} " + "r" * 100 for n in range(60)] + ["  FAIL  push refused", "publish: stopped"]
        rc, out = self.wait([*block, *push, "exit=1"])
        self.assertEqual(rc, 1)
        self.assertEqual(out[: len(block)], block)
        self.assertEqual(out[-3:-1], ["  FAIL  push refused", "publish: stopped"])
        self.assertLessEqual(len("\n".join(out[:-1]).encode()), common.FAILURE_CAP + 200)

    def test_a_summary_without_a_verify_end_line_keeps_its_last_lines(self) -> None:
        summary = ["merge-train summary", *[f"  merged  #{n} " + "m" * 80 for n in range(30)]]
        rc, out = self.wait([*summary, "merge-train: 30 merged, 0 skipped of 30 PRs", "exit=0"])
        self.assertEqual(rc, 0)
        self.assertEqual(out[0], "merge-train summary")
        self.assertTrue(any("more lines; whole log:" in line for line in out))
        self.assertEqual(out[-2], "merge-train: 30 merged, 0 skipped of 30 PRs")
        self.assertLessEqual(len("\n".join(out[:-1]).encode()), common.SUCCESS_CAP + 200)

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

    def test_a_red_publish_retried_in_one_log_shows_only_the_last_attempts_failing_lines(self) -> None:
        first = ["== test", "  FAIL  old_suite failed", "verify summary", "  FAILED  test   1.0s", "verify: FAILED in 1.0s"]
        second = ["== lint", "  FAIL  net/b.gd:9: new failure", "verify summary", "  FAILED  lint   1.0s"]
        rc, out = self.wait([*first, *second, "verify: FAILED in 2.0s", "exit=1"])
        self.assertEqual(rc, 1)
        text = "\n".join(out)
        self.assertIn("  FAIL  net/b.gd:9: new failure", text)
        self.assertNotIn("old_suite", text)

    def test_a_red_merge_train_shows_the_failing_lines_of_every_pr_it_tried(self) -> None:
        log = ["== #1", "  FAIL  suite_a failed", "verify summary", "verify: FAILED in 1.0s"]
        log += ["== #2", "verify summary", "verify: passed in 1.0s", "merge-train summary", "  skipped #1", "  merged  #2"]
        rc, out = self.wait([*log, "merge-train: 1 merged, 1 skipped of 2 PRs", "exit=1"])
        self.assertEqual(rc, 1)
        self.assertIn("  FAIL  suite_a failed", "\n".join(out))

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
