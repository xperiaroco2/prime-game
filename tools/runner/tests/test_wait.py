"""`wait <log> [--max S]` (#303): a bounded wait on a background job's log, so no agent's tool call outlasts the
5-minute prompt cache. A job is finished only when the last complete line of its log is `exit=<n>`; until then
`wait` returns 124 after at most S seconds; a missing log or a bad --max is 2."""

import contextlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, guard, permissions, verify, wait
from runner.common import IS_WINDOWS, ROOT, git_bash

MAIN = re.sub(r"[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$", "", str(ROOT))
RULES = permissions.Rules.load(ROOT / ".claude" / "settings.json")

VERIFY_START = [
    "doctor",
    "  ok    Python 3.14.0",
    "",
    "verify: slot 1 of 2 (waited 0.0s)",
    "verify: two lanes at once (python: lint, selftest; godot: check, selftest-godot, test); each step's output "
    "follows whole when it ends",
    "",
]
VERIFY_STEPS = ["== lint (python lane, 4.1s, passed)", "lint", "  ok    gdformat", "  ok    gdlint"]
GREEN_SUMMARY = [
    "verify summary",
    "  passed  doctor            2.0s",
    "  passed  lint              4.1s",
    "  lanes: python 200.1s, godot 290.3s; 16 CPUs, selftest on 4 worker processes",
    "  slot 1 of 2 (waited 0.0s)",
    "verify: passed in 312.4s",
]
RED_SUMMARY = [
    "verify summary",
    "  passed  doctor            2.0s",
    "  FAILED  lint              4.1s",
    "verify: FAILED in 305.0s",
]


class Clock:
    """A fake monotonic clock: sleep() moves it, and `on_sleep` (call number -> action) may change the log."""

    def __init__(self) -> None:
        self.t = 0.0
        self.sleeps: list[float] = []
        self.on_sleep: dict[int, object] = {}

    def clock(self) -> float:
        return self.t

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.t += seconds
        action = self.on_sleep.get(len(self.sleeps))
        if callable(action):
            action()


class WaitTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="prime wait "))  # a space in the path, as in a real scratchpad
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.log = self.tmp / "verify-1.log"
        self.time = Clock()

    def write(self, lines: list[str], end: str = "\n", encoding: str = "utf-8") -> None:
        self.log.write_bytes((end.join(lines) + (end if lines else "")).encode(encoding))

    def append(self, text: str) -> None:
        with self.log.open("ab") as out:
            out.write(text.encode("utf-8"))

    def run_wait(self, max_seconds: int = 240, log: str | None = None, **kwargs: float) -> tuple[int, list[str]]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = wait.main(
                str(self.log) if log is None else log,
                max_seconds,
                clock=self.time.clock,
                sleep=self.time.sleep,
                **kwargs,
            )
        return rc, out.getvalue().splitlines()

    def test_a_finished_green_log_returns_0_and_prints_the_summary(self) -> None:
        self.write(VERIFY_START + VERIFY_STEPS + GREEN_SUMMARY + ["exit=0"])
        rc, out = self.run_wait()
        self.assertEqual(rc, 0)
        self.assertEqual(out[: len(GREEN_SUMMARY)], GREEN_SUMMARY)
        self.assertEqual(len(out), len(GREEN_SUMMARY) + 1, out)
        self.assertRegex(out[-1], r"^wait: .*verify-1\.log finished: exit=0 \(whole log: .*\)$")
        self.assertNotIn("== lint (python lane, 4.1s, passed)", out)
        self.assertEqual(self.time.sleeps, [])  # finished: no wait at all

    def test_a_finished_red_log_returns_1(self) -> None:
        self.write(VERIFY_START + VERIFY_STEPS + RED_SUMMARY + ["exit=1"])
        rc, out = self.run_wait()
        self.assertEqual(rc, 1)
        self.assertIn("verify: FAILED in 305.0s", out)
        self.assertIn("finished: exit=1", out[-1])

    def test_a_merge_train_log_prints_its_own_summary_after_the_publishes_verify(self) -> None:
        # merge-train (#387) runs publishes whose verify summaries come before its own: only the train's is printed.
        train = ["merge-train summary", "  merged   #30 (core/30-task): publish", "  skipped  #31: CI is red",
                 "merge-train: 1 merged, 1 skipped of 2 PRs"]  # fmt: skip
        self.write(VERIFY_START + VERIFY_STEPS + GREEN_SUMMARY + ["publish: done", "wave: merged #30"] + train
                   + ["exit=1"])  # fmt: skip
        rc, out = self.run_wait()
        self.assertEqual(rc, 1)
        self.assertEqual(out[:-1], train)

    def test_a_job_exit_code_passes_through_unchanged(self) -> None:
        # mutants has no "verify summary": the last lines before the marker are its table and verdict.
        body = [f"line {i}" for i in range(40)] + ["mutants: 3 killed, 0 survived in 400.0 s", "exit=2"]
        self.write(body)
        rc, out = self.run_wait()
        self.assertEqual(rc, 2)
        self.assertEqual(out[:-1], body[-1 - wait.TAIL_LINES : -1])
        self.assertIn("finished: exit=2", out[-1])
        self.assertTrue(all(line.startswith("wait: ") for line in out[-1:]))

    def test_a_running_log_times_out_with_124_and_one_line(self) -> None:
        self.write(VERIFY_START + VERIFY_STEPS)
        rc, out = self.run_wait(240)
        self.assertEqual(rc, wait.STILL_RUNNING)
        self.assertEqual(len(out), 1, out)
        self.assertTrue(out[0].startswith("wait: still running after 240 s ("), out[0])
        self.assertIn("never start the job again", out[0])
        self.assertLessEqual(sum(self.time.sleeps), 240)
        self.assertAlmostEqual(self.time.t, 240)

    def test_verify_early_lines_are_not_a_result(self) -> None:
        self.write(VERIFY_START)
        self.assertEqual(self.run_wait(30)[0], wait.STILL_RUNNING)

    def test_a_half_written_or_misplaced_exit_line_is_not_a_result(self) -> None:
        cases = {
            "exit= without a newline": "exit=",
            "exit=0 without a newline": "exit=0",
            "a word before it": "xexit=0\n",
            "indented": "  exit=0\n",
            "a word after it": "exit=0 later\n",
        }
        for name, tail in cases.items():
            with self.subTest(case=name):
                self.write(VERIFY_START + GREEN_SUMMARY)
                self.append(tail)
                self.assertEqual(self.run_wait(9)[0], wait.STILL_RUNNING)

    def test_an_exit_line_in_the_middle_is_not_a_result(self) -> None:
        # A step's output can hold a bare exit=0 line (a test fixture printed whole); only the launch line's echo,
        # the last write of the job, counts.
        self.write(VERIFY_START + ["exit=0"] + VERIFY_STEPS)
        self.assertEqual(self.run_wait(9)[0], wait.STILL_RUNNING)

    def test_blank_lines_after_the_marker_still_count_as_finished(self) -> None:
        self.write(GREEN_SUMMARY + ["exit=0", "", ""])
        self.assertEqual(self.run_wait()[0], 0)

    def test_the_job_finishing_during_the_wait_returns_early(self) -> None:
        self.write(VERIFY_START + VERIFY_STEPS)
        self.time.on_sleep[3] = lambda: self.append("\n".join(GREEN_SUMMARY) + "\nexit=0\n")
        rc, out = self.run_wait(240)
        self.assertEqual(rc, 0)
        self.assertEqual(len(self.time.sleeps), 3)
        self.assertLess(self.time.t, 240)
        self.assertEqual(out[0], "verify summary")

    def test_a_missing_log_exits_2_after_the_grace(self) -> None:
        rc, out = self.run_wait(240, grace=10)
        self.assertEqual(rc, wait.MISSING)
        self.assertEqual(len(out), 1, out)
        self.assertTrue(out[0].startswith("wait: no log at "), out[0])
        self.assertGreaterEqual(self.time.t, 10)
        self.assertLess(self.time.t, 20)

    def test_a_log_that_appears_during_the_grace_is_waited_on(self) -> None:
        self.time.on_sleep[2] = lambda: self.write(GREEN_SUMMARY + ["exit=0"])
        self.assertEqual(self.run_wait(240, grace=10)[0], 0)

    def test_a_log_deleted_during_the_wait_exits_2(self) -> None:
        self.write(VERIFY_START)
        self.time.on_sleep[1] = self.log.unlink
        rc, out = self.run_wait(240)
        self.assertEqual(rc, wait.MISSING)
        self.assertTrue(out[0].startswith("wait: "), out)
        self.assertIn("disappeared", out[0])

    def test_an_unreadable_log_is_waits_own_2_never_a_traceback(self) -> None:
        # A folder passed by mistake (Windows reads it as a PermissionError) or a locked log: never Python's exit 1,
        # which an agent would read as a red job.
        rc, out = self.run_wait(240, log=str(self.tmp))
        self.assertEqual(rc, wait.MISSING)
        self.assertEqual(len(out), 1, out)
        self.assertTrue(out[0].startswith("wait: cannot read "), out[0])
        self.write(VERIFY_START)
        with mock.patch.object(Path, "read_bytes", side_effect=PermissionError(13, "locked")):
            rc, out = self.run_wait(240)
        self.assertEqual(rc, wait.MISSING)
        self.assertTrue(out[0].startswith("wait: cannot read "), out)

    def test_max_over_270_or_under_1_is_refused(self) -> None:
        self.write(GREEN_SUMMARY + ["exit=0"])
        for value in ("300", "271", "0", "-5"):
            with self.subTest(max=value):
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    rc = cli.main(["wait", str(self.log), "--max", value])
                self.assertEqual(rc, 2)
                self.assertIn("wait: --max is 1 to 270 s", out.getvalue())
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            cli.main(["wait", str(self.log), "--max", "four"])
        self.assertEqual(raised.exception.code, 2)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(["wait", str(self.log), "--max", "270"]), 0)

    def test_encodings_and_line_ends(self) -> None:
        # PowerShell 5.1's `*>` writes UTF-16 with a BOM; Out-File and Set-Content may add a UTF-8 BOM; CRLF lines.
        for name, encoding, end in (
            ("utf-8 BOM", "utf-8-sig", "\n"),
            ("utf-16 BOM", "utf-16", "\r\n"),
            ("CRLF", "utf-8", "\r\n"),
        ):
            with self.subTest(encoding=name):
                self.write(GREEN_SUMMARY + ["exit=0"], end=end, encoding=encoding)
                rc, out = self.run_wait()
                self.assertEqual(rc, 0)
                self.assertEqual(out[0], "verify summary")
                self.write(VERIFY_START, end=end, encoding=encoding)
                self.assertEqual(self.run_wait(6)[0], wait.STILL_RUNNING)

    def test_path_forms(self) -> None:
        self.assertEqual(wait.native_path("/c/Users/x/a b/v.log", windows=True), Path("C:/Users/x/a b/v.log"))
        self.assertEqual(wait.native_path("/d/prime-game/t.log", windows=True), Path("D:/prime-game/t.log"))
        self.assertEqual(wait.native_path("C:\\Users\\x\\a b\\v.log", windows=True), Path("C:\\Users\\x\\a b\\v.log"))
        self.assertEqual(wait.native_path("C:/Users/x/v.log", windows=True), Path("C:/Users/x/v.log"))
        self.assertEqual(wait.native_path("/c/x/v.log", windows=False), Path("/c/x/v.log"))
        self.assertEqual(wait.native_path("/tmp/v.log", windows=True), Path("/tmp/v.log"))
        self.assertEqual(wait.native_path("~/v.log", windows=False), Path.home() / "v.log")

    def test_an_msys_only_path_says_so(self) -> None:
        # Git Bash's /tmp is not a folder Windows' Python can see: the log seems missing, and the line says why.
        rc, out = self.run_wait(240, log="/tmp/prime-wait-test-no-such.log", grace=0)
        self.assertEqual(rc, wait.MISSING)
        if IS_WINDOWS:
            self.assertIn("scratchpad", out[0])


HEAD = "a" * 40


class VerifiedTest(unittest.TestCase):
    """`wait --verified`: a standalone verify before `publish` (which runs verify itself) is needed unless the newest
    record passed at HEAD with a clean tree and the tree is still clean."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="prime wait "))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.history = self.tmp / "verify-history.jsonl"

    def run_verified(self, records: list[dict] | None, dirty: bool = False, head: str = HEAD) -> tuple[int, str]:
        if records is not None:
            self.history.write_text("".join(json.dumps(r) + "\n" for r in records), encoding="utf-8")
        status = {" M core/x.gd"} if dirty else set()
        facts = {"branch": "tooling/7-x", "head": head, "tree": None if dirty else "t" * 40, "runner": "r"}
        out = io.StringIO()
        with (
            mock.patch.object(verify, "HISTORY", self.history),
            mock.patch("runner.common.git_status", return_value=status),
            mock.patch.object(verify, "git_facts", return_value=facts),
            contextlib.redirect_stdout(out),
        ):
            rc = cli.main(["wait", "--verified"])
        return rc, out.getvalue()

    @staticmethod
    def record(**fields: object) -> dict:
        return {"start": "2026-10-04T18:00:00Z", "head": HEAD, "tree": "t" * 40, "status": "passed", **fields}

    def test_a_passed_verify_at_head_with_a_clean_tree_needs_no_second_one(self) -> None:
        rc, out = self.run_verified([self.record(status="FAILED"), self.record()])
        self.assertEqual(rc, 0, out)
        self.assertIn("wait: verify passed at HEAD aaaaaaaaaaaa with a clean tree", out)

    def test_anything_else_needs_a_verify(self) -> None:
        cases = {
            "no history": (None, False, "no verify record"),
            "an empty history": ([], False, "no verify record"),
            "red": ([self.record(status="FAILED")], False, "is FAILED"),
            "a commit since": ([self.record(head="b" * 40)], False, "ran at bbbbbbbbbbbb, HEAD is aaaaaaaaaaaa"),
            "a dirty run": ([self.record(tree=None)], False, "ran with uncommitted changes"),
            "dirty now": ([self.record()], True, "uncommitted changes now"),
            "the newest is red": ([self.record(), self.record(status="FAILED")], False, "is FAILED"),
        }
        for name, (records, dirty, why) in cases.items():
            with self.subTest(case=name):
                self.history.unlink(missing_ok=True)
                rc, out = self.run_verified(records, dirty)
                self.assertEqual(rc, 1, out)
                self.assertTrue(out.startswith("wait: no passed verify at HEAD"), out)
                self.assertIn(why, out)

    def test_a_log_and_verified_together_or_neither_is_2(self) -> None:
        for argv in (["wait"], ["wait", "x.log", "--verified"]):
            with self.subTest(argv=argv):
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    self.assertEqual(cli.main(argv), 2)
                self.assertIn("wait: give a log, or --verified alone", out.getvalue())


def msys(path: Path) -> str:
    """The Git Bash form of a Windows path (C:\\x\\y -> /c/x/y)."""
    text = str(path).replace("\\", "/")
    return re.sub(r"^([A-Za-z]):", lambda m: "/" + m.group(1).lower(), text)


class EndToEndTest(unittest.TestCase):
    """The commands an agent runs: the launch line and `wait` through the runner's wrappers, in each shell."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="prime wait "))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.env = {**os.environ, "PYTHON_BIN": sys.executable}

    def bash(self, script: str) -> subprocess.CompletedProcess[str]:
        bash = git_bash()
        if bash is None:
            self.skipTest("no Git Bash or bash")
        return subprocess.run(
            [bash, "-c", script], capture_output=True, text=True, encoding="utf-8", env=self.env, timeout=60, cwd=ROOT
        )

    def test_git_bash_launch_line_and_wait(self) -> None:
        log = self.tmp / "verify-1.log"
        shown = msys(log) if IS_WINDOWS else str(log)
        res = self.bash(f'L="{shown}"; (echo "verify summary"; exit 3) > "$L" 2>&1; echo "exit=$?" >> "$L"; '
                        'tools/run.sh wait "$L" --max 5')  # fmt: skip
        self.assertEqual(res.returncode, 3, res.stdout + res.stderr)
        self.assertIn("finished: exit=3", res.stdout)
        self.assertTrue(res.stdout.startswith("verify summary"), res.stdout)
        running = self.tmp / "verify-2.log"
        running.write_text("verify: two lanes at once\n", encoding="utf-8")
        started = time.monotonic()
        res = self.bash(f'tools/run.sh wait "{msys(running) if IS_WINDOWS else running}" --max 1')
        self.assertEqual(res.returncode, wait.STILL_RUNNING, res.stdout + res.stderr)
        self.assertLess(time.monotonic() - started, 20)
        self.assertIn("wait: still running after 1 s", res.stdout)

    @unittest.skipUnless(IS_WINDOWS, "cmd and PowerShell 5.1 are Windows shells")
    def test_powershell_and_cmd(self) -> None:
        done = self.tmp / "verify-1.log"
        done.write_text("verify summary\nverify: passed in 1.0s\nexit=0\n", encoding="utf-8")
        running = self.tmp / "verify-2.log"
        running.write_text("verify: two lanes at once\n", encoding="utf-8")
        run_cmd = str(ROOT / "tools" / "run.cmd")
        for log, want in ((done, 0), (running, wait.STILL_RUNNING)):
            with self.subTest(shell="cmd", log=log.name):
                res = subprocess.run(
                    ["cmd", "/c", run_cmd, "wait", str(log), "--max", "1"],
                    capture_output=True, text=True, encoding="utf-8", env=self.env, timeout=60,
                )  # fmt: skip
                self.assertEqual(res.returncode, want, res.stdout + res.stderr)
            # PowerShell 5.1's -Command exits by $?, so the script passes the native exit code on itself. The Git
            # Bash form of the path, as an agent may paste it, works too.
            for form in (str(log), msys(log)):
                with self.subTest(shell="powershell", log=log.name, form=form):
                    command = f"& '{run_cmd}' wait '{form}' --max 1; exit $LASTEXITCODE"
                    res = subprocess.run(
                        ["powershell", "-NoProfile", "-NonInteractive", "-Command", command],
                        capture_output=True, text=True, encoding="utf-8", errors="replace", env=self.env, timeout=60,
                    )  # fmt: skip
                    self.assertEqual(res.returncode, want, res.stdout + res.stderr)
                    self.assertIn("wait: ", res.stdout)


class OwnRepo(guard.NoRepo):
    def github_repo(self) -> str | None:
        return "xperiaroco2/prime-game"


class NoPromptTest(unittest.TestCase):
    def test_the_bounded_wait_commands_run_without_a_prompt(self) -> None:
        # The unattended-work ADR: a background verify and its polling must not ask, outside bypass too.
        wt = "/d/prime-game/.claude/worktrees/7"
        log = "/c/Users/u/AppData/Local/Temp/claude/D--prime-game/x/scratchpad/a7/verify-1.log"
        calls = [("Bash", f'cd {wt} && tools/run.sh {job} > {log} 2>&1; echo "exit=$?" >> {log}')
                 for job in ("verify", "publish", "publish --base release/m5", "mutants a.json")]  # fmt: skip
        calls += [
            ("Bash", f"cd {wt} && tools/run.sh wait {log}"),
            ("Bash", f"cd {wt} && tools/run.sh wait {log} --max 200"),
            ("PowerShell", f"Set-Location D:/prime-game/.claude/worktrees/7; tools\\run.cmd wait {log}"),
            ("Bash", f"cd {wt} && timeout 240 gh pr checks 12 --watch --interval 30; echo rc=$?"),
            ("Bash", f"cd {wt} && tools/run.sh wait --verified"),
            ("PowerShell", "Set-Location D:/prime-game/.claude/worktrees/7; tools\\run.cmd wait --verified"),
        ]
        for tool, command in calls:
            with self.subTest(tool=tool, command=command):
                got = permissions.verdict(RULES, guard, tool, command, str(ROOT), MAIN, OwnRepo(), bypass=False)
                self.assertEqual(got[0], permissions.PASS, got[1])


if __name__ == "__main__":
    unittest.main()
