"""`verify`: doctor, then the Python and the Godot lane at once (#179) with the headless ENet (#45), freeze (#70),
stall (#95), bots (#102), chaos (#188) and game (#149) runs in the Godot lane: their place, arguments and port (the game step's
command lines: test_hostjoin.GameCheckTest); each step's output whole, the summary, the history record; and
`selftest` in worker processes, counted against a serial discovery. Lanes here are stubs: a real lane would run
verify inside this test run."""

import ast
import contextlib
import io
import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
import uuid
from pathlib import Path
from unittest import mock

from runner import common, slots, verify
from runner.common import ROOT, Failure

GODOT_STEPS = ["check", "selftest-godot", "test", "enet", "freeze", "stall", "bots", "bots-enet", "chaos", "game"]


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
    for target, attribute, name in (
        (verify.doctor, "main", "doctor"),
        (verify.lint, "main", "lint"),
        (verify.check, "main", "check"),
        (verify.gdunit, "main", "test"),
        (verify, "enet", "enet"),
        (verify, "freeze", "freeze"),
        (verify, "stall", "stall"),
        (verify, "bots_one_process", "bots"),
        (verify, "bots_enet", "bots-enet"),
        (verify, "chaos", "chaos"),
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
            verify.lane_main(lane)
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

    def run(
        self,
        run_lane: verify.RunLane,
        *,
        doctor: int = 0,
        status: object = None,
        counted: tuple[list[str], str] = ([], "runner tests: 2 run and 0 skipped of 2; a serial run: 2 run of 2"),
        pool: slots.Pool | None = None,
    ) -> tuple[int, str, dict[str, object]]:
        out = io.StringIO()
        with (
            mock.patch.object(verify, "slot_pool", return_value=(pool, "no limit (a test)")) as self.slot_pool,
            mock.patch.object(verify.doctor, "main", return_value=doctor),
            mock.patch.object(verify, "git_status", side_effect=status if status is not None else [set(), set()]),
            mock.patch.object(
                verify, "count_after_lanes", return_value=(*counted, {"run": 2, "skipped": 0})
            ),
            mock.patch.object(
                verify, "git_facts", return_value={"branch": "b", "head": "h", "tree": "t", "runner": "r"}
            ),
            mock.patch.object(verify, "HISTORY", self.history),
            mock.patch.dict(os.environ),
            contextlib.redirect_stdout(out),
        ):
            rc = verify.main(run_lane=run_lane)
        lines = self.history.read_text(encoding="utf-8").splitlines()
        self.test.assertEqual(len(lines), 1, lines)
        return rc, out.getvalue(), json.loads(lines[0])


def summary_rows(text: str) -> list[tuple[str, str]]:
    rows = text[text.rindex("verify summary") :].splitlines()[1:]
    return [(row.split()[0], row.split()[1]) for row in rows if row.split()[0] in ("passed", "FAILED")]


class LaneTest(unittest.TestCase):
    def test_every_step_has_one_lane_and_the_godot_steps_stay_serial_in_one(self) -> None:
        self.assertEqual(verify.LANES["python"], ("lint", "selftest"))
        self.assertEqual(list(verify.LANES["godot"]), GODOT_STEPS)
        in_lanes = [name for names in verify.LANES.values() for name in names]
        self.assertEqual(sorted(["doctor", *in_lanes]), sorted(verify.STEP_ORDER))
        self.assertEqual(set(verify.steps()), set(verify.STEP_ORDER))

    def test_each_lane_runs_its_steps_in_order(self) -> None:
        for lane, names in verify.LANES.items():
            ran: list[str] = []
            with self.subTest(lane=lane), stub_steps(ran), contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(verify.lane_main(lane), 0)
            self.assertEqual(ran, list(names))
            marks = [
                json.loads(line[len(verify.MARK) :])
                for line in out.getvalue().splitlines()
                if line.startswith(verify.MARK)
            ]
            self.assertEqual([m["step"] for m in marks], list(names))

    def test_the_lanes_run_at_once(self) -> None:
        started = threading.Barrier(2, timeout=10)

        def run_lane(lane: str, names: tuple[str, ...], emit: verify.Emit) -> None:
            started.wait()  # breaks after 10 s unless the other lane runs at the same time
            fake_lane()(lane, names, emit)

        rc, _text, _record = Verify(self).run(run_lane)
        self.assertEqual(rc, 0)

    def test_a_failed_step_of_either_lane_fails_verify_and_the_others_still_run(self) -> None:
        for failing in ("lint", "selftest", *GODOT_STEPS):
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
        self.assertRegex(lanes, r"lanes: python [\d.]+s, godot [\d.]+s; \d+ CPUs, selftest on \d+ worker processes")
        self.assertIn("runner tests: 2 run and 0 skipped of 2", text)
        self.assertRegex(text.splitlines()[-1], r"^verify: passed in [\d.]+s$")
        self.assertEqual(set(record["lanes"]), {"python", "godot"})  # type: ignore[arg-type]

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
        self.assertEqual(calls, [[], ["godot", "python"]])
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
             "workers", "selftest", "slot"},  # fmt: skip
        )
        self.assertIsNone(record["slot"])  # no slot pool: CI, or a verify inside a verify
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
            verify.lane_main("godot")
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

    def test_only_the_test_step_has_a_detail(self) -> None:
        with (
            stub_steps(),
            mock.patch.object(verify.gdunit, "take_last_run", return_value={"shards": []}) as taken,
            contextlib.redirect_stdout(io.StringIO()) as out,
        ):
            verify.lane_main("godot")
        marks = [json.loads(line[len(verify.MARK) :]) for line in out.getvalue().splitlines()
                 if line.startswith(verify.MARK)]  # fmt: skip
        self.assertEqual([m["step"] for m in marks if "detail" in m], ["test"])
        taken.assert_called_once()

    def test_a_red_steps_first_failure_line(self) -> None:
        enet = ("  FAIL  enet_host_and_two_clients #1: exited 1 (log: tools/out/logs/run/x-1.log)\n"
                "        -> ERROR: NET instance 1 FAIL: no Welcome within 10 s\n"
                "        ->    at: push_error (core/variant/variant_utility.cpp:1024)\n")  # fmt: skip
        one_process = ("BOTS refusals: FAILED (seed 1) 2.0s\n  the host accepted a vote of a downed player\n"
                       "  FAIL  bots_main #1: exited 1 (log: tools/out/logs/run/bots_main-1.log)\n")  # fmt: skip
        cases = {
            BOTS_ENET_OUT: "bots_main #2: exited 1 (log: tools/out/logs/run/bots_main-2.log) | a Correction outside a "
            "placement (epoch 3, at (1.5, 0, -2)): an honest bot is never corrected",
            enet: "enet_host_and_two_clients #1: exited 1 (log: tools/out/logs/run/x-1.log) | "
            "ERROR: NET instance 1 FAIL: no Welcome within 10 s",
            one_process: "bots_main #1: exited 1 (log: tools/out/logs/run/bots_main-1.log) | "
            "the host accepted a vote of a downed player",
            "CHAOS seed 188001: FAILED (timeout, 900 ms)\n": "CHAOS seed 188001: FAILED (timeout, 900 ms)",
            "selftest\n  FAIL  runner.tests.test_x.T.test_y: AssertionError: 1 != 2\n        Traceback\n":
                "runner.tests.test_x.T.test_y: AssertionError: 1 != 2",
            "lint\nsomething went wrong\nlint: FAILED\n\n": "lint: FAILED",
            "": "",
        }  # fmt: skip
        for output, line in cases.items():
            with self.subTest(output=output[:30]):
                self.assertEqual(verify.first_failure(output), line)
        long = verify.first_failure("  FAIL  " + "x" * 1000)
        self.assertEqual(len(long), verify.gdunit.MESSAGE_CAP)

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
        self.assertEqual((rc, held), (0, [True, True]))
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
                "test_user_dir.RealUserDirTest",
            },
        )
        found = {".".join(t.id().split(".")[2:4]) for t in verify.discover() if verify.group_of(t) == "godot"}
        self.assertEqual(found, needs)

    def test_a_quarter_of_the_logical_cpus_at_least_one(self) -> None:
        self.assertEqual([verify.selftest_workers(n) for n in (1, 2, 4, 8, 16, 32)], [1, 1, 1, 2, 4, 8])

    def test_workers_report_each_outcome_like_a_serial_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            name = f"selftest_fixture_{uuid.uuid4().hex}"
            (Path(tmp) / f"{name}.py").write_text(FIXTURE, encoding="utf-8")
            sys.path.insert(0, tmp)  # the spawned workers get this process's sys.path
            self.addCleanup(sys.path.remove, tmp)
            names = ("test_passes", "test_fails", "test_skipped_by_a_decorator", "test_skipped_when_it_runs")
            ids = [f"{name}.T.{test}" for test in names]
            entries = {e["id"]: e for e in verify.run_in_workers(ids, 2)}
            serial = unittest.TestResult()
            unittest.defaultTestLoader.loadTestsFromName(f"{name}.T").run(serial)
            sys.modules.pop(name, None)
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
        self.assertEqual((serial.testsRun, len(serial.failures), len(serial.skipped)), (4, 1, 2))

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
            record = {"tests": [{"id": "fast", "seconds": 0.1}, {"id": "slow", "seconds": 9.0}]}
            (Path(tmp) / "selftest-python.json").write_text(json.dumps(record), encoding="utf-8")
            with mock.patch.object(verify, "LOGS", Path(tmp)):
                self.assertEqual(verify._slowest_first("python", ["fast", "slow", "new"]), ["new", "slow", "fast"])
                self.assertEqual(verify._slowest_first("godot", ["b", "a"]), ["b", "a"])

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

    def test_the_chaos_step_runs_one_fixed_seed_of_the_short_match(self) -> None:
        with mock.patch.object(verify.bots, "chaos", return_value=0) as run:
            self.assertEqual(verify.chaos(), 0)
        run.assert_called_once_with(seed=verify.CHAOS_SEED)
        self.assertLess(verify.LANES["godot"].index("bots-enet"), verify.LANES["godot"].index("chaos"))

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


if __name__ == "__main__":
    unittest.main()
