"""Processes Windows could not start (#441): exit 0xC0000142 (STATUS_DLL_INIT_FAILED) before the first line. `run`
starts such a process once more after a pause, loudly, never one that ran; once a restart was refused too, the
process restarts nothing more. `run`'s, the GdUnit4 shards' and the game session's reports name it, and
`machine_load` records the machine's load in the NOT STARTED line."""

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import common, gdunit, hostjoin, launch
from runner.common import ROOT, Result

REFUSED = 3221225794  # 0xC0000142 as subprocess reports it on Windows
# A child that stands in for a process Windows refused: it exits TEST_CODE silently for its first `refusals` starts
# (the count kept in a file), then prints "ran" and exits 0. TEST_CODE is added to the not-started codes for the test:
# a real 0xC0000142 exit status exists only on Windows (RealCodeTest).
TEST_CODE = 66
CHILD = """
import sys
from pathlib import Path
count, refusals = Path(sys.argv[1]), int(sys.argv[2])
starts = int(count.read_text()) + 1 if count.exists() else 1
count.write_text(str(starts))
if starts <= refusals:
    sys.exit(66)
print("ran")
"""


class PredicateTest(unittest.TestCase):
    def test_only_the_code_with_no_output_and_a_short_life_never_ran(self) -> None:
        self.assertTrue(common.not_started(REFUSED, ""))
        self.assertTrue(common.not_started(-1073741502, " \n", 2.1))
        self.assertFalse(common.not_started(REFUSED, "ERROR: x\n"), "it printed a line: it ran")
        self.assertFalse(common.not_started(REFUSED, "", common.NOT_STARTED_SECONDS), "it lived: it ran")
        for rc in (0, 1, 3221225477, None):
            self.assertFalse(common.not_started(rc, ""), rc)

    def test_the_words_name_the_code(self) -> None:
        self.assertIn("0xC0000142, STATUS_DLL_INIT_FAILED", common.exit_words(REFUSED))
        self.assertEqual(common.exit_words(3), "exited 3")
        problem = common.start_problem(REFUSED)
        self.assertTrue(problem.startswith("could not start: exited 3221225794 (0xC0000142"), problem)
        self.assertIn("run verify again", problem)
        self.assertNotIn("restart", problem, "only a process run() restarted was restarted")
        self.assertIn("before it printed anything, also on its restart; ", common.start_problem(REFUSED, True))


class RestartTest(unittest.TestCase):
    """run() on a real child, with TEST_CODE counted as not started and no real pause."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.count = Path(tmp.name) / "starts"
        self.starts = common.Starts()
        self.pause = mock.MagicMock()
        for patch in (
            mock.patch.object(common, "NOT_STARTED_CODES", (*common.NOT_STARTED_CODES, TEST_CODE)),
            mock.patch.object(common, "STARTS", self.starts),
            mock.patch.object(common, "_restart_sleep", self.pause),
            mock.patch.object(common, "machine_load", return_value="Machine: a test"),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def run_child(self, refusals: int, code: str = CHILD) -> tuple[Result, str, int]:
        """run() of the child; its result, the runner's printed lines and how often the child started."""
        self.count.unlink(missing_ok=True)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            res = common.run([sys.executable, "-c", code, str(self.count), str(refusals)], timeout=60)
        return res, out.getvalue(), int(self.count.read_text()) if self.count.exists() else 0

    def test_a_refused_start_is_restarted_once_loudly_and_its_restart_is_the_result(self) -> None:
        started: list[object] = []
        self.count.unlink(missing_ok=True)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            res = common.run(
                [sys.executable, "-c", CHILD, str(self.count), "1"], timeout=60, on_start=started.append
            )
        self.assertEqual((res.rc, res.out.strip()), (0, "ran"))
        self.assertEqual(self.count.read_text(), "2")
        self.assertEqual(len(started), 2, "on_start sees each start")
        self.pause.assert_called_once_with(common.RESTART_PAUSE)
        self.assertGreaterEqual(res.seconds, common.RESTART_PAUSE, "the seconds count from the first start")
        text = out.getvalue()
        self.assertIn("  warn  NOT STARTED, restarted once: python", text)
        self.assertIn("so it never ran; starting it again in", text)
        self.assertIn("Machine: a test", text)
        self.assertIn("  warn  RESTARTED: python", text)
        self.assertEqual(common.take_starts(), {"refused": 1, "restarted": 1, "recovered": 1})
        self.assertEqual(common.take_starts(), {}, "taken once")
        self.assertFalse(self.starts.gave_up)

    def test_a_restart_refused_too_fails_and_the_process_restarts_nothing_more(self) -> None:
        res, text, starts = self.run_child(refusals=5)
        self.assertEqual((res.rc, starts), (TEST_CODE, 2))
        self.assertIn("NOT STARTED again: python", text)
        self.assertTrue(self.starts.gave_up)
        res, text, starts = self.run_child(refusals=5)
        self.assertEqual((res.rc, starts), (TEST_CODE, 1), "no restart after a refused one")
        self.assertIn("not restarted, since a restart in this process failed the same way", text)
        self.pause.assert_called_once()
        self.assertEqual(common.take_starts(), {"refused": 3, "restarted": 1, "recovered": 0})
        res, _text, starts = self.run_child(refusals=0)
        self.assertEqual((res.rc, starts), (0, 1), "a start that works still runs")

    def test_a_run_instance_refused_twice_is_reported_as_not_started(self) -> None:
        res, _text, starts = self.run_child(refusals=5)
        self.assertEqual((res.rc, starts), (TEST_CODE, 2))
        self.assertGreaterEqual(res.seconds, common.RESTART_PAUSE, "the seconds count from the first start")
        problem = launch.Instance(1, ROOT / "tools/out/logs/run/x-1.log", res, 60).problem
        self.assertTrue(problem.startswith("could not start: exited 66"), problem)
        self.assertIn("also on its restart", problem)
        self.assertTrue(res.restarted)
        res, _text, starts = self.run_child(refusals=5)
        self.assertEqual((starts, res.restarted), (1, False), "gave up: not restarted")
        problem = launch.Instance(1, ROOT / "tools/out/logs/run/x-1.log", res, 60).problem
        self.assertNotIn("restart", problem, "a report names a restart only when one ran")

    def test_a_process_that_ran_is_never_started_again(self) -> None:
        printed = CHILD.replace("    sys.exit(66)", "    print('a line'); sys.exit(66)")
        res, text, starts = self.run_child(refusals=1, code=printed)
        self.assertEqual((res.rc, starts, text), (TEST_CODE, 1, ""))
        with mock.patch.object(common, "NOT_STARTED_SECONDS", 0.0):
            res, text, starts = self.run_child(refusals=1)
        self.assertEqual((res.rc, starts, text), (TEST_CODE, 1, ""), "it lived longer than a refused start does")
        failed = CHILD.replace("sys.exit(66)", "sys.exit(3)")
        res, text, starts = self.run_child(refusals=1, code=failed)
        self.assertEqual((res.rc, starts, text), (3, 1, ""), "another exit code")
        self.pause.assert_not_called()
        self.assertEqual(common.take_starts(), {})


@unittest.skipUnless(common.IS_WINDOWS, "a real 0xC0000142 exit status exists only on Windows")
class RealCodeTest(unittest.TestCase):
    def test_a_child_that_exits_0xC0000142_silently_counts_as_not_started(self) -> None:
        with (
            mock.patch.object(common, "STARTS", common.Starts()),
            mock.patch.object(common, "_restart_sleep"),
            contextlib.redirect_stdout(io.StringIO()) as out,
        ):
            res = common.run([sys.executable, "-c", "import os; os._exit(-1073741502)"], timeout=60)
            counts = common.take_starts()
        self.assertEqual(res.rc, REFUSED)
        self.assertEqual(counts, {"refused": 2, "restarted": 1, "recovered": 0})
        self.assertIn("NOT STARTED again", out.getvalue())

    def test_the_machine_load_line(self) -> None:
        line = common.machine_load()
        self.assertRegex(line, r"^Machine: \d+ processes, \d+ threads, \d+ handles; commit [\d.]+ of [\d.]+ GB")
        self.assertRegex(line, r"\d+ USER and \d+ GDI objects in \d+ processes$")


class ReportTest(unittest.TestCase):
    """Each report says `could not start` for a process that never ran, and keeps its words for one that ran."""

    def test_a_run_instance(self) -> None:
        def problem(rc: int, out: str) -> str:
            return launch.Instance(1, ROOT / "tools/out/logs/run/x-1.log", Result(rc, out, False, 0.2), 60).problem

        self.assertTrue(problem(REFUSED, "").startswith("could not start: exited 3221225794 (0xC0000142"))
        self.assertEqual(problem(REFUSED, "PROBE a line\n"), "exited 3221225794")

    def test_a_game_session_part(self) -> None:
        part = hostjoin.Part("host", [])
        part.proc = mock.MagicMock(returncode=REFUSED)
        self.assertTrue(part.problem.startswith("could not start: exited 3221225794"), part.problem)
        self.assertNotIn("restart", part.problem, "the game session's parts are never restarted")
        part.lines = ["session: hosting"]
        self.assertEqual(part.problem, "exited 3221225794 (hosting)")

    def test_a_gdunit_run(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertTrue(gdunit._judge(REFUSED, "", [], "tools/out/logs/test-shard1.log", "shard 1"))
        self.assertIn("shard 1: GdUnit4 could not start: exited 3221225794 (0xC0000142", out.getvalue())
        self.assertNotIn("restart", out.getvalue())
        with contextlib.redirect_stdout(io.StringIO()) as out:
            gdunit._judge(REFUSED, "", [], "x.log", restarted=True)
        self.assertIn("before it printed anything, also on its restart", out.getvalue())
        with contextlib.redirect_stdout(io.StringIO()) as out:
            gdunit._judge(REFUSED, "Godot started\n", [], "x.log")
        self.assertIn("GdUnit4 crashed or exited unexpectedly (exit 3221225794)", out.getvalue())


if __name__ == "__main__":
    unittest.main()
