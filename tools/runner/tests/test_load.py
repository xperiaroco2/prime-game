"""`load` (#388): bounded busy loops in a verify slot. Real lock files in a temporary folder and a fake clock for the
slot; real busy-loop processes of a fraction of a second for the loops."""

import json
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Callable
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock

from runner import cli, load, slots
from runner.common import Failure, group_kwargs, kill_tree
from runner.tests.test_slots import FakeClock


class LoadCase(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.where = Path(tmp.name) / "verify-slots"
        self.said: list[str] = []

    def pool(self, count: int, name: str, kind: str = slots.VERIFY, max_wait: float = 150.0) -> slots.Pool:
        fake = FakeClock()
        pool = slots.Pool(self.where, count, max_wait, kind=kind, me={"worktree": f"D:/wt/{name}", "branch": None},
                          clock=fake.clock, sleep=fake.sleep, say=self.said.append)  # fmt: skip
        self.addCleanup(pool.release)
        return pool

    @staticmethod
    def recorder(started: list[int]) -> Callable[[int, float], int]:
        def run(loops: int, seconds: float) -> int:
            started.append(loops)
            return 0

        return run

    def main(self, *args: object, **kwargs: object) -> tuple[int, str]:
        out = StringIO()
        with redirect_stdout(out):
            rc = load.main(*args, **kwargs)  # type: ignore[arg-type]
        return rc, out.getvalue()


class SlotTest(LoadCase):
    def test_the_loops_run_while_the_load_run_holds_a_slot_and_the_slot_is_free_after(self) -> None:
        seen: list[tuple[int, float, object, object]] = []

        def loops(count: int, seconds: float) -> int:
            holder = json.loads((self.where / "slot-1.json").read_text(encoding="utf-8"))
            seen.append((count, seconds, holder["kind"], self.pool(1, "probe").try_take()))
            return 0

        rc, out = self.main(3, 5.0, pool=lambda: (self.pool(1, "loaded", slots.LOAD), ""), loop_runner=loops)
        self.assertEqual(rc, 0)
        self.assertEqual(seen, [(3, 5.0, "load", None)])  # the slot is held by the load run while its loops run
        self.assertIn("load: slot 1 of 1, waited 0.0s", out)
        self.assertEqual((self.where / "slot-1.json").read_text(encoding="utf-8"), "")
        self.assertIsNotNone(self.pool(1, "next").try_take())

    def test_no_slot_within_the_wait_starts_nothing_and_fails(self) -> None:
        self.pool(1, "verifying").acquire()
        started: list[int] = []
        rc, out = self.main(
            2, 5.0, pool=lambda: (self.pool(1, "loaded", slots.LOAD), ""), loop_runner=self.recorder(started)
        )
        self.assertEqual(rc, 1)
        self.assertEqual(started, [])
        self.assertIn("load: FAILED: no verify slot within 150s; nothing started", out)
        self.assertTrue(any("this load run does not start" in line for line in self.said), self.said)

    def test_a_failing_slot_folder_does_not_stop_the_load(self) -> None:
        self.where.parent.mkdir(parents=True, exist_ok=True)
        self.where.write_text("a file where the folder should be", encoding="utf-8")
        started: list[int] = []
        rc, _ = self.main(
            2, 5.0, pool=lambda: (self.pool(1, "loaded", slots.LOAD), ""), loop_runner=self.recorder(started)
        )
        self.assertEqual((rc, started), (0, [2]))
        self.assertTrue(any("this load run runs without a slot" in line for line in self.said), self.said)

    def test_without_slots_the_load_runs_and_says_why(self) -> None:
        rc, out = self.main(2, 5.0, pool=lambda: (None, "no limit on CI"), loop_runner=lambda n, s: 0)
        self.assertEqual(rc, 0)
        self.assertIn("load: no limit on CI; no verify slot taken", out)

    def test_the_real_pool_is_a_load_runs(self) -> None:
        pool, why = slots.for_verify({}, env={slots.DIR_VAR: str(self.where)}, kind=slots.LOAD)
        assert pool is not None
        self.assertEqual((pool.kind, why), (slots.LOAD, ""))


class ArgsTest(unittest.TestCase):
    def test_the_bounds(self) -> None:
        for loops, seconds in ((0, 5.0), (load.MAX_LOOPS + 1, 5.0), (2, 0.0), (2, load.MAX_SECONDS + 1)):
            with self.subTest(loops=loops, seconds=seconds), self.assertRaises(Failure):
                load.check_args(loops, seconds)
        load.check_args(1, load.MAX_SECONDS)

    def test_bad_arguments_fail_before_any_slot_is_taken(self) -> None:
        asked: list[bool] = []

        def pool() -> tuple[slots.Pool | None, str]:
            asked.append(True)
            return None, ""

        with self.assertRaises(Failure):
            load.main(0, 5.0, pool=pool, loop_runner=lambda n, s: 0)
        self.assertEqual(asked, [])

    def test_two_loops_per_logical_cpu_by_default(self) -> None:
        self.assertEqual(load.default_loops(16), 32)  # #318 and #354's load on the engineer's PC
        self.assertEqual(load.default_loops(0), 2)

    def test_the_command_line(self) -> None:
        args = cli.build_parser().parse_args(["load", "--loops", "3", "--seconds", "90"])
        self.assertEqual((args.command, args.loops, args.seconds), ("load", 3, 90.0))
        args = cli.build_parser().parse_args(["load"])
        self.assertEqual((args.loops, args.seconds), (None, load.DEFAULT_SECONDS))


class LoopsTest(unittest.TestCase):
    def test_the_loops_stop_themselves_on_time(self) -> None:
        procs: list[subprocess.Popen[bytes]] = []

        def spawn(seconds: float) -> subprocess.Popen[bytes]:
            procs.append(load.spawn_loop(seconds))
            return procs[-1]

        out: list[str] = []
        with mock.patch.object(load, "GRACE", 60.0):  # a loaded PC can take seconds to start a Python process
            self.assertEqual(load.run_loops(2, 0.3, spawn=spawn, out=out.append), 0)
        self.assertEqual([proc.returncode for proc in procs], [0, 0])  # each ended by itself, none was stopped
        self.assertTrue(out[0].startswith("load: running 2 busy loops for 0.3s, until "), out)
        self.assertEqual(out[1:], ["load: done: 2 busy loops for 0.3s"])

    def test_a_loop_that_outlives_its_time_is_stopped(self) -> None:
        procs: list[subprocess.Popen[bytes]] = []

        def spawn(seconds: float) -> subprocess.Popen[bytes]:  # a loop that ignores its time
            code = "import time; time.sleep(120)"
            proc = subprocess.Popen([sys.executable, "-c", code], **group_kwargs())  # type: ignore[call-overload]
            procs.append(proc)
            return procs[-1]

        self.addCleanup(lambda: [kill_tree(p) for p in procs if p.poll() is None])
        fake = FakeClock()
        out: list[str] = []
        load.run_loops(1, 10.0, spawn=spawn, clock=fake.clock, sleep=fake.sleep, out=out.append)
        self.assertIsNotNone(procs[0].poll())
        self.assertGreaterEqual(fake.now - 1000.0, 10.0 + load.GRACE)
        self.assertIn("load: stopped 1 busy loops that outlived their 10s", out)

    def test_an_interrupted_load_stops_every_loop(self) -> None:
        procs: list[subprocess.Popen[bytes]] = []

        def spawn(seconds: float) -> subprocess.Popen[bytes]:
            procs.append(load.spawn_loop(seconds))
            return procs[-1]

        def interrupt(_: float) -> None:
            raise KeyboardInterrupt

        self.addCleanup(lambda: [kill_tree(p) for p in procs if p.poll() is None])
        with self.assertRaises(KeyboardInterrupt):
            load.run_loops(2, 120.0, spawn=spawn, sleep=interrupt, out=lambda _: None)
        self.assertEqual(len(procs), 2)
        self.assertTrue(all(proc.poll() is not None for proc in procs))


if __name__ == "__main__":
    unittest.main()
