"""`verify`: doctor, then the Python, the Godot and the selftest-godot lane at once (#179, #556) with the headless ENet
(#45), freeze (#70), stall (#95), bots (#102), chaos (#188) and game (#149) runs in the Godot lane: their place,
arguments and port (the game step's command lines: test_hostjoin.GameCheckTest); the steps that wait for other lanes'
steps (AFTER) and `--fail-fast` (#556); each step's output whole, the summary, the history record; and `selftest` in
worker processes, counted against a serial discovery. Lanes here are stubs: a real lane would run verify inside this
test run."""

import ast
import contextlib
import inspect
import io
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid
from collections.abc import Callable
from pathlib import Path
from unittest import mock

from runner import cli, common, metrics, slots, suspend, verify, wait
from runner.common import ROOT, Failure

GODOT_STEPS = [
    "check",
    "test",
    "enet",
    "freeze",
    "stall",
    "webrtc",
    "webrtc-freeze",
    "webrtc-stall",
    "webrtc-silence",
    "bots",
    "bots-enet",
    "bots-webrtc",
    "chaos",
    "chaos-webrtc",
    "game",
]
# The Godot lane's network runs: they start only after every other Godot run has ended (AFTER, #556).
NETWORK_STEPS = GODOT_STEPS[GODOT_STEPS.index("test") + 1 :]


def no_wait(_needed: tuple[str, ...]) -> None:
    """lane_main's wait in this process: its stdin is no parent's Gate."""


def stub_steps(record: list[str] | None = None, failing: str = "") -> contextlib.ExitStack:
    """Every step replaced by a stub that records its name and fails when it is `failing`."""

    def step(name: str) -> mock.MagicMock:
        def called(*_args: object, **_kwargs: object) -> int:
            if record is not None:
                record.append(name)
            return int(name == failing)

        return mock.MagicMock(side_effect=called)

    stack = contextlib.ExitStack()
    stack.enter_context(mock.patch.object(verify.gdunit, "LAST_RUN", None))  # no earlier test run's record
    stack.enter_context(mock.patch.object(verify.check, "_exit_crashes", 0))  # nor an earlier check's crash count
    for target, attribute, name in (
        (verify.doctor, "main", "doctor"),
        (verify.lint, "main", "lint"),
        (verify.signalling, "main", "signal"),
        (verify.check, "main", "check"),
        (verify.gdunit, "main", "test"),
        (verify, "enet", "enet"),
        (verify, "freeze", "freeze"),
        (verify, "stall", "stall"),
        (verify, "webrtc", "webrtc"),
        (verify, "webrtc_freeze", "webrtc-freeze"),
        (verify, "webrtc_stall", "webrtc-stall"),
        (verify, "webrtc_silence", "webrtc-silence"),
        (verify, "bots_one_process", "bots"),
        (verify, "bots_enet", "bots-enet"),
        (verify, "bots_webrtc", "bots-webrtc"),
        (verify, "chaos", "chaos"),
        (verify, "chaos_webrtc", "chaos-webrtc"),
        (verify, "game", "game"),
    ):
        stack.enter_context(mock.patch.object(target, attribute, step(name)))
    selftest = step("selftest")
    stack.enter_context(
        mock.patch.object(
            verify, "selftest", side_effect=lambda group: selftest() if group == "python" else step("selftest-godot")()
        )
    )
    return stack


_INLINE = threading.Lock()


def inline_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
    """A lane in this process: lane_main's printed output through the LaneReader, as run_lane_process reads it."""
    with _INLINE:  # one lane at a time: redirect_stdout swaps sys.stdout for every thread
        with contextlib.redirect_stdout(io.StringIO()) as out:
            verify.lane_main(lane, wait=no_wait, names=names)
        reader = verify.LaneReader(lane, names, emit)
        for line in out.getvalue().splitlines(keepends=True):
            reader.feed(line)
        reader.close("ended")


def fake_lane(statuses: dict[str, str] | None = None, delays: dict[str, float] | None = None) -> verify.RunLane:
    """A lane that reports each step with the given status after the given delay, without running anything."""

    def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
        for name in names:
            time.sleep((delays or {}).get(name, 0.0))
            status = (statuses or {}).get(name, "passed")
            emit(verify.StepRun(name, lane, status, 1.0, f"{name} line 1\n{name} line 2\n"))

    return run_lane


class Verify:
    """main() with a stubbed doctor, clean tree, count check and history; returns its rc, printed text and record."""

    def __init__(self, test: unittest.TestCase) -> None:
        self.test = test
        tmp = tempfile.TemporaryDirectory()
        test.addCleanup(tmp.cleanup)
        self.history = Path(tmp.name) / "verify-history.jsonl"
        self.logs = Path(tmp.name) / "out" / "logs"

    def run(
        self,
        run_lane: verify.RunLane,
        *,
        doctor: int | Callable[..., int] = 0,
        status: object = None,
        counted: tuple[list[str], str] = ([], "runner tests: 2 run and 0 skipped of 2; a serial run: 2 run of 2"),
        pool: slots.Pool | None = None,
        full: bool = True,
        fail_fast: bool = False,
        watch: object = None,
        verbose: bool = True,
    ) -> tuple[int, str, dict[str, object]]:
        """verbose: the whole output, as before #572 (these tests read every step's lines); a quiet run's log goes to
        self.logs, never this checkout's tools/out."""
        out = io.StringIO()
        with (
            mock.patch.object(verify, "slot_pool", return_value=(pool, "no limit (a test)")) as self.slot_pool,
            mock.patch.object(
                verify.doctor, "main", **({"side_effect": doctor} if callable(doctor) else {"return_value": doctor})
            ),
            mock.patch.object(verify, "git_status", side_effect=status if status is not None else [set(), set()]),
            mock.patch.object(
                verify, "count_after_lanes", return_value=(*counted, {"run": 2, "skipped": 0})
            ) as self.count,
            mock.patch.object(
                verify, "git_facts", return_value={"branch": "b", "head": "h", "tree": "t", "runner": "r"}
            ),
            mock.patch.object(verify, "HISTORY", self.history),
            mock.patch.object(common, "LOGS", self.logs),
            mock.patch.object(common, "OUT", self.logs.parent),
            mock.patch.dict(os.environ),
            contextlib.redirect_stdout(out),
        ):
            no_watch = lambda _on_suspend, _stop: None  # noqa: E731 - a run without a suspend
            rc = verify.main(  # type: ignore[arg-type]
                run_lane=run_lane, full=full, fail_fast=fail_fast, watch=watch or no_watch, verbose=verbose
            )
        lines = self.history.read_text(encoding="utf-8").splitlines()
        self.test.assertEqual(len(lines), 1, lines)
        return rc, out.getvalue(), json.loads(lines[0])


def summary_rows(text: str) -> list[tuple[str, str]]:
    rows = text[text.rindex("verify summary") :].splitlines()[1:]
    return [(row.split()[0], row.split()[1]) for row in rows if row.split()[0] in ("passed", "FAILED")]


class LaneTest(unittest.TestCase):
    def test_every_step_has_one_lane_and_the_network_runs_stay_serial_in_one(self) -> None:
        self.assertEqual(verify.LANES["python"], ("lint", "signal", "selftest"))
        self.assertEqual(list(verify.LANES["godot"]), GODOT_STEPS)
        self.assertEqual(verify.LANES["selftest-godot"], ("selftest-godot",))
        in_lanes = [name for names in verify.LANES.values() for name in names]
        self.assertEqual(sorted(["doctor", *in_lanes]), sorted(verify.STEP_ORDER))
        self.assertEqual(set(verify.steps()), set(verify.STEP_ORDER))

    def test_no_other_godot_run_overlaps_a_network_run(self) -> None:
        # #556: the runner tests that start Godot run beside `test`, after `check`'s import; the first network run
        # waits for them, and every network run follows it in the one Godot lane, after check and test.
        self.assertEqual(verify.AFTER["selftest-godot"], ("check",))
        self.assertEqual(verify.AFTER[NETWORK_STEPS[0]], ("selftest-godot",))
        self.assertEqual(set(verify.AFTER), {"selftest-godot", NETWORK_STEPS[0]})
        godot = verify.LANES["godot"]
        self.assertEqual(godot[: godot.index(NETWORK_STEPS[0])], ("check", "test"))
        lane_of = {name: lane for lane, names in verify.LANES.items() for name in names}
        for step, needed in verify.AFTER.items():
            for name in needed:
                self.assertNotEqual(lane_of[name], lane_of[step], "a step of its own lane has ended anyway")

    def test_each_lane_runs_its_steps_in_order_each_after_its_steps_of_other_lanes(self) -> None:
        for lane, names in verify.LANES.items():
            ran: list[str] = []

            def wait(needed: tuple[str, ...]) -> None:
                ran.append(f"wait {','.join(needed)}")

            with self.subTest(lane=lane), stub_steps(ran), contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(verify.lane_main(lane, wait=wait), 0)
            expected = []
            for name in names:
                expected += [f"wait {','.join(verify.AFTER.get(name, ()))}", name]
            self.assertEqual(ran, expected)
            marks = [
                json.loads(line[len(verify.MARK) :])
                for line in out.getvalue().splitlines()
                if line.startswith(verify.MARK)
            ]
            self.assertEqual([m["step"] for m in marks], list(names))

    def test_the_lanes_run_at_once(self) -> None:
        started = threading.Barrier(len(verify.LANES), timeout=10)

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            started.wait()  # breaks after 10 s unless the other lane runs at the same time
            fake_lane()(lane, names, emit)

        rc, _text, _record = Verify(self).run(run_lane)
        self.assertEqual(rc, 0)

    def test_a_failed_step_of_either_lane_fails_verify_and_the_others_still_run(self) -> None:
        for failing in ("lint", "signal", "selftest", "selftest-godot", *GODOT_STEPS):
            ran: list[str] = []
            with self.subTest(failing=failing), stub_steps(ran, failing):
                rc, text, record = Verify(self).run(inline_lane)
                self.assertEqual(rc, 1)
                self.assertEqual(sorted(ran), sorted(set(verify.STEP_ORDER) - {"doctor"}))
                self.assertEqual([name for status, name in summary_rows(text) if status == "FAILED"], [failing])
                self.assertEqual(len(summary_rows(text)), len(verify.STEP_ORDER))
                self.assertEqual(record["status"], "FAILED")

    def test_a_red_doctor_stops_everything(self) -> None:
        lane = mock.MagicMock()
        rc, text, record = Verify(self).run(lane, doctor=1)
        self.assertEqual(rc, 1)
        lane.assert_not_called()
        self.assertEqual(summary_rows(text), [("FAILED", "doctor")])
        self.assertEqual([s["name"] for s in record["steps"]], ["doctor"])  # type: ignore[union-attr]

    def test_the_summary_keeps_the_serial_order_and_each_lane_wall_time(self) -> None:
        # The Python lane ends first and the Godot lane's steps end in their own order: the summary is still in order.
        rc, text, record = Verify(self).run(fake_lane(delays={"check": 0.05, "lint": 0.0}))
        self.assertEqual(rc, 0)
        self.assertEqual([name for _status, name in summary_rows(text)], list(verify.STEP_ORDER))
        lanes = next(line for line in text.splitlines() if line.strip().startswith("lanes:"))
        self.assertRegex(
            lanes,
            r"lanes: python [\d.]+s, godot [\d.]+s, selftest-godot [\d.]+s; \d+ CPUs, selftest on \d+ worker processes",
        )
        self.assertIn("runner tests: 2 run and 0 skipped of 2", text)
        self.assertRegex(text.splitlines()[-1], r"^verify: passed in [\d.]+s$")
        self.assertEqual(list(record["lanes"]), list(verify.LANES))  # type: ignore[arg-type]
        self.assertEqual(record["mode"], "full")
        self.assertNotIn(verify.FAST_LINE, text)

    def test_each_steps_output_is_printed_whole(self) -> None:
        delays = {name: 0.01 for name in verify.STEP_ORDER}
        _rc, text, _record = Verify(self).run(fake_lane(delays=delays))
        lines = text.splitlines()
        for name in verify.STEP_ORDER[1:]:
            at = lines.index(f"{name} line 1")
            self.assertTrue(lines[at - 1].startswith(f"== {name} ("), lines[at - 1])
            self.assertEqual(lines[at + 1], f"{name} line 2")

    def test_the_clean_tree_check_runs_after_both_lanes(self) -> None:
        ended: list[str] = []

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            fake_lane()(lane, names, emit)
            ended.append(lane)

        def status() -> set[str]:
            calls.append(sorted(ended))
            return set() if len(calls) == 1 else {"?? left.txt"}

        calls: list[list[str]] = []
        rc, text, record = Verify(self).run(run_lane, status=status)
        self.assertEqual(calls, [[], sorted(verify.LANES)])
        self.assertEqual(rc, 1)
        self.assertIn(("FAILED", "clean"), summary_rows(text))
        self.assertIsNotNone(record)

    def test_a_count_that_differs_from_a_serial_run_fails_verify(self) -> None:
        counted = (["1 runner tests never ran: x"], "runner tests: ...")
        rc, text, _record = Verify(self).run(fake_lane(), counted=counted)
        self.assertEqual(rc, 1)
        self.assertIn(("FAILED", "selftest-count"), summary_rows(text))
        self.assertIn("1 runner tests never ran: x", text)

    def test_a_lane_that_crashes_fails_its_unreported_steps(self) -> None:
        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            if lane == "godot":
                emit(verify.StepRun("check", lane, "passed", 1.0))
                raise OSError("no such file")
            fake_lane()(lane, names, emit)

        rc, text, _record = Verify(self).run(run_lane)
        self.assertEqual(rc, 1)
        rows = dict((name, status) for status, name in summary_rows(text))
        self.assertEqual(rows["check"], "passed")
        self.assertEqual([rows[name] for name in GODOT_STEPS[1:]], ["FAILED"] * (len(GODOT_STEPS) - 1))
        self.assertIn("the godot lane crashed", text)

    def test_a_crashed_lanes_message_waits_for_the_step_being_printed(self) -> None:
        printing = threading.Lock()
        held: list[bool] = []

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            if lane == "godot":
                raise OSError("no such file")

        with mock.patch.object(verify, "bad", side_effect=lambda *_args: held.append(printing.locked())):
            verify.run_lanes(run_lane, lambda _step: None, printing)
        self.assertEqual(held, [True])

    def test_the_history_record(self) -> None:
        rc, _text, record = Verify(self).run(fake_lane())
        self.assertEqual(rc, 0)
        self.assertEqual(
            set(record),
            {"start", "worktree", "branch", "head", "tree", "runner", "status", "seconds", "steps", "lanes", "cpus",
             "workers", "selftest", "slot", "stopped", "mode"},  # fmt: skip
        )
        self.assertIsNone(record["slot"])  # no slot pool: CI, or a verify inside a verify
        self.assertIsNone(record["stopped"])  # every step ran
        self.assertRegex(str(record["start"]), r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertEqual(record["worktree"], ROOT.as_posix())
        self.assertEqual((record["branch"], record["tree"], record["runner"]), ("b", "t", "r"))
        self.assertEqual(record["cpus"], os.cpu_count())
        steps = record["steps"]
        assert isinstance(steps, list)
        self.assertEqual([s["name"] for s in steps], list(verify.STEP_ORDER))
        self.assertEqual({s["lane"] for s in steps if s["name"] in GODOT_STEPS}, {"godot"})
        doctor = {"name": "doctor", "lane": "main", "status": "passed", "seconds": steps[0]["seconds"]}
        self.assertEqual(steps[0], doctor)
        self.assertEqual(record["selftest"], {"run": 2, "skipped": 0})

    def test_the_tree_hash_only_with_a_clean_tree(self) -> None:
        def git(*args: str) -> mock.MagicMock:
            return mock.MagicMock(rc=0, out={"--abbrev-ref": "tooling/1-x\n"}.get(args[1], f"{args[-1]}-hash\n"))

        with mock.patch.object(verify, "git", side_effect=git):
            clean = verify.git_facts(clean=True)
            dirty = verify.git_facts(clean=False)
        self.assertEqual(clean, {"branch": "tooling/1-x", "head": "HEAD-hash", "tree": "HEAD^{tree}-hash",
                                 "runner": "HEAD:tools/runner-hash"})  # fmt: skip
        self.assertIsNone(dirty["tree"])

    def test_a_lane_step_that_raises_is_red_and_the_lane_goes_on(self) -> None:
        with (
            stub_steps(),
            mock.patch.object(verify.check, "main", side_effect=Failure("no Godot")),
            mock.patch.object(verify, "enet", side_effect=RuntimeError("bug")),
            contextlib.redirect_stdout(io.StringIO()) as out,
        ):
            verify.lane_main("godot", wait=no_wait)
        marks = {
            m["step"]: m["rc"]
            for m in (
                json.loads(line[len(verify.MARK) :])
                for line in out.getvalue().splitlines()
                if line.startswith(verify.MARK)
            )
        }
        self.assertEqual(list(marks), GODOT_STEPS)
        self.assertEqual((marks["check"], marks["enet"], marks["test"]), (1, 1, 0))
        self.assertIn("FAIL  no Godot", out.getvalue())
        self.assertIn("RuntimeError: bug", out.getvalue())


# A red `bots-enet` as `bots.main` prints it over ENet (the #284 case): the FAIL line, then each instance's report.
BOTS_ENET_OUT = """bots
  ok    bots_main #1: exit 0 in 41.0s, no engine errors (log: tools/out/logs/run/bots_main-1.log)
  FAIL  bots_main #2: exited 1 (log: tools/out/logs/run/bots_main-2.log)
run: FAILED (1 of 3)
  #2 BOTS dissident_kills_the_crew: FAILED (seed 7) 41.2s
  #2   a Correction outside a placement (epoch 3, at (1.5, 0, -2)): an honest bot is never corrected
  #2   command log (Match.replay with ReplayFiles.read): user://x.log
"""


class FastTest(unittest.TestCase):
    """`verify` with no flag (#605): doctor, lint and check, the clean-tree check; no test, no slot, no count check."""

    def test_the_default_is_the_fast_run(self) -> None:
        self.assertIs(inspect.signature(verify.main).parameters["full"].default, False)
        self.assertEqual(verify.FAST_LANES, {"python": ("lint",), "godot": ("check",)})
        self.assertEqual(verify.FAST_ORDER, ("doctor", "lint", "check"))

    def test_it_runs_only_lint_and_check_and_says_the_tests_run_on_ci(self) -> None:
        ran: list[str] = []
        run = Verify(self)
        with stub_steps(ran):
            rc, text, record = run.run(inline_lane, full=False)
        self.assertEqual(rc, 0)
        self.assertEqual(sorted(ran), ["check", "lint"])  # doctor: the stub in Verify
        self.assertEqual(summary_rows(text), [("passed", "doctor"), ("passed", "lint"), ("passed", "check")])
        self.assertIn(f"  {verify.FAST_LINE}", text.splitlines())
        self.assertRegex(text.splitlines()[-1], r"^verify: passed in [\d.]+s$")
        run.slot_pool.assert_not_called()  # no verify slot
        run.count.assert_not_called()  # no runner test ran, so none is counted
        self.assertEqual(record["mode"], "fast")
        self.assertEqual(record["status"], "passed")
        self.assertEqual(list(record["lanes"]), list(verify.FAST_LANES))  # type: ignore[arg-type]
        self.assertEqual([s["name"] for s in record["steps"]], list(verify.FAST_ORDER))  # type: ignore[union-attr]
        self.assertIsNone(record["slot"])

    def test_the_full_run_runs_every_step(self) -> None:
        ran: list[str] = []
        with stub_steps(ran):
            rc, text, record = Verify(self).run(inline_lane, full=True)
        self.assertEqual(rc, 0)
        self.assertEqual(sorted(ran), sorted(set(verify.STEP_ORDER) - {"doctor"}))
        self.assertEqual([name for _status, name in summary_rows(text)], list(verify.STEP_ORDER))
        self.assertEqual(record["mode"], "full")

    def test_a_red_lint_or_check_fails_it_and_the_other_still_runs(self) -> None:
        for failing in ("lint", "check"):
            ran: list[str] = []
            with self.subTest(failing=failing), stub_steps(ran, failing):
                rc, text, record = Verify(self).run(inline_lane, full=False)
                self.assertEqual(rc, 1)
                self.assertEqual(sorted(ran), ["check", "lint"])  # doctor: the stub in Verify
                self.assertEqual([name for status, name in summary_rows(text) if status == "FAILED"], [failing])
                self.assertEqual((record["status"], record["mode"]), ("FAILED", "fast"))

    def test_it_keeps_the_clean_tree_check(self) -> None:
        rc, text, _record = Verify(self).run(fake_lane(), status=[set(), {"?? left.txt"}], full=False)
        self.assertEqual(rc, 1)
        self.assertIn(("FAILED", "clean"), summary_rows(text))

    def test_a_red_doctor_stops_it(self) -> None:
        lane = mock.MagicMock()
        rc, text, _record = Verify(self).run(lane, doctor=1, full=False)
        self.assertEqual(rc, 1)
        lane.assert_not_called()
        self.assertEqual(summary_rows(text), [("FAILED", "doctor")])

    def test_a_lane_process_runs_only_the_fast_steps(self) -> None:
        self.assertNotIn("names=", " ".join(verify.lane_command("python")))
        self.assertNotIn("names=", " ".join(verify.lane_command("python", verify.LANES["python"])))
        self.assertIn("names=('lint',)", " ".join(verify.lane_command("python", ("lint",))))
        ran: list[str] = []
        with stub_steps(ran), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(verify.lane_main("godot", wait=no_wait, names=("check",)), 0)
        self.assertEqual(ran, ["check"])


def red_lane(outputs: dict[str, str]) -> verify.RunLane:
    """A lane that reports each step red with the given output when it has one, else passed with two lines."""

    def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
        for name in names:
            if name in outputs:
                emit(verify.StepRun(name, lane, "FAILED", 1.0, outputs[name]))
            else:
                emit(verify.StepRun(name, lane, "passed", 1.0, f"{name}\n  ok    {name} line 1\n{name}: passed\n"))

    return run_lane


RED_LINT = "lint\n  ok    gdformat (709 files)\n  FAIL  core/a.gd:5: Error: a bad name (function-variable-name)\nlint: FAILED\n"


class QuietTest(unittest.TestCase):
    """Quiet by default (#572): the whole output in tools/out/logs/verify-output.log, the terminal only each red step's
    failure lines and the summary block, the exit code and the red step's name always; --verbose as before."""

    def log(self, run: Verify) -> str:
        return (run.logs / "verify-output.log").read_text(encoding="utf-8")

    def where(self, run: Verify) -> str:
        """The footer naming the log: in a temporary folder here, tools/out/logs/verify-output.log for real."""
        return common.where_line(run.logs / "verify-output.log")

    def test_a_green_run_prints_only_its_summary_block_with_the_log_path(self) -> None:
        run = Verify(self)
        rc, text, record = run.run(red_lane({}), full=False, verbose=False)
        self.assertEqual(rc, 0)
        lines = text.splitlines()
        self.assertEqual(lines[0], "verify summary")
        self.assertEqual(lines[-1].split(" in ")[0], "verify: passed")
        self.assertEqual(lines[-2], f"  {self.where(run)}")
        self.assertTrue(self.where(run).startswith("full output: ") and self.where(run).endswith("prints it all)"))
        self.assertEqual(summary_rows(text), [("passed", "doctor"), ("passed", "lint"), ("passed", "check")])
        self.assertLessEqual(len(text.encode()), common.SUCCESS_CAP)
        self.assertNotIn("lint line 1", text)
        log = self.log(run)
        self.assertIn("  ok    lint line 1", log)  # every step's whole output, and the summary too
        self.assertIn("verify: 2 lanes at once", log)
        self.assertTrue(log.rstrip().endswith(lines[-1]))
        self.assertEqual(record["status"], "passed")

    def test_a_red_step_prints_its_name_and_failure_lines_before_the_summary_never_its_ok_lines(self) -> None:
        run = Verify(self)
        rc, text, record = run.run(red_lane({"lint": RED_LINT}), full=False, verbose=False)
        self.assertEqual(rc, 1)
        head, summary = text.split("verify summary\n")
        self.assertEqual(head.splitlines(), [
            "== lint (python lane, 1.0s, FAILED)",
            "  FAIL  core/a.gd:5: Error: a bad name (function-variable-name)",
        ])  # fmt: skip
        self.assertIn(("FAILED", "lint"), summary_rows(text))
        self.assertTrue(summary.rstrip().splitlines()[-1].startswith("verify: FAILED in "))
        self.assertIn("gdformat (709 files)", self.log(run))
        failure = record["steps"][1]["failure"]  # type: ignore[index]
        self.assertEqual(failure, "core/a.gd:5: Error: a bad name (function-variable-name)")

    def test_red_excerpts_share_about_4_kb_and_each_red_step_still_shows_its_first_lines(self) -> None:
        many = "check\n" + "".join(f"  FAIL  res://a.gd:{n}: Parse Error: x\n" for n in range(400)) + "check: FAILED\n"
        run = Verify(self)
        rc, text, _record = run.run(red_lane({"check": many, "lint": RED_LINT}), full=False, verbose=False)
        self.assertEqual(rc, 1)
        head = text.split("verify summary\n")[0]
        self.assertIn("== check (godot lane, 1.0s, FAILED)", head)
        self.assertIn("== lint (python lane, 1.0s, FAILED)", head)
        self.assertIn("  FAIL  core/a.gd:5: Error: a bad name", head)
        self.assertIn("  FAIL  res://a.gd:0: Parse Error: x", head)
        self.assertRegex(head, r"\.\.\. \d+ more lines; " + re.escape(self.where(run)))
        self.assertLessEqual(len(head.encode()), common.FAILURE_CAP + verify.EXCERPT_MIN)
        self.assertIn("  FAIL  res://a.gd:399: Parse Error: x", self.log(run))

    def test_a_red_doctor_prints_its_failure_lines(self) -> None:
        def doctor(**_kwargs: object) -> int:
            common.say("doctor --quick")
            common.ok("Python 3.14")
            common.bad("Godot 4.6 found, 4.7.2 pinned")
            return 1

        run = Verify(self)
        rc, text, _record = run.run(mock.MagicMock(), doctor=doctor, full=False, verbose=False)
        self.assertEqual(rc, 1)
        self.assertEqual(text.split("verify summary\n")[0].splitlines(),
                         ["== doctor (FAILED)", "  FAIL  Godot 4.6 found, 4.7.2 pinned"])  # fmt: skip
        self.assertEqual(summary_rows(text), [("FAILED", "doctor")])

    def test_a_second_run_keeps_the_first_runs_whole_output_as_prev(self) -> None:
        """merge-train retries a red verify in the same worktree (#572 review): attempt 1's output must survive."""
        run = Verify(self)
        run.run(red_lane({"lint": RED_LINT}), full=False, verbose=False)
        first = self.log(run)
        run.history.unlink()  # the helper reads one record per run
        run.run(red_lane({}), full=False, verbose=False)
        self.assertEqual((run.logs / "verify-output.prev.log").read_text(encoding="utf-8"), first)
        self.assertIn("  FAIL  core/a.gd:5", first)
        self.assertNotIn("  FAIL  core/a.gd:5", self.log(run))
        self.assertIsNone(verify._SPLIT)

    def test_a_nested_quiet_run_restores_the_outer_split(self) -> None:
        outer = mock.sentinel.outer
        with mock.patch.object(verify, "_SPLIT", outer):
            run = Verify(self)
            run.run(red_lane({}), full=False, verbose=False)
            self.assertIs(verify._SPLIT, outer)

    def test_a_dirty_tree_after_the_run_prints_the_files_it_left(self) -> None:
        run = Verify(self)
        rc, text, _record = run.run(red_lane({}), status=[set(), {"?? left.txt"}], full=False, verbose=False)
        self.assertEqual(rc, 1)
        self.assertEqual(text.split("verify summary\n")[0].splitlines(), [
            "== clean tree (FAILED)",
            "  FAIL  verify left new or changed files in the working tree:",
            "        -> ?? left.txt",
        ])  # fmt: skip

    def test_a_red_count_check_prints_its_problems(self) -> None:
        run = Verify(self)
        counted = (["test_x.T.test_y ran twice"], "runner tests: 2 run")
        rc, text, _record = run.run(red_lane({}), counted=counted, verbose=False)
        self.assertEqual(rc, 1)
        self.assertIn("== selftest-count (FAILED)\n  FAIL  test_x.T.test_y ran twice\n", text)

    def test_metrics_and_wait_read_a_quiet_runs_summary(self) -> None:
        run = Verify(self)
        rc, text, _record = run.run(red_lane({"lint": RED_LINT}), full=False, verbose=False)
        parsed = metrics.parse_verify(text)
        assert parsed is not None
        self.assertEqual((parsed["status"], parsed["steps"]["lint"][0], parsed.get("fast")), ("FAILED", "FAILED", True))
        report = wait.quiet_report([*text.splitlines(), f"exit={rc}"], rc, "x.log")
        self.assertIn(f"  {self.where(run)}", report)
        self.assertIn("  FAIL  core/a.gd:5: Error: a bad name (function-variable-name)", report)

    def test_an_exception_prints_the_log_path_and_goes_on_up(self) -> None:
        def crash(_lane: str, _names: tuple[str, ...], _emit: verify.Emit) -> None:
            raise KeyboardInterrupt

        run = Verify(self)
        out = io.StringIO()
        with (
            mock.patch.object(verify, "run_lanes", side_effect=KeyboardInterrupt),
            mock.patch.object(verify.doctor, "main", return_value=0),
            mock.patch.object(verify, "git_status", return_value=set()),
            mock.patch.object(verify, "git_facts", return_value={}),
            mock.patch.object(common, "LOGS", run.logs),
            mock.patch.object(common, "OUT", run.logs.parent),
            contextlib.redirect_stdout(out),
            self.assertRaises(KeyboardInterrupt),
        ):
            verify.main(crash, watch=lambda _on, _stop: None)
        self.assertEqual(out.getvalue().splitlines()[-1], f"verify: stopped by KeyboardInterrupt; {self.where(run)}")

    def test_verbose_prints_every_steps_output_as_before(self) -> None:
        _rc, text, _record = Verify(self).run(red_lane({}), full=False, verbose=True)
        self.assertIn("  ok    lint line 1", text)
        self.assertNotIn("full output:", text)

    def test_the_cli_is_quiet_unless_verbose_or_on_ci(self) -> None:
        with mock.patch.object(verify, "main", return_value=0) as main, mock.patch.object(common, "IS_CI", False):
            cli.main(["verify"])
            cli.main(["verify", "--verbose"])
        with mock.patch.object(verify, "main", return_value=0) as on_ci, mock.patch.object(common, "IS_CI", True):
            cli.main(["verify", "--full"])
        self.assertEqual([c.kwargs["verbose"] for c in main.call_args_list], [False, True])
        self.assertTrue(on_ci.call_args.kwargs["verbose"])  # CI's job log is the whole output (the PC has the log)


class HistoryDetailTest(unittest.TestCase):
    """What the history record keeps of a red step (#273): `test`'s processes and failing tests, every red step's
    first failure line; a green step keeps its four fields (and `test` its processes)."""

    def test_the_test_steps_processes_and_failing_tests_reach_the_record_through_the_lane(self) -> None:
        detail = {"shards": [{"shard": 1, "rc": 0, "seconds": 80.0},
                             {"shard": 2, "rc": 3221225477, "seconds": 12.5, "results": False}],
                  "failed_tests": [{"test": "a_test::test_one", "message": "Expecting: 1 but was 2"}]}  # fmt: skip

        def red_test(**_kwargs: object) -> int:
            verify.gdunit.LAST_RUN = detail  # what gdunit.main leaves
            common.bad("shard 2: GdUnit4 crashed or exited unexpectedly (exit 3221225477); log: x.log")
            return 1

        with stub_steps(), mock.patch.object(verify.gdunit, "main", side_effect=red_test):
            rc, _text, record = Verify(self).run(inline_lane)
        self.assertEqual(rc, 1)
        steps = {s["name"]: s for s in record["steps"]}  # type: ignore[union-attr]
        self.assertEqual(steps["test"], {
            "name": "test", "lane": "godot", "status": "FAILED", "seconds": steps["test"]["seconds"], **detail,
            "failure": "shard 2: GdUnit4 crashed or exited unexpectedly (exit 3221225477); log: x.log"})  # fmt: skip
        self.assertEqual(set(steps["enet"]), {"name", "lane", "status", "seconds"})
        self.assertIsNone(verify.gdunit.LAST_RUN, "taken by the lane")

    def test_a_mark_carries_the_detail_and_a_broken_detail_is_left_out(self) -> None:
        steps: list[verify.StepRun] = []
        reader = verify.LaneReader("godot", ("test", "enet"), steps.append)
        reader.feed(f'{verify.MARK}{{"step": "test", "rc": 0, "seconds": 1, "detail": {{"shards": []}}}}\n')
        reader.feed(f'{verify.MARK}{{"step": "enet", "rc": 0, "seconds": 1, "detail": [1]}}\n')
        self.assertEqual([s.detail for s in steps], [{"shards": []}, {}])

    def test_only_the_test_and_check_steps_have_a_detail(self) -> None:
        with (
            stub_steps(),
            mock.patch.object(verify.gdunit, "take_last_run", return_value={"shards": []}) as taken,
            contextlib.redirect_stdout(io.StringIO()) as out,
        ):
            verify.lane_main("godot", wait=no_wait)
        marks = [json.loads(line[len(verify.MARK) :]) for line in out.getvalue().splitlines()
                 if line.startswith(verify.MARK)]  # fmt: skip
        # `check` carries its `exit_crash` flag (#449), `test` its shards; no other step has a detail
        self.assertEqual([m["step"] for m in marks if "detail" in m], ["check", "test"])
        self.assertEqual(next(m for m in marks if m["step"] == "check")["detail"], {"exit_crash": False})
        taken.assert_called_once()

    def test_a_red_steps_first_failure_line(self) -> None:
        enet = ("  FAIL  enet_host_and_two_clients #1: exited 1 (log: tools/out/logs/run/x-1.log)\n"
                "        -> ERROR: NET instance 1 FAIL: no Welcome within 10 s\n"
                "        ->    at: push_error (core/variant/variant_utility.cpp:1024)\n")  # fmt: skip
        one_process = ("BOTS refusals: FAILED (seed 1) 2.0s\n  the host accepted a vote of a downed player\n"
                       "  FAIL  bots_main #1: exited 1 (log: tools/out/logs/run/bots_main-1.log)\n")  # fmt: skip
        # A runner test's traceback can echo an engine-like line; only the steps that run the game look for a reason.
        traceback = ("selftest\n  FAIL  runner.tests.test_x.T.test_y: AssertionError: 1 != 2\n"
                     "        ERROR: a fixture line the test echoed\n")  # fmt: skip
        cases = [
            ("bots-enet", BOTS_ENET_OUT, "bots_main #2: exited 1 (log: tools/out/logs/run/bots_main-2.log) | a "
             "Correction outside a placement (epoch 3, at (1.5, 0, -2)): an honest bot is never corrected"),
            ("enet", enet, "enet_host_and_two_clients #1: exited 1 (log: tools/out/logs/run/x-1.log) | "
             "ERROR: NET instance 1 FAIL: no Welcome within 10 s"),
            ("bots", one_process, "bots_main #1: exited 1 (log: tools/out/logs/run/bots_main-1.log) | "
             "the host accepted a vote of a downed player"),
            ("chaos", "CHAOS seed 188001: FAILED (timeout, 900 ms)\n", "CHAOS seed 188001: FAILED (timeout, 900 ms)"),
            ("selftest", traceback, "runner.tests.test_x.T.test_y: AssertionError: 1 != 2"),
            ("selftest-godot", traceback, "runner.tests.test_x.T.test_y: AssertionError: 1 != 2"),
            ("lint", "lint\n  ERROR: not an engine line\nlint: FAILED\n\n", "lint: FAILED"),
            ("game", "", ""),
        ]  # fmt: skip
        for step, output, line in cases:
            with self.subTest(step=step):
                self.assertEqual(verify.first_failure(step, output), line)
        long = verify.first_failure("test", "  FAIL  " + "x" * 1000)
        self.assertEqual(len(long), verify.gdunit.MESSAGE_CAP)

    def test_a_steps_refused_starts_reach_its_record_and_the_summary(self) -> None:
        # #441: the lane takes the process starts Windows refused during each step into its record, and the summary
        # adds them up in one NOT STARTED line; a step without any keeps its plain record.
        def refused(counts: tuple[int, int, int], rc: int) -> mock.MagicMock:
            def step(*_args: object, **_kwargs: object) -> int:
                common.STARTS.refused, common.STARTS.restarted, common.STARTS.recovered = counts
                if rc:
                    common.bad(f"bots_main #1: {common.start_problem(3221225794)}")
                return rc

            return mock.MagicMock(side_effect=step)

        with (
            stub_steps(),
            mock.patch.object(common, "STARTS", common.Starts()),
            mock.patch.object(verify, "enet", refused((1, 1, 1), 0)),
            mock.patch.object(verify, "bots_enet", refused((2, 1, 0), 1)),
        ):
            rc, text, record = Verify(self).run(inline_lane)
        self.assertEqual(rc, 1)
        steps = {s["name"]: s for s in record["steps"]}  # type: ignore[union-attr]
        self.assertEqual(steps["enet"]["not_started"], {"refused": 1, "restarted": 1, "recovered": 1})
        self.assertEqual(steps["bots-enet"]["not_started"], {"refused": 2, "restarted": 1, "recovered": 0})
        self.assertTrue(steps["bots-enet"]["failure"].startswith("bots_main #1: could not start: exited 3221225794"))
        self.assertNotIn("not_started", steps["freeze"])
        summary = text[text.rindex("verify summary") :]
        self.assertIn("  NOT STARTED: Windows refused 3 process start(s) (exit 3221225794, 0xC0000142) in enet, "
                      "bots-enet; 2 restarted once, 1 of them ran.", summary)  # fmt: skip
        with stub_steps(), mock.patch.object(common, "STARTS", common.Starts()):
            _rc, text, record = Verify(self).run(inline_lane)
        self.assertNotIn("NOT STARTED", text)
        self.assertFalse(any("not_started" in s for s in record["steps"]))  # type: ignore[union-attr]

    def test_a_check_that_passed_after_godot_crashed_at_exit_is_named_in_its_record_and_summary_row(self) -> None:
        # #449: the project check passes Godot's access violation at exit after a clean run (#442). The lane takes the
        # count into the check step's record, and the summary row (what publish's verify tail carries) names it.
        def crashed(*_args: object, **_kwargs: object) -> int:
            verify.check._exit_crashes += 1  # what project_check counts when it passes such a run
            return 0

        with stub_steps(), mock.patch.object(verify.check, "main", side_effect=crashed):
            rc, text, record = Verify(self).run(inline_lane)
        self.assertEqual(rc, 0)
        steps = {s["name"]: s for s in record["steps"]}  # type: ignore[union-attr]
        self.assertIs(steps["check"]["exit_crash"], True)
        self.assertEqual([name for name, step in steps.items() if "exit_crash" in step], ["check"])
        row = next(line for line in text[text.rindex("verify summary") :].splitlines() if " check " in line)
        self.assertRegex(row, r"^  passed  check +[\d.]+s  \(Godot crashed at exit, #442\)$")
        self.assertEqual(len(summary_rows(text)), len(verify.STEP_ORDER))
        parsed = metrics.parse_verify(text)  # metrics still reads every row of the summary, the noted one included
        self.assertEqual(set(parsed["steps"]), set(verify.STEP_ORDER))  # type: ignore[index]
        self.assertEqual(parsed["steps"]["check"][0], "passed")  # type: ignore[index]
        self.assertEqual(parsed["exit_crashes"], ["check"])  # type: ignore[index]
        with stub_steps():
            _rc, text, record = Verify(self).run(inline_lane)
        self.assertNotIn("crashed at exit", text)
        # a check step always says whether it crashed (false here), so metrics counts only the records that could
        self.assertEqual([s["name"] for s in record["steps"] if "exit_crash" in s], ["check"])  # type: ignore[union-attr]
        self.assertIs(next(s for s in record["steps"] if s["name"] == "check")["exit_crash"], False)  # type: ignore[union-attr]

    def test_a_check_that_crashed_at_exit_and_failed_for_another_reason_says_so_in_its_row(self) -> None:
        # #449 review: the check can be red after its project check passed the crash (warnings policy, UID lint ...);
        # the row must not suggest that the crash caused the failure.
        def crashed_then_failed(*_args: object, **_kwargs: object) -> int:
            verify.check._exit_crashes += 1
            return 1

        with stub_steps(), mock.patch.object(verify.check, "main", side_effect=crashed_then_failed):
            _rc, text, record = Verify(self).run(inline_lane)
        row = next(line for line in text[text.rindex("verify summary") :].splitlines() if " check " in line)
        self.assertRegex(row, r"^  FAILED  check +[\d.]+s  \(Godot crashed at exit, #442; red for another reason\)$")
        self.assertEqual(metrics.parse_verify(text)["steps"]["check"][0], "FAILED")  # type: ignore[index]
        self.assertIs(next(s for s in record["steps"] if s["name"] == "check")["exit_crash"], True)  # type: ignore[union-attr]

    def test_a_red_step_without_any_output_has_no_failure_field(self) -> None:
        record = verify.step_record(verify.StepRun("game", "godot", "FAILED", 1.0, ""))
        self.assertEqual(record, {"name": "game", "lane": "godot", "status": "FAILED", "seconds": 1.0})
        green = verify.step_record(verify.StepRun("game", "godot", "passed", 1.0, "  FAIL  not read when green\n"))
        self.assertNotIn("failure", green)


class SlotTest(unittest.TestCase):
    """verify takes one of the machine-wide slots (#185) after doctor, for its lanes, and records the wait."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.where = Path(tmp.name)
        self.said: list[str] = []

    def pool(self, count: int = 1, max_wait: float = 0.0, name: str = "this") -> slots.Pool:
        pool = slots.Pool(self.where, count, max_wait, me={"worktree": f"D:/wt/{name}"}, say=self.said.append)
        self.addCleanup(pool.release)
        return pool

    def test_the_lanes_run_in_a_slot_that_is_released_afterwards(self) -> None:
        held: list[bool] = []

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            held.append(self.pool(name="probe").try_take() is None)  # the slot is taken while the lanes run
            fake_lane()(lane, names, emit)

        rc, text, record = Verify(self).run(run_lane, pool=self.pool())
        self.assertEqual((rc, held), (0, [True] * len(verify.LANES)))
        self.assertEqual(record["slot"], {"slot": 1, "of": 1, "waited": 0.0, "over": False, "reclaimed": 0})
        self.assertIn("  slot: 1 of 1, waited 0.0s for a verify slot", text.splitlines())
        end = r"^verify: passed in [\d.]+s \(after [\d.]+s waiting for a verify slot\)$"
        self.assertRegex(text.splitlines()[-1], end)
        self.assertEqual(self.pool(name="next").acquire().slot, 1)

    def test_a_red_or_crashed_run_releases_its_slot(self) -> None:
        def crash(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            raise RuntimeError("the lane crashed")

        for run_lane in (fake_lane({"freeze": "FAILED"}), crash):
            with self.subTest(run_lane=run_lane), contextlib.redirect_stdout(io.StringIO()):
                rc, _text, _record = Verify(self).run(run_lane, pool=self.pool())
                self.assertEqual(rc, 1)
                after = self.pool(name="next")
                self.assertEqual(after.try_take(), (1, None))  # free, and not left behind as a stale holder
                after.release()

    def test_a_run_past_the_longest_wait_runs_every_step_over_the_limit_and_says_so(self) -> None:
        self.pool(name="busy").acquire()
        ran: list[str] = []
        with stub_steps(ran):
            rc, text, record = Verify(self).run(inline_lane, pool=self.pool(max_wait=0.0))
        self.assertEqual(rc, 0)  # over the limit is a warning, never a skipped or failed step
        self.assertEqual(sorted(ran), sorted(set(verify.STEP_ORDER) - {"doctor"}))
        self.assertEqual(record["slot"], {"slot": None, "of": 1, "waited": 0.0, "over": True, "reclaimed": 0})
        self.assertIn("ran over the limit", text)
        self.assertIn("D:/wt/busy", text)
        self.assertIn("OVER THE LIMIT", text.splitlines()[-1])
        self.assertTrue(any("OVER THE LIMIT" in line for line in self.said), self.said)

    def test_the_run_time_leaves_the_wait_out(self) -> None:
        pool = self.pool()
        pool.acquire = mock.MagicMock(return_value=slots.Taken(1, 1, 120.0))  # type: ignore[method-assign]
        _rc, text, record = Verify(self).run(fake_lane(), pool=pool)
        self.assertEqual(record["slot"]["waited"], 120.0)  # type: ignore[index]
        self.assertLess(float(str(record["seconds"])), 60.0)
        self.assertIn("(after 120.0s waiting for a verify slot)", text.splitlines()[-1])

    def test_a_red_doctor_takes_no_slot(self) -> None:
        harness = Verify(self)
        _rc, _text, record = harness.run(mock.MagicMock(), doctor=1, pool=self.pool())
        harness.slot_pool.assert_not_called()
        self.assertIsNone(record["slot"])

    def test_no_slot_inside_a_verify_or_on_ci(self) -> None:
        facts = {"branch": "b"}
        with mock.patch.dict(os.environ, {verify.INSIDE_VAR: "1"}):
            self.assertIsNone(verify.slot_pool(facts)[0])
        with mock.patch.dict(os.environ), mock.patch.object(verify, "IS_CI", True):
            os.environ.pop(verify.INSIDE_VAR, None)
            self.assertEqual(verify.slot_pool(facts), (None, "no limit on CI"))
        with mock.patch.dict(os.environ, {slots.DIR_VAR: str(self.where), slots.COUNT_VAR: "3"}):
            os.environ.pop(verify.INSIDE_VAR, None)
            with mock.patch.object(verify, "IS_CI", False):
                pool, _why = verify.slot_pool(facts)
        assert pool is not None
        me = {"worktree": ROOT.as_posix(), "branch": "b"}
        self.assertEqual((pool.count, pool.where, pool.me), (3, self.where, me))


class LaneProcessTest(unittest.TestCase):
    """run_lane_process on a real process that prints like a lane."""

    def lane(self, script: str, names: tuple[str, ...], timeout: float = 60) -> list[verify.StepRun]:
        steps: list[verify.StepRun] = []
        verify.run_lane_process("python", names, steps.append, cmd=[sys.executable, "-c", script], timeout=timeout)
        return steps

    def test_each_step_gets_the_lines_before_its_mark(self) -> None:
        mark = verify.MARK
        script = (
            f"print('lint out'); print('{mark}' + '{{\"step\": \"lint\", \"rc\": 0, \"seconds\": 2.5}}');"
            f"print('ü selftest out'); print('{mark}' + '{{\"step\": \"selftest\", \"rc\": 1, \"seconds\": 3.0}}')"
        )
        steps = self.lane(script, ("lint", "selftest"))
        self.assertEqual(
            [(s.name, s.status, s.seconds) for s in steps], [("lint", "passed", 2.5), ("selftest", "FAILED", 3.0)]
        )
        self.assertEqual(steps[0].output, "lint out\n")
        self.assertEqual(steps[1].output, "ü selftest out\n")

    def test_a_broken_mark_is_output_not_a_step(self) -> None:
        steps: list[verify.StepRun] = []
        reader = verify.LaneReader("python", ("lint",), steps.append)
        for line in (
            f"{verify.MARK}not json\n",
            f'{verify.MARK}{{"rc": 0}}\n',
            f'{verify.MARK}{{"step": "lint", "rc": 0, "seconds": 1}}\n',
        ):
            reader.feed(line)
        self.assertEqual([(s.name, s.status) for s in steps], [("lint", "passed")])
        self.assertEqual(steps[0].output, f"{verify.MARK}not json\n{verify.MARK}{{\"rc\": 0}}\n")

    def test_a_mark_of_another_lanes_step_or_a_reported_one_is_output_not_a_step(self) -> None:
        # A selftest worker prints into the Python lane: its mark must never replace the Godot lane's red check.
        steps: list[verify.StepRun] = []
        reader = verify.LaneReader("python", ("lint", "selftest"), steps.append)
        stray = f'{verify.MARK}{{"step": "check", "rc": 0, "seconds": 1}}\n'
        again = f'{verify.MARK}{{"step": "lint", "rc": 0, "seconds": 1}}\n'
        for line in (f'{verify.MARK}{{"step": "lint", "rc": 1, "seconds": 1}}\n', stray, again):
            reader.feed(line)
        reader.feed(f'{verify.MARK}{{"step": "selftest", "rc": 0, "seconds": 2}}\n')
        self.assertEqual([(s.name, s.status) for s in steps], [("lint", "FAILED"), ("selftest", "passed")])
        self.assertEqual(steps[1].output, stray + again)

    def test_a_lane_that_dies_fails_its_unreported_steps_with_its_last_output(self) -> None:
        mark = verify.MARK
        script = (
            f"print('{mark}' + '{{\"step\": \"lint\", \"rc\": 0, \"seconds\": 1}}'); "
            "print('half'); raise SystemExit(3)"
        )
        steps = self.lane(script, ("lint", "selftest"))
        self.assertEqual([(s.name, s.status) for s in steps], [("lint", "passed"), ("selftest", "FAILED")])
        self.assertIn("half\n", steps[1].output)
        self.assertIn("the python lane ended before selftest did: its process exited 3", steps[1].output)

    def test_a_lane_past_its_timeout_is_stopped(self) -> None:
        steps = self.lane("import time; print('started', flush=True); time.sleep(60)", ("lint",), timeout=2)
        self.assertEqual([(s.name, s.status) for s in steps], [("lint", "FAILED")])
        self.assertIn("stopped after 2s", steps[0].output)

    def test_no_real_lanes_inside_a_lane_or_a_selftest_worker(self) -> None:
        with mock.patch.dict(os.environ, {verify.INSIDE_VAR: "1"}), self.assertRaises(Failure) as caught:
            verify.run_lane_process("python", ("lint",), lambda _step: None)
        self.assertIn("no verify lanes inside", str(caught.exception))


def stoppable_lane(statuses: dict[str, str] | None = None, delays: dict[str, float] | None = None) -> verify.RunLane:
    """fake_lane that reports nothing more once verify --fail-fast has stopped the lanes, as a killed lane process."""

    def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
        for name in names:
            time.sleep((delays or {}).get(name, 0.0))
            if verify._STOP.is_set():
                return
            emit(verify.StepRun(name, lane, (statuses or {}).get(name, "passed"), 1.0, f"{name} out\n"))

    return run_lane


def summary_statuses(text: str) -> dict[str, str]:
    """Each summary row's step and status, `not run` included."""
    rows = text[text.rindex("verify summary") :].splitlines()[1:]
    found = {}
    for row in rows:
        m = re.match(r"^  (passed|FAILED|not run) +(\S+(?: tree)?) +[\d.]+s", row)
        if m:
            found[m.group(2)] = m.group(1)
    return found


class AfterTest(unittest.TestCase):
    """AFTER (#556): a lane process starts such a step once the parent has told it that its steps ended."""

    def test_wait_for_steps_reads_step_names_until_every_needed_one_ended(self) -> None:
        with mock.patch.object(verify, "_ENDED", set()):
            stream = io.StringIO("lint\ncheck\nlater\n")
            verify.wait_for_steps(("check",), stream)
            self.assertEqual(stream.readline(), "later\n", "it reads no further than it needs")
            verify.wait_for_steps(("lint",), io.StringIO(""))  # told before: nothing to read
            verify.wait_for_steps((), io.StringIO(""))
            verify.wait_for_steps(("game",), io.StringIO(""))  # the end of stdin: no parent to wait for
            self.assertEqual(verify._ENDED, {"lint", "check"})

    def test_the_gate_tells_each_lane_every_ended_step_once_the_earlier_ones_first(self) -> None:
        gate = verify.Gate()
        first, second, ended = io.BytesIO(), io.BytesIO(), io.BytesIO()
        gate.attach(first)
        gate.end("check")
        gate.end("check")
        gate.attach(second)
        gate.end("test")
        ended.close()  # a lane process that has ended: nothing to tell, and no error
        gate.attach(ended)
        gate.end("enet")
        gate.detach(first)
        gate.end("game")
        self.assertEqual(first.getvalue(), b"check\ntest\nenet\n")
        self.assertEqual(second.getvalue(), b"check\ntest\nenet\ngame\n")

    def test_a_step_starts_only_after_the_step_it_waits_for_ended_in_another_lane(self) -> None:
        # A real lane process running lane_main: its step `two` waits for lane a's `one`, told over its stdin.
        tools = str(ROOT / "tools")
        code = (
            f"import sys, time; sys.path.insert(0, {tools!r}); sys.dont_write_bytecode = True; "
            "from runner import verify; verify.LANES = {'b': ('two',)}; verify.AFTER = {'two': ('one',)}; "
            "verify.steps = lambda: {'two': lambda: (print('two at', time.time()), 0)[1]}; "
            "sys.exit(verify.lane_main('b'))"
        )
        ended: list[float] = []

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            if lane == "a":
                time.sleep(1.5)
                ended.append(time.time())
                emit(verify.StepRun("one", lane, "passed", 1.5))
            else:
                verify.run_lane_process(lane, names, emit, cmd=[sys.executable, "-u", "-c", code], timeout=60)

        steps: list[verify.StepRun] = []
        with (
            mock.patch.object(verify, "LANES", {"a": ("one",), "b": ("two",)}),
            mock.patch.object(verify, "AFTER", {"two": ("one",)}),
        ):
            verify.run_lanes(run_lane, steps.append)
        two = next(step for step in steps if step.name == "two")
        self.assertEqual(two.status, "passed", two.output)
        started = re.search(r"two at ([\d.]+)", two.output)
        assert started is not None, two.output
        self.assertGreaterEqual(float(started.group(1)), ended[0])

    def test_a_lane_without_an_after_step_gets_the_end_of_input_on_stdin(self) -> None:
        code = "import sys; print('stdin:', repr(sys.stdin.read()))"
        steps: list[verify.StepRun] = []

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            if lane == "a":
                emit(verify.StepRun("one", lane, "passed", 0.0))
            else:
                time.sleep(0.3)  # lane a's step has ended: a Gate pipe would carry it
                verify.run_lane_process(lane, names, emit, cmd=[sys.executable, "-c", code], timeout=60)

        with mock.patch.object(verify, "LANES", {"a": ("one",), "b": ("two",)}), mock.patch.object(verify, "AFTER", {}):
            verify.run_lanes(run_lane, steps.append)
        lane_b = [step for step in steps if step.lane == "b"]
        self.assertTrue(lane_b)
        self.assertIn("stdin: ''", "".join(step.output for step in lane_b))

    def test_a_lane_that_crashes_still_tells_its_steps_as_ended(self) -> None:
        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            if lane == "a":
                raise OSError("no such file")
            emit(verify.StepRun("two", lane, "passed", 1.0))

        with mock.patch.object(verify, "LANES", {"a": ("one",), "b": ("two",)}), mock.patch.object(verify, "bad"):
            verify.run_lanes(run_lane, lambda _step: None)
        self.assertEqual(sorted(verify._GATE.ended), ["one", "two"])


class FailFastTest(unittest.TestCase):
    """verify --fail-fast (#556): the first red step stops every lane; the rest is not run, never a pass."""

    def tearDown(self) -> None:
        verify._STOP.clear()

    def test_the_first_red_step_stops_every_lane_and_the_rest_is_not_run(self) -> None:
        delays = {name: 0.5 for name in verify.STEP_ORDER} | {"lint": 0.0}
        rc, text, record = Verify(self).run(stoppable_lane({"lint": "FAILED"}, delays), fail_fast=True)
        self.assertEqual(rc, 1)
        rest = [name for name in verify.STEP_ORDER if name not in ("doctor", "lint")]
        statuses = summary_statuses(text)
        self.assertEqual(statuses, {"doctor": "passed", "lint": "FAILED"} | {name: "not run" for name in rest})
        self.assertEqual(list(statuses), list(verify.STEP_ORDER), "the summary keeps every step, in order")
        self.assertIn(f"  stopped early (--fail-fast): lint was red; {len(rest)} steps not run: {', '.join(rest)}", text)
        self.assertRegex(text.splitlines()[-1], r"^verify: FAILED in [\d.]+s, stopped early at lint \(--fail-fast\)$")
        self.assertNotIn("== signal", text, "a step that never ran prints no block")
        self.assertEqual(record["status"], "FAILED")
        self.assertEqual(record["stopped"], {"at": "lint", "not_run": rest})
        steps = {s["name"]: s for s in record["steps"]}  # type: ignore[union-attr]
        self.assertEqual({name: steps[name]["status"] for name in rest}, {name: "not run" for name in rest})
        self.assertNotIn("failure", steps["selftest"])
        self.assertEqual(record["selftest"], {}, "no count of a partial selftest")

    def test_no_count_check_after_a_stop(self) -> None:
        run = Verify(self)
        run.run(stoppable_lane({"check": "FAILED"}, {name: 0.5 for name in verify.STEP_ORDER} | {"check": 0.0}),
                fail_fast=True)  # fmt: skip
        run.count.assert_not_called()

    def test_a_red_step_reported_after_the_stop_is_not_run_and_a_passed_one_stays_passed(self) -> None:
        # A killed lane's step may still report (its process ended under it) while the stop goes on: not a red of
        # its own. A step that passed before the stop reached its lane did pass.
        stopped = threading.Event()

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            if lane == "python":
                emit(verify.StepRun("lint", lane, "FAILED", 1.0, "  FAIL  lint\n"))
                stopped.set()
            elif lane == "godot":
                stopped.wait(10)
                emit(verify.StepRun("check", lane, "passed", 1.0))
                emit(verify.StepRun("test", lane, "FAILED", 0.0, "the godot lane ended before test did\n"))

        rc, text, record = Verify(self).run(run_lane, fail_fast=True)
        self.assertEqual(rc, 1)
        statuses = summary_statuses(text)
        self.assertEqual((statuses["lint"], statuses["check"], statuses["test"]), ("FAILED", "passed", "not run"))
        self.assertNotIn("the godot lane ended before test did", text)
        self.assertEqual(record["stopped"]["at"], "lint")  # type: ignore[index]
        self.assertNotIn("check", record["stopped"]["not_run"])  # type: ignore[index]

    def test_without_the_flag_a_red_step_stops_nothing(self) -> None:
        delays = {name: 0.05 for name in verify.STEP_ORDER} | {"lint": 0.0}
        rc, text, record = Verify(self).run(stoppable_lane({"lint": "FAILED"}, delays))
        self.assertEqual(rc, 1)
        self.assertEqual([n for n, status in summary_statuses(text).items() if status != "passed"], ["lint"])
        self.assertIsNone(record["stopped"])

    def test_stop_lanes_ends_a_running_lane_process_and_one_that_starts_after_it(self) -> None:
        sleeper = [sys.executable, "-c", "import time; print('started', flush=True); time.sleep(60)"]
        steps: list[verify.StepRun] = []
        timer = threading.Timer(1.0, verify.stop_lanes)
        timer.start()
        started = time.monotonic()
        verify.run_lane_process("python", ("lint",), steps.append, cmd=sleeper, timeout=60)
        timer.join()
        self.assertLess(time.monotonic() - started, 30)
        late: list[verify.StepRun] = []
        started = time.monotonic()
        verify.run_lane_process("godot", ("check",), late.append, cmd=sleeper, timeout=60)  # _STOP is still set
        self.assertLess(time.monotonic() - started, 30)
        # Unended: the lane reader fails them, and verify --fail-fast's emit reports them as not run.
        self.assertEqual([(s.name, s.status) for s in steps + late], [("lint", "FAILED"), ("check", "FAILED")])

    def test_the_flag_reaches_verify_and_is_off_by_default(self) -> None:
        with mock.patch.object(verify, "main", return_value=0) as run, mock.patch.object(common, "IS_CI", False):
            self.assertEqual(cli.main(["verify"]), 0)
            self.assertEqual(cli.main(["verify", "--fail-fast"]), 0)
            self.assertEqual(cli.main(["verify", "--full", "--fail-fast"]), 0)
            self.assertEqual(cli.main(["verify", "--full"]), 0)
        self.assertEqual(
            run.call_args_list,
            [
                mock.call(full=False, fail_fast=False, verbose=False),
                mock.call(full=False, fail_fast=True, verbose=False),
                mock.call(full=True, fail_fast=True, verbose=False),
                mock.call(full=True, fail_fast=False, verbose=False),
            ],
        )

    def test_metrics_reads_a_stopped_summary_without_its_not_run_rows(self) -> None:
        delays = {name: 0.5 for name in verify.STEP_ORDER} | {"lint": 0.0}
        _rc, text, _record = Verify(self).run(stoppable_lane({"lint": "FAILED"}, delays), fail_fast=True)
        parsed = metrics.parse_verify(text)
        assert parsed is not None
        self.assertEqual(parsed["steps"], {"doctor": ("passed", parsed["steps"]["doctor"][1]), "lint": ("FAILED", 1.0)})
        self.assertEqual((parsed["status"], parsed["stopped"]), ("FAILED", True))


class SuspendTest(unittest.TestCase):
    """#595: a machine that slept stops the run at its resume: the steps it was running are red with the suspend, the
    rest is not run, and the run counts as stopped early."""

    def tearDown(self) -> None:
        verify._STOP.clear()

    def test_a_suspend_stops_the_running_steps_red_and_the_rest_is_not_run(self) -> None:
        ran = {"python": threading.Event(), "godot": threading.Event()}

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            done = names[:1] if lane in ran else ()
            for name in done:
                emit(verify.StepRun(name, lane, "passed", 1.0, f"{name} out\n"))
            if lane in ran:
                ran[lane].set()
            verify._STOP.wait(10)  # the lane process runs on until stop_lanes kills it
            for name in names[len(done) :]:  # as LaneReader.close reports the steps of a killed lane
                emit(verify.StepRun(name, lane, "FAILED", 0.0, f"  FAIL  the {lane} lane ended before {name} did\n"))

        def watch(on_suspend: object, stop: threading.Event) -> None:
            def fire() -> None:
                if all(event.wait(10) for event in ran.values()):
                    on_suspend(37954.4)  # type: ignore[operator]

            threading.Thread(target=fire, daemon=True).start()

        run = Verify(self)
        rc, text, record = run.run(run_lane, watch=watch)
        self.assertEqual(rc, 1)
        stopped = ["selftest-godot", "signal", "test"]  # each lane's running step; enet still waited for selftest-godot
        statuses = summary_statuses(text)
        self.assertEqual({name for name, status in statuses.items() if status == "FAILED"}, set(stopped))
        self.assertEqual({name for name, status in statuses.items() if status == "passed"}, {"doctor", "lint", "check"})
        not_run = [name for name in verify.STEP_ORDER if statuses[name] == "not run"]
        self.assertEqual(len(not_run), len(verify.STEP_ORDER) - 6)
        said = "the machine slept or was suspended (37954 s)"
        self.assertIn(f"verify: {said}: stopping every lane (selftest-godot, signal, test)", text)
        self.assertIn(f"== signal (python lane, 0.0s, FAILED)\n  FAIL  {said}: verify stopped this step\n", text)
        self.assertIn(f"  stopped early: {said} while verify ran; {len(not_run)} steps not run", text)
        self.assertEqual(text.splitlines()[-1].split(" in ")[0], "verify: FAILED")
        self.assertTrue(text.splitlines()[-1].endswith(f"s, stopped early at {', '.join(stopped)}: {said}"), text)
        self.assertEqual(record["stopped"], {"at": None, "suspended": 37954, "not_run": not_run})
        steps = {s["name"]: s for s in record["steps"]}  # type: ignore[union-attr]
        self.assertEqual(steps["test"]["failure"], f"{said}: verify stopped this step")
        run.count.assert_not_called()
        self.assertIsNone(metrics.parse_verify(text), "metrics counts none of the steps the sleep made red")

    def test_the_watch_runs_beside_the_lanes_and_stops_with_them(self) -> None:
        seen: list[threading.Event] = []
        _rc, _text, record = Verify(self).run(fake_lane(), watch=lambda _on, stop: seen.append(stop))
        self.assertEqual(len(seen), 1)
        self.assertTrue(seen[0].is_set())
        self.assertIsNone(record["stopped"])
        default = inspect.signature(verify.main).parameters["watch"].default
        self.assertIs(default, suspend.watch_in_background)

    def test_a_suspend_noticed_after_a_fail_fast_stop_changes_nothing(self) -> None:
        told = threading.Event()

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            if lane == "python":
                emit(verify.StepRun("lint", lane, "FAILED", 1.0, "  FAIL  lint\n"))
            elif lane == "godot":
                told.wait(10)  # still running when the suspend is noticed

        def watch(on_suspend: object, stop: threading.Event) -> None:
            def fire() -> None:
                verify._STOP.wait(10)  # --fail-fast has stopped the lanes
                on_suspend(500.0)  # type: ignore[operator]
                told.set()

            threading.Thread(target=fire, daemon=True).start()

        _rc, text, record = Verify(self).run(run_lane, fail_fast=True, watch=watch)
        self.assertTrue(told.is_set())
        self.assertNotIn("slept", text)
        self.assertEqual(record["stopped"]["at"], "lint")  # type: ignore[index]

    def test_a_suspend_noticed_after_the_lanes_ended_changes_nothing(self) -> None:
        def watch(on_suspend: object, stop: threading.Event) -> None:
            def fire() -> None:
                if stop.wait(10):  # the lanes ended: a tick that was under way when they did
                    on_suspend(500.0)  # type: ignore[operator]

            threading.Thread(target=fire, daemon=True).start()

        run = Verify(self)
        rc, text, record = run.run(fake_lane(), watch=watch)
        self.assertEqual(rc, 0)
        self.assertNotIn("slept", text)
        self.assertIsNone(record["stopped"])
        run.count.assert_called_once()

    def test_a_suspend_noticed_after_the_last_step_ended_changes_nothing(self) -> None:
        # The lanes' threads are still being joined: every step has ended, so the count check and the pass stand.
        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            for name in names:
                emit(verify.StepRun(name, lane, "passed", 1.0, f"{name} out\n"))

        def watch(on_suspend: object, stop: threading.Event) -> None:
            def fire() -> None:
                time.sleep(0.2)
                on_suspend(500.0)  # type: ignore[operator]

            fired.append(threading.Thread(target=fire))

        fired: list[threading.Thread] = []
        run = Verify(self)

        def late_lanes(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            run_lane(lane, names, emit)
            if lane == "godot":
                fired[0].start()
                fired[0].join()  # run_lanes has not returned yet when the suspend is told

        rc, text, record = run.run(late_lanes, watch=watch)
        self.assertEqual(rc, 0)
        self.assertNotIn("slept", text)
        self.assertIsNone(record["stopped"])
        run.count.assert_called_once()

    def test_stop_lanes_firmly_falls_back_to_kill_and_repeats_while_a_lane_process_lives(self) -> None:
        proc = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"], stdout=subprocess.DEVNULL)
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        with verify._LIVE_LOCK:
            verify._LIVE.add(proc)
        self.addCleanup(verify._LIVE.discard, proc)
        calls: list[int] = []
        slept: list[float] = []

        def refused(target: subprocess.Popen[bytes]) -> None:
            calls.append(target.pid)
            raise OSError("a process cannot start right after a wake")  # taskkill, STATUS_DLL_INIT_FAILED

        def sleep(seconds: float) -> None:
            slept.append(seconds)
            proc.wait(timeout=10)  # Popen.kill ended it, though the lane's thread has not reported it yet
            with verify._LIVE_LOCK:
                verify._LIVE.discard(proc)  # as run_lane_process does when its process ends

        with mock.patch.object(verify, "stop_lane", refused):
            verify.stop_lanes_firmly(tries=4, gap=1.0, sleep=sleep)
        self.assertEqual((len(calls), slept), (1, [1.0]))
        self.assertIsNotNone(proc.poll())

    def test_the_steps_in_flight_are_each_lanes_first_unended_step_that_could_start(self) -> None:
        self.assertEqual(verify.steps_in_flight({"doctor"}), {"lint", "check"})
        self.assertEqual(verify.steps_in_flight({"doctor", "lint", "check"}), {"signal", "test", "selftest-godot"})
        self.assertEqual(verify.steps_in_flight({"lint", "signal", "check", "test"}), {"selftest", "selftest-godot"})
        self.assertEqual(verify.steps_in_flight(set(verify.STEP_ORDER)), set())


def alive(pid: int) -> bool:
    """Whether the process `pid` still runs: a zombie, which only waits for its parent to read its exit, does not."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    stat = Path(f"/proc/{pid}/stat")
    if stat.exists():
        try:
            return stat.read_text().rsplit(")", 1)[1].split()[0] != "Z"
        except (OSError, IndexError):
            return False
    state = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True, check=False).stdout
    return bool(state.strip()) and not state.strip().startswith("Z")


class LaneTermTest(unittest.TestCase):
    """#574: a lane process stopped on Linux or macOS (verify --fail-fast, the lane timeout, Ctrl+C) kills the
    processes common.run started, each in a group of its own that the kill of the lane's group never reaches."""

    def tearDown(self) -> None:
        verify._STOP.clear()

    def test_lane_main_kills_the_children_on_sigterm_while_its_steps_run(self) -> None:
        seen: list[object] = []
        before = signal.getsignal(signal.SIGTERM)

        def step() -> int:
            seen.append(signal.getsignal(signal.SIGTERM))
            return 0

        with (
            mock.patch.object(verify, "LANES", {"x": ("s",)}),
            mock.patch.object(verify, "AFTER", {}),
            mock.patch.object(verify, "steps", lambda: {"s": step}),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(verify.lane_main("x", wait=no_wait), 0)
        # Windows has no such handler: stop_lane's taskkill /T reaches the whole tree.
        self.assertEqual(seen, [before if common.IS_WINDOWS else verify.lane_stopped])
        self.assertEqual(signal.getsignal(signal.SIGTERM), before, "the earlier handler is back after the steps")

    def test_the_handler_kills_what_run_started_then_ends_the_lane_at_once(self) -> None:
        calls: list[str] = []
        with (
            mock.patch.object(verify, "kill_running", lambda: calls.append("kill_running")),
            mock.patch.object(verify.os, "_exit", lambda rc: calls.append(f"exit {rc}")),
        ):
            verify.lane_stopped(signal.SIGTERM, None)
        self.assertEqual(calls, ["kill_running", f"exit {128 + signal.SIGTERM}"])

    def test_run_tracks_each_process_until_it_ends(self) -> None:
        tracked: list[bool] = []
        procs: list[object] = []

        def started(proc: object) -> None:
            procs.append(proc)
            tracked.append(proc in common.RUNNING)

        result = common.run([sys.executable, "-c", "pass"], timeout=60, on_start=started)
        self.assertEqual(result.rc, 0, result.out)
        self.assertEqual(tracked, [True])
        self.assertNotIn(procs[0], common.RUNNING)

    def test_kill_running_kills_each_group_and_waits_for_none(self) -> None:
        # Its caller is a signal handler: a Popen.wait there could block on the wait the signal interrupted.
        first, second = mock.MagicMock(), mock.MagicMock()
        killed: list[object] = []
        with (
            mock.patch.object(common, "RUNNING", {first, second}),
            mock.patch.object(common, "_kill_group", killed.append),
        ):
            common.kill_running()
        self.assertCountEqual(killed, [first, second])
        first.wait.assert_not_called()
        second.wait.assert_not_called()

    def test_stop_lane_sends_sigterm_first_on_linux_and_macos_only(self) -> None:
        for windows in (False, True):
            with self.subTest(windows=windows):
                proc = mock.MagicMock()
                proc.poll.return_value = None
                killed: list[object] = []
                with (
                    mock.patch.object(verify, "IS_WINDOWS", windows),
                    mock.patch.object(verify, "kill_tree", killed.append),
                ):
                    verify.stop_lane(proc)
                self.assertEqual(killed, [proc], "the lane's group (its tree on Windows) is killed in the end")
                if windows:
                    proc.terminate.assert_not_called()
                else:
                    proc.terminate.assert_called_once_with()
                    proc.wait.assert_called_once_with(timeout=verify.LANE_TERM_GRACE)

    @unittest.skipIf(common.IS_WINDOWS, "Windows: kill_tree's taskkill /T reaches the whole tree")
    def test_stop_lanes_kills_a_child_run_started_in_a_session_of_its_own(self) -> None:
        tools = str(ROOT / "tools")
        with tempfile.TemporaryDirectory() as tmp:
            pidfile = str(Path(tmp) / "child.pid")
            child = [
                sys.executable,
                "-c",
                f"import os, time; open({pidfile!r} + '.tmp', 'w').write(str(os.getpid())); "
                f"os.replace({pidfile!r} + '.tmp', {pidfile!r}); time.sleep(120)",
            ]
            code = (
                f"import sys; sys.path.insert(0, {tools!r}); sys.dont_write_bytecode = True; "
                "from runner import common, verify; verify.LANES = {'x': ('s',)}; verify.AFTER = {}; "
                f"verify.steps = lambda: {{'s': lambda: common.run({child!r}, timeout=300).rc}}; "
                "sys.exit(verify.lane_main('x'))"
            )

            def stop_once_the_child_runs() -> None:
                deadline = time.monotonic() + 60
                while not os.path.exists(pidfile) and time.monotonic() < deadline:
                    time.sleep(0.05)
                verify.stop_lanes()

            stopper = threading.Thread(target=stop_once_the_child_runs, daemon=True)
            stopper.start()
            steps: list[verify.StepRun] = []
            started = time.monotonic()
            verify.run_lane_process("x", ("s",), steps.append, cmd=[sys.executable, "-u", "-c", code], timeout=120)
            stopper.join(timeout=60)
            self.assertTrue(os.path.exists(pidfile), "the child never started")
            pid = int(Path(pidfile).read_text())
            try:
                deadline = time.monotonic() + 10
                while alive(pid) and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertFalse(alive(pid), "the child run started outlived its stopped lane")
            finally:
                if alive(pid):
                    os.kill(pid, signal.SIGKILL)
            self.assertLess(time.monotonic() - started, 60)
            self.assertEqual([(s.name, s.status) for s in steps], [("s", "FAILED")])


FIXTURE = '''
import unittest

class T(unittest.TestCase):
    def test_passes(self):
        pass

    def test_fails(self):
        self.assertEqual(1, 2)

    @unittest.skip("by a decorator")
    def test_skipped_by_a_decorator(self):
        pass

    def test_skipped_when_it_runs(self):
        self.skipTest("at run time")
'''


GROUP_FIXTURE = '''
import os
import unittest
from pathlib import Path

from runner.common import app_data_dir
from runner.verify import starts_godot


def godot_writes_its_user_dir(name):
    """What a Godot start does: a folder in app_userdata/ of the app-data folder it was given."""
    base = app_data_dir()
    if base is not None:
        (base / "Godot" / "app_userdata" / name / "logs").mkdir(parents=True, exist_ok=True)
        (base / "Godot" / "app_userdata" / name / "logs" / "godot.log").write_text("x", encoding="utf-8")


class NoGodot(unittest.TestCase):
    def test_one(self):
        if os.environ.get("SELFTEST_FIXTURE_LEAK"):
            godot_writes_its_user_dir("PrimeGame-182-abcdef")

    def test_two(self):
        if os.environ.get("SELFTEST_FIXTURE_FAIL"):
            self.fail("asked to")


@starts_godot
class WithGodot(unittest.TestCase):
    def test_three(self):
        godot_writes_its_user_dir("PrimeGame-182-fedcba")
'''


BATCH_FIXTURE = """
import os
import unittest


class Shared(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.environ["SELFTEST_BATCH_SETUPS"], "a", encoding="utf-8") as f:
            print("Shared", file=f)

    def test_a(self):
        pass

    def test_b(self):
        pass

    def test_c(self):
        pass


class Broken(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        raise RuntimeError("no class for you")

    def test_a(self):
        pass

    def test_b(self):
        pass


class SkippedClass(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        raise unittest.SkipTest("not today")

    def test_a(self):
        pass


class Sub(unittest.TestCase):
    def test_a(self):
        for n in (1, 2):
            with self.subTest(n=n):
                self.assertEqual(n, 1)


class Torn(unittest.TestCase):
    @classmethod
    def tearDownClass(cls):
        raise RuntimeError("torn")

    def test_a(self):
        pass

    def test_b(self):
        pass
"""


class SelftestTest(unittest.TestCase):
    def selftest_on_fixture(
        self, group: str, fail: bool = False, leak: bool = False
    ) -> tuple[int, dict[str, object] | None, str]:
        """selftest(group) over GROUP_FIXTURE in temp logs; its rc, its results record and its printed text."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        name = f"selftest_group_fixture_{uuid.uuid4().hex}"
        (Path(tmp.name) / f"{name}.py").write_text(GROUP_FIXTURE, encoding="utf-8")
        sys.path.insert(0, tmp.name)  # the spawned workers get this process's sys.path
        self.addCleanup(sys.path.remove, tmp.name)
        self.addCleanup(sys.modules.pop, name, None)
        tests = list(verify._flatten(unittest.defaultTestLoader.loadTestsFromName(name)))
        logs = Path(tmp.name) / "logs"
        env = {
            verify.RUN_ID_VAR: "run-1",
            **({"SELFTEST_FIXTURE_FAIL": "1"} if fail else {}),
            **({"SELFTEST_FIXTURE_LEAK": "1"} if leak else {}),
        }
        # This process's app-data folder, as selftest finds it: the real one outside a test, so a temporary one here.
        var = common.app_data_var()
        if var is not None:
            env[var] = str(Path(tmp.name) / "outer")
        with (
            mock.patch.dict(os.environ, env),
            mock.patch.object(verify, "discover", return_value=tests),
            mock.patch.object(verify, "LOGS", logs),
            mock.patch.object(verify, "ensure_out", side_effect=lambda: logs.mkdir(exist_ok=True)),
            mock.patch.object(verify, "selftest_workers", return_value=2),
            contextlib.redirect_stdout(io.StringIO()) as out,
        ):
            rc = verify.selftest(group)
            record = verify.read_results(group)
        return rc, record, out.getvalue()

    def test_each_group_runs_only_its_classes_and_records_this_run(self) -> None:
        groups = {"python": {"NoGodot.test_one", "NoGodot.test_two"}, "godot": {"WithGodot.test_three"}}
        for group, expected in groups.items():
            rc, record, text = self.selftest_on_fixture(group)
            self.assertEqual(rc, 0, text)
            assert record is not None
            self.assertEqual(record["run"], "run-1")
            self.assertEqual(record["workers"], 2 if group == "python" else 1)
            tests = record["tests"]
            assert isinstance(tests, list)
            self.assertEqual({".".join(str(e["id"]).split(".")[-2:]) for e in tests}, expected)
            self.assertEqual({e["outcome"] for e in tests}, {"passed"})

    def test_a_failed_test_in_a_worker_fails_its_group(self) -> None:
        rc, record, text = self.selftest_on_fixture("python", fail=True)
        self.assertEqual(rc, 1)
        assert record is not None
        tests = record["tests"]
        assert isinstance(tests, list)
        self.assertEqual(sorted(str(e["outcome"]) for e in tests), ["failed", "passed"])
        self.assertIn("AssertionError: asked to", text)
        self.assertIn("selftest: FAILED", text)

    def test_a_test_that_writes_to_the_app_data_folder_outside_a_godot_class_fails_the_run(self) -> None:
        # #233: selftest's workers get a stand-in app-data folder; a @starts_godot class writes to its own instead.
        if common.app_data_var() is None:
            self.skipTest("no app-data variable on this OS")
        for group in ("python", "godot"):
            rc, _record, text = self.selftest_on_fixture(group)
            self.assertEqual(rc, 0, text)
            self.assertNotIn("wrote to the app-data folder", text)
        rc, _record, text = self.selftest_on_fixture("python", leak=True)
        self.assertEqual(rc, 1, text)
        self.assertIn(
            "runner tests wrote to the app-data folder, which outside selftest is the real one: "
            "Godot/app_userdata/PrimeGame-182-abcdef/logs/godot.log",
            text,
        )
        self.assertIn("selftest: FAILED", text)

    def test_app_data_written_names_at_most_a_few_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.assertEqual(verify.app_data_written(None), [])
            self.assertEqual(verify.app_data_written(folder), [])
            (folder / "Godot").mkdir()  # an empty folder is no write
            self.assertEqual(verify.app_data_written(folder), [])
            for n in range(7):
                (folder / "Godot" / f"f{n}.txt").write_text("x", encoding="utf-8")
            self.assertEqual(verify.app_data_written(folder, limit=2), ["Godot/f0.txt", "Godot/f1.txt", "and 5 more"])

    def test_app_data_written_names_an_empty_user_dir_folder(self) -> None:
        # Godot makes the user:// folder before it writes any file into it: an empty one is still a leak.
        for godot in ("Godot", "godot"):
            with self.subTest(godot), tempfile.TemporaryDirectory() as tmp:
                folder = Path(tmp)
                (folder / godot / "app_userdata").mkdir(parents=True)
                self.assertEqual(verify.app_data_written(folder), [])
                (folder / godot / "app_userdata" / "PrimeGame-182-abcdef").mkdir()
                self.assertEqual(verify.app_data_written(folder), [f"{godot}/app_userdata/PrimeGame-182-abcdef/"])

    def test_the_godot_group_is_every_class_that_needs_godot(self) -> None:
        # A class whose skip asks for godot_bin() starts Godot: it must carry @starts_godot, and only such a class.
        needs, marked = set(), set()
        for path in sorted(verify.TESTS.glob("test*.py")):
            for node in ast.parse(path.read_text(encoding="utf-8")).body:
                if isinstance(node, ast.ClassDef):
                    decorators = [ast.unparse(d) for d in node.decorator_list]
                    if any("godot_bin()" in d for d in decorators):
                        needs.add(f"{path.stem}.{node.name}")
                    if any(d.endswith("starts_godot") for d in decorators):
                        marked.add(f"{path.stem}.{node.name}")
        self.assertEqual(marked, needs)
        self.assertEqual(
            needs,
            {
                "test_godot_tools.RealNormalizeTest",
                "test_hostjoin.RealSessionTest",
                "test_import_freshness.RealStaleCacheTest",
                "test_launch.RealRunTest",
                "test_lfs.RealPointerTest",
                "test_user_dir.RealUserDirTest",
            },
        )
        found = {".".join(t.id().split(".")[2:4]) for t in verify.discover() if verify.group_of(t) == "godot"}
        self.assertEqual(found, needs)

    def test_half_the_logical_cpus_of_a_big_machine_a_quarter_of_a_small_one_at_least_one(self) -> None:
        # #556: 8 on the engineer's PC (16 logical CPUs), 1 on CI's 4-vCPU runner as before.
        cpus = (1, 2, 4, 6, 7, 8, 16, 32)
        self.assertEqual([verify.selftest_workers(n) for n in cpus], [1, 1, 1, 1, 1, 4, 8, 16])

    def test_alone_a_small_machine_gives_every_cpu_a_big_one_still_half(self) -> None:
        # #603: CI's minimum-Python job (4 vCPUs, nothing beside it) runs on 4 workers; the PC keeps 8 of 16.
        cpus = (1, 2, 4, 6, 7, 8, 16, 32)
        self.assertEqual([verify.selftest_workers(n, alone=True) for n in cpus], [1, 2, 4, 6, 7, 4, 8, 16])

    def test_selftest_in_a_verify_lane_shares_the_machine_and_alone_does_not(self) -> None:
        # `all` runs the selftest-godot group beside the Python one, so outside a lane it is not alone either.
        for group, inside, alone in (("python", "1", False), ("python", "", True), ("all", "", False)):
            with (
                self.subTest(group=group, inside=inside),
                mock.patch.dict(os.environ, {verify.INSIDE_VAR: inside}),
                mock.patch.object(verify, "discover", return_value=[]),
                mock.patch.object(verify, "selftest_workers", return_value=3) as workers,
                mock.patch.object(verify, "_run_group", return_value=([], 0.0)),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                verify.selftest(group)
                workers.assert_called_once_with(alone=alone)

    def test_workers_report_each_outcome_like_a_serial_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            name = f"selftest_fixture_{uuid.uuid4().hex}"
            (Path(tmp) / f"{name}.py").write_text(FIXTURE, encoding="utf-8")
            sys.path.insert(0, tmp)  # the spawned workers get this process's sys.path
            self.addCleanup(sys.path.remove, tmp)
            names = ("test_passes", "test_fails", "test_skipped_by_a_decorator", "test_skipped_when_it_runs")
            ids = [f"{name}.T.{test}" for test in names]
            # One batch, two, or a test a batch (#603): the same outcome for each test.
            runs = [verify.run_in_workers(b, 2) for b in ([ids], [ids[:2], ids[2:]], [[i] for i in ids])]
            serial = unittest.TestResult()
            unittest.defaultTestLoader.loadTestsFromName(f"{name}.T").run(serial)
            sys.modules.pop(name, None)
        for run in runs:
            entries = {e["id"]: e for e in run}
            outcome = {test_id.rsplit(".", 1)[1]: (e["outcome"], e["static"]) for test_id, e in entries.items()}
            self.assertEqual(
                outcome,
                {
                    "test_passes": ("passed", False),
                    "test_fails": ("failed", False),
                    "test_skipped_by_a_decorator": ("skipped", True),
                    "test_skipped_when_it_runs": ("skipped", False),
                },
            )
            self.assertIn("AssertionError: 1 != 2", str(entries[ids[1]]["detail"]))
            self.assertEqual(entries[ids[3]]["detail"], "at run time")
        self.assertEqual((serial.testsRun, len(serial.failures), len(serial.skipped)), (4, 1, 2))

    def test_a_batch_runs_class_fixtures_once_and_gives_their_errors_and_skips_to_their_tests(self) -> None:
        # #603: a batch is a serial run of its tests; a fixture's outcome is each of its class's tests' in the batch.
        with tempfile.TemporaryDirectory() as tmp:
            name = f"selftest_batch_fixture_{uuid.uuid4().hex}"
            (Path(tmp) / f"{name}.py").write_text(BATCH_FIXTURE, encoding="utf-8")
            sys.path.insert(0, tmp)
            self.addCleanup(sys.path.remove, tmp)
            self.addCleanup(sys.modules.pop, name, None)
            setups = Path(tmp) / "setups.txt"
            with mock.patch.dict(os.environ, {"SELFTEST_BATCH_SETUPS": str(setups)}):
                tests = list(verify._flatten(unittest.defaultTestLoader.loadTestsFromName(name)))
                ids = [t.id() for t in tests]
                started = time.monotonic()
                entries = verify.run_batch(tests, ids)
                took = time.monotonic() - started
                serial = unittest.TestResult()
                unittest.defaultTestLoader.loadTestsFromName(name).run(serial)
            self.assertEqual(setups.read_text(encoding="utf-8").splitlines(), ["Shared", "Shared"])
        outcome = {".".join(str(e["id"]).split(".")[-2:]): e["outcome"] for e in entries}
        self.assertEqual(
            outcome,
            {
                "Broken.test_a": "failed", "Broken.test_b": "failed",
                "Shared.test_a": "passed", "Shared.test_b": "passed", "Shared.test_c": "passed",
                "SkippedClass.test_a": "skipped",
                "Sub.test_a": "failed",
                "Torn.test_a": "failed", "Torn.test_b": "failed",
            },
        )  # fmt: skip
        detail = {".".join(str(e["id"]).split(".")[-2:]): str(e["detail"]) for e in entries}
        self.assertIn("RuntimeError: no class for you", detail["Broken.test_b"])
        self.assertEqual(detail["SkippedClass.test_a"], "not today")
        self.assertIn("AssertionError: 2 != 1", detail["Sub.test_a"])
        self.assertIn("RuntimeError: torn", detail["Torn.test_a"])
        self.assertEqual(ids, [e["id"] for e in entries])
        self.assertAlmostEqual(sum(float(str(e["seconds"])) for e in entries), took, delta=0.5)
        # The serial run: Broken's and Torn's fixture errors, Sub's subtest failure; the skipped class's fixture.
        self.assertEqual((serial.testsRun, len(serial.errors), len(serial.failures)), (6, 2, 1))

    def test_the_count_matches_a_serial_discovery(self) -> None:
        reference = {"a": False, "b": True}
        entries: list[dict[str, object]] = [
            {"id": "a", "outcome": "passed", "static": False},
            {"id": "b", "outcome": "skipped", "static": True},
        ]
        problems, line = verify.count_check(reference, entries)
        self.assertEqual(problems, [])
        self.assertEqual(line, "runner tests: 1 run and 1 skipped of 2; a serial run: 1 run of 2")

    def test_a_lost_doubled_extra_or_differently_skipped_test_is_named(self) -> None:
        reference = {"a": False, "b": False, "c": False, "g": False}
        entries: list[dict[str, object]] = [
            {"id": "a", "outcome": "passed", "static": False},
            {"id": "a", "outcome": "passed", "static": False},
            {"id": "x", "outcome": "passed", "static": False},
            # RealSessionTest discovered before check imported the project: skipped there, not in a serial run.
            {"id": "g", "outcome": "skipped", "static": True},
            {"id": "c", "outcome": "skipped", "static": False},  # skipTest() at run time: a serial run skips it too
        ]
        problems, _line = verify.count_check(reference, entries)
        self.assertEqual(
            problems,
            [
                "1 runner tests never ran: b",
                "1 runner tests ran but a serial run has no such test: x",
                "1 runner tests ran more than once: a",
                "1 runner tests skipped by a decorator in one run and not in the other: g",
            ],
        )

    def test_the_last_runs_slowest_tests_start_first_and_new_ones_before_them(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            record = {"tests": [{"id": "m.A.fast", "seconds": 0.1}, {"id": "m.B.slow", "seconds": 9.0}]}
            (Path(tmp) / "selftest-python.json").write_text(json.dumps(record), encoding="utf-8")
            with mock.patch.object(verify, "LOGS", Path(tmp)):
                seconds = verify.last_seconds("python")
                self.assertEqual(seconds, {"m.A.fast": 0.1, "m.B.slow": 9.0})
                batches = verify.plan_batches(["m.A.fast", "m.B.slow", "m.C.new"], seconds, 1)
                self.assertEqual(batches, [["m.C.new"], ["m.B.slow"], ["m.A.fast"]])
                self.assertEqual(verify.last_seconds("godot"), {})
                self.assertEqual(verify.plan_batches(["m.A.b", "m.B.a"], {}, 4), [["m.A.b"], ["m.B.a"]])

    def test_a_class_runs_in_batches_of_its_tests_in_their_order_none_over_its_share(self) -> None:
        # #603: 16 s of tests on 1 worker: no batch over 16 / (1 * BATCHES_PER_WORKER) = 4 s, unless one test is.
        ids = [f"m.Big.t{i}" for i in range(6)] + ["m.Lone.t0", "m.Small.a", "m.Small.b", "m.Small.c"]
        seconds = {
            "m.Big.t0": 2.0, "m.Big.t1": 1.5, "m.Big.t2": 0.5, "m.Big.t3": 1.0, "m.Big.t4": 2.0, "m.Big.t5": 2.5,
            "m.Lone.t0": 5.0, "m.Small.a": 0.5, "m.Small.b": 0.5, "m.Small.c": 0.5,
        }  # fmt: skip
        with mock.patch.object(verify, "BATCHES_PER_WORKER", 4):
            batches = verify.plan_batches(ids, seconds, 1)
        self.assertEqual(
            batches,
            [
                ["m.Lone.t0"],  # 5 s: one test over the share runs alone, and first
                ["m.Big.t0", "m.Big.t1", "m.Big.t2"],  # 4 s
                ["m.Big.t3", "m.Big.t4"],  # 3 s
                ["m.Big.t5"],  # 2.5 s
                ["m.Small.a", "m.Small.b", "m.Small.c"],  # 1.5 s: a class never shares a batch with another
            ],
        )
        self.assertEqual(sorted(t for batch in batches for t in batch), sorted(ids))
        self.assertEqual(verify.plan_batches([], {}, 8), [])

    def test_more_workers_cut_a_class_finer_and_new_tests_count_a_second(self) -> None:
        ids = [f"m.C.t{i}" for i in range(8)]
        # 8 unknown seconds over 1 worker * 4 batches: 2 tests a batch; over 2 workers * 4: 1 a batch.
        self.assertEqual(verify.plan_batches(ids, {}, 1), [ids[0:2], ids[2:4], ids[4:6], ids[6:8]])
        self.assertEqual(verify.plan_batches(ids, {}, 2), [[test_id] for test_id in ids])

    def test_verify_counts_the_results_of_this_run_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for group, run in (("python", "this"), ("godot", "an older run")):
                record = {"run": run, "tests": [{"id": "t", "outcome": "passed", "static": False}]}
                (Path(tmp) / f"selftest-{group}.json").write_text(json.dumps(record), encoding="utf-8")
            with mock.patch.object(verify, "LOGS", Path(tmp)), mock.patch.object(verify, "discover", return_value=[]):
                problems, _line, counts = verify.count_after_lanes("this")
        self.assertIn("selftest godot left no results of this run", problems[0])
        self.assertEqual(counts, {"run": 1, "skipped": 0})


class EnetStepTest(unittest.TestCase):
    def test_the_run_is_headless_three_instances_on_its_own_port(self) -> None:
        with (
            mock.patch.object(verify, "free_udp_port", return_value=23456),
            mock.patch.object(verify.launch, "main", return_value=0) as run,
        ):
            self.assertEqual(verify.enet(), 0)
        run.assert_called_once_with(
            verify.ENET_RUN, headless=True, seconds=90, instances=3, user_args=["--port=23456"]
        )
        self.assertTrue((ROOT / verify.ENET_RUN).is_file())

    def test_the_freeze_run_is_headless_three_instances_on_its_own_port(self) -> None:
        with (
            mock.patch.object(verify, "free_udp_port", return_value=23457),
            mock.patch.object(verify.launch, "main", return_value=0) as run,
        ):
            self.assertEqual(verify.freeze(), 0)
        run.assert_called_once_with(
            verify.FREEZE_RUN, headless=True, seconds=60, instances=3, user_args=["--port=23457"]
        )
        self.assertTrue((ROOT / verify.FREEZE_RUN).is_file())

    def test_the_stall_run_is_one_headless_process_on_three_free_ports(self) -> None:
        with (
            mock.patch.object(verify, "free_udp_port", return_value=23458) as pick,
            mock.patch.object(verify.launch, "main", return_value=0) as run,
        ):
            self.assertEqual(verify.stall(), 0)
        pick.assert_called_once_with(count=3)
        run.assert_called_once_with(
            verify.STALL_RUN, headless=True, seconds=60, instances=1, user_args=["--port=23458"]
        )
        self.assertTrue((ROOT / verify.STALL_RUN).is_file())

    def test_the_webrtc_twins_run_headless_on_a_port_free_for_tcp_too(self) -> None:
        cases = (
            (verify.webrtc, verify.WEBRTC_RUN, 3),
            (verify.webrtc_freeze, verify.WEBRTC_FREEZE_RUN, 3),
            (verify.webrtc_stall, verify.WEBRTC_STALL_RUN, 1),
            (verify.webrtc_silence, verify.WEBRTC_SILENCE_RUN, 1),
        )
        for step, target, instances in cases:
            with (
                self.subTest(target),
                mock.patch.object(verify, "free_udp_port", return_value=23459) as pick,
                mock.patch.object(verify.launch, "main", return_value=0) as run,
            ):
                self.assertEqual(step(), 0)
                pick.assert_called_once_with(tcp=True)
                run.assert_called_once_with(
                    target, headless=True, seconds=60, instances=instances, user_args=["--port=23459"]
                )
                self.assertTrue((ROOT / target).is_file())
        self.assertEqual(verify.LANES["godot"].index("webrtc"), verify.LANES["godot"].index("stall") + 1)

    def test_the_chaos_step_runs_one_fixed_seed_of_the_short_match(self) -> None:
        with mock.patch.object(verify.bots, "chaos", return_value=0) as run:
            self.assertEqual(verify.chaos(), 0)
        run.assert_called_once_with(seed=verify.CHAOS_SEED)
        self.assertLess(verify.LANES["godot"].index("bots-enet"), verify.LANES["godot"].index("chaos"))

    def test_the_webrtc_bots_and_chaos_run_the_enet_scenario_and_seed_after_their_enet_twins(self) -> None:
        with mock.patch.object(verify.bots, "main", return_value=0) as run:
            self.assertEqual(verify.bots_webrtc(), 0)
        run.assert_called_once_with(
            [verify.BOTS_ENET_SCENARIO], instances=verify.BOTS_ENET_INSTANCES, transport="webrtc"
        )
        with mock.patch.object(verify.bots, "chaos", return_value=0) as chaos:
            self.assertEqual(verify.chaos_webrtc(), 0)
        chaos.assert_called_once_with(seed=verify.CHAOS_SEED, transport="webrtc")
        godot = verify.LANES["godot"]
        self.assertEqual(godot.index("bots-webrtc"), godot.index("bots-enet") + 1)
        self.assertEqual(godot.index("chaos-webrtc"), godot.index("chaos") + 1)
        self.assertIn("bots-webrtc", verify.REASON_STEPS)
        self.assertIn("chaos-webrtc", verify.REASON_STEPS)

    def test_the_bots_run_every_scenario_in_one_process_then_one_over_enet(self) -> None:
        with mock.patch.object(verify.bots, "main", return_value=0) as run:
            self.assertEqual(verify.bots_one_process(), 0)
            self.assertEqual(verify.bots_enet(), 0)
        self.assertEqual(
            run.call_args_list,
            [mock.call(), mock.call([verify.BOTS_ENET_SCENARIO], instances=verify.BOTS_ENET_INSTANCES)],
        )
        self.assertTrue((ROOT / "content" / "scenarios" / f"{verify.BOTS_ENET_SCENARIO}.tres").is_file())


class FreePortTest(unittest.TestCase):
    def test_a_port_held_by_someone_else_is_skipped(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as held:
            held.bind(("127.0.0.1", 0))
            taken = held.getsockname()[1]
            # A second port the OS just handed out and took back: free, and not `taken` while `held` is open.
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.bind(("127.0.0.1", 0))
                free = probe.getsockname()[1]
            picks = iter([taken, free])
            self.assertEqual(verify.free_udp_port(lambda _ports: next(picks)), free)

    def test_with_a_count_every_port_of_the_run_must_bind(self) -> None:
        held = {20001}
        picks = iter([20000, 20005])
        with mock.patch.object(verify, "_binds", side_effect=lambda port: port not in held):
            self.assertEqual(verify.free_udp_port(lambda _ports: next(picks), count=2), 20005)

    def test_with_tcp_a_port_must_bind_for_tcp_too(self) -> None:
        tcp_held = {20000}
        picks = iter([20000, 20005])

        def binds(port: int, kind: int = socket.SOCK_DGRAM) -> bool:
            return kind != socket.SOCK_STREAM or port not in tcp_held

        with mock.patch.object(verify, "_binds", side_effect=binds):
            self.assertEqual(verify.free_udp_port(lambda _ports: next(picks), tcp=True), 20005)

    def test_the_last_port_of_a_run_stays_in_the_range(self) -> None:
        offered: list[range] = []

        def last(ports: range) -> int:
            offered.append(ports)
            return ports[-1]

        with mock.patch.object(verify, "_binds", return_value=True):
            port = verify.free_udp_port(last, count=3)
        self.assertEqual(port + 2, verify.ENET_PORTS[-1])
        self.assertEqual(offered[0].start, verify.ENET_PORTS.start)

    def test_the_port_is_outside_the_ephemeral_ranges(self) -> None:
        port = verify.free_udp_port()
        self.assertIn(port, verify.ENET_PORTS)
        self.assertLess(max(verify.ENET_PORTS), 32768)

    def test_no_free_port_fails_by_saying_so(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as held:
            held.bind(("127.0.0.1", 0))
            taken = held.getsockname()[1]
            with self.assertRaises(Failure) as caught:
                verify.free_udp_port(lambda _ports: taken)
        self.assertIn("no free UDP port", str(caught.exception))


class SelftestCommandTest(unittest.TestCase):
    """`selftest --group` (#349): CI's minimum-Python job runs only the tests that start no Godot."""

    def test_the_group_reaches_selftest_and_defaults_to_all(self) -> None:
        with mock.patch.object(verify, "selftest", return_value=0) as run:
            self.assertEqual(cli.main(["selftest"]), 0)
            self.assertEqual(cli.main(["selftest", "--group", "python"]), 0)
            self.assertEqual(cli.main(["selftest", "--group", "godot"]), 0)
        self.assertEqual(run.call_args_list, [mock.call("all"), mock.call("python"), mock.call("godot")])

    def test_another_group_is_refused(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            cli.build_parser().parse_args(["selftest", "--group", "unit"])


if __name__ == "__main__":
    unittest.main()
