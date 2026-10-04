"""Machine-wide verify slots (#185): real lock files in a temporary folder, a fake clock for the waits, and a child
process that takes a slot and is killed for the stale reclaim."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path

from runner import slots
from runner.common import ROOT, Failure, kill_tree


class FakeClock:
    """A clock that only sleep() moves; `at` runs a callback once the clock reaches its time."""

    def __init__(self) -> None:
        self.now = 1000.0
        self.slept: list[float] = []
        self.at: list[tuple[float, Callable[[], None]]] = []

    def clock(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.slept.append(seconds)
        self.now += seconds
        for when, call in list(self.at):
            if self.now >= when:
                self.at.remove((when, call))
                call()


class SlotsCase(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.where = Path(tmp.name) / "verify-slots"
        self.said: list[str] = []

    def pool(self, count: int = 2, max_wait: float = 150.0, name: str = "me", clock: FakeClock | None = None,
             ) -> slots.Pool:  # fmt: skip
        fake = clock or FakeClock()
        pool = slots.Pool(
            self.where, count, max_wait, me={"worktree": f"D:/wt/{name}", "branch": f"tooling/1-{name}"},
            clock=fake.clock, sleep=fake.sleep, say=self.said.append,
        )  # fmt: skip
        self.addCleanup(pool.release)
        return pool


class AcquireTest(SlotsCase):
    def test_a_free_slot_is_taken_at_once_and_names_its_holder(self) -> None:
        taken = self.pool(name="a").acquire()
        self.assertEqual((taken.slot, taken.waited, taken.over, taken.reclaimed), (1, 0.0, False, []))
        holder = json.loads((self.where / "slot-1.json").read_text(encoding="utf-8"))
        self.assertEqual((holder["worktree"], holder["branch"], holder["pid"]), ("D:/wt/a", "tooling/1-a", os.getpid()))
        self.assertRegex(holder["since"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertEqual(taken.record(), {"slot": 1, "of": 2, "waited": 0.0, "over": False, "reclaimed": 0})

    def test_each_run_takes_its_own_slot_and_none_is_left_past_the_count(self) -> None:
        self.assertEqual(self.pool(name="a").acquire().slot, 1)
        self.assertEqual(self.pool(name="b").acquire().slot, 2)
        self.assertIsNone(self.pool(name="c").try_take())

    def test_a_released_slot_is_free_again_and_its_holder_file_cleared(self) -> None:
        first = self.pool(name="a")
        first.acquire()
        first.release()
        self.assertEqual((self.where / "slot-1.json").read_text(encoding="utf-8"), "")
        again = self.pool(name="b").acquire()
        self.assertEqual((again.slot, again.reclaimed), (1, []))  # a released slot is not a reclaimed one


class WaitTest(SlotsCase):
    def test_a_full_pool_waits_saying_every_minute_who_holds_the_slots(self) -> None:
        holder = self.pool(count=1, name="busy")
        holder.acquire()
        fake = FakeClock()
        fake.at.append((fake.now + 130, holder.release))
        taken = self.pool(count=1, name="waiting", clock=fake).acquire()
        self.assertEqual(taken.slot, 1)
        self.assertGreaterEqual(taken.waited, 130)
        self.assertLess(taken.waited, 130 + slots.POLL + 0.01)
        reports = [line for line in self.said if line.startswith("verify: waiting for a slot")]
        self.assertEqual(len(reports), 3, self.said)  # at 0, 60 and 120 s
        for line in reports:
            self.assertIn("slot 1: D:/wt/busy (tooling/1-busy, pid", line)
        self.assertTrue(all(s <= slots.POLL for s in fake.slept))

    def test_after_the_longest_wait_the_run_goes_ahead_without_a_slot_and_says_so(self) -> None:
        self.pool(count=1, name="busy").acquire()
        fake = FakeClock()
        taken = self.pool(count=1, max_wait=150, name="late", clock=fake).acquire()
        self.assertTrue(taken.over)
        self.assertIsNone(taken.slot)
        self.assertAlmostEqual(taken.waited, 150.0)
        self.assertEqual([h.worktree for h in taken.holders], ["D:/wt/busy"])
        self.assertTrue(any("OVER THE LIMIT" in line and "D:/wt/busy" in line for line in self.said), self.said)
        self.assertEqual(taken.record(), {"slot": None, "of": 1, "waited": 150.0, "over": True, "reclaimed": 0})
        self.assertIn("ran over the limit", taken.summary())

    def test_a_failing_slot_folder_lets_the_run_go_ahead_without_a_slot(self) -> None:
        self.where.parent.mkdir(parents=True, exist_ok=True)
        self.where.write_text("a file where the folder should be", encoding="utf-8")
        fake = FakeClock()
        taken = self.pool(count=1, name="unwritable", clock=fake).acquire()
        self.assertTrue(taken.over)
        self.assertIsNone(taken.slot)
        self.assertEqual(fake.slept, [])  # no wait on a folder that cannot hold a slot
        self.assertIsNotNone(taken.error)
        self.assertTrue(any("WARN" in line and str(self.where) in line for line in self.said), self.said)
        record = taken.record()
        self.assertEqual((record["slot"], record["over"], record["error"]), (None, True, taken.error))
        self.assertIn("ran without a slot", taken.summary())

    def test_holders_names_each_slot_with_an_empty_holder_for_a_free_one(self) -> None:
        # #324: a free slot (no holder file, or a cleared one) raised NameError instead of an empty holder.
        self.pool(count=3, name="a").acquire()
        released = self.pool(count=3, name="b")
        released.acquire()
        released.release()  # slot 2: its holder file cleared; slot 3: never written
        holders = self.pool(count=3, name="reader").holders()
        self.assertEqual([h.slot for h in holders], [1, 2, 3])
        self.assertEqual([h.worktree for h in holders], ["D:/wt/a", "?", "?"])
        self.assertEqual(holders[1], slots.Holder(2))
        self.assertEqual(holders[2].line(), "slot 3: ? (detached, pid None, since ?)")

    def test_a_full_pool_whose_holder_file_is_blank_still_waits_and_names_the_slot(self) -> None:
        # A held slot can have a blank holder file (its write failed, or a reader caught it half-written): the wait
        # reports it as unknown instead of crashing (#324).
        self.pool(count=1, name="busy").acquire()
        (self.where / "slot-1.json").write_text("", encoding="utf-8")
        taken = self.pool(count=1, max_wait=150, name="late", clock=FakeClock()).acquire()
        self.assertTrue(taken.over)
        self.assertEqual(taken.holders, [slots.Holder(1)])
        self.assertTrue(any(line.startswith("verify: waiting for a slot") and "slot 1: ?" in line
                            for line in self.said), self.said)  # fmt: skip

    def test_a_zero_wait_never_sleeps(self) -> None:
        self.pool(count=1, name="busy").acquire()
        fake = FakeClock()
        self.assertTrue(self.pool(count=1, max_wait=0, name="now", clock=fake).acquire().over)
        self.assertEqual(fake.slept, [])


class ReleaseTest(SlotsCase):
    def test_a_failing_run_releases_its_slot(self) -> None:
        pool = self.pool(count=1, name="red")
        with self.assertRaises(RuntimeError), pool.held() as taken:
            self.assertEqual(taken.slot, 1)
            raise RuntimeError("a step crashed")
        after = self.pool(count=1, name="next").acquire()
        self.assertEqual((after.slot, after.over, after.reclaimed), (1, False, []))

    def test_release_clears_the_holder_file_while_a_waiter_reads_it(self) -> None:
        # A waiting run reads the holder files for its minute report; on Windows a reader's open file cannot be
        # replaced by a rename, so the holder file must be cleared in place, or it would name a finished run.
        pool = self.pool(count=1, name="done")
        pool.acquire()
        with (self.where / "slot-1.json").open(encoding="utf-8"):
            pool.release()
        self.assertEqual((self.where / "slot-1.json").read_text(encoding="utf-8"), "")
        self.assertEqual(sorted(p.name for p in self.where.iterdir()), ["slot-1.json", "slot-1.lock"])
        after = self.pool(count=1, name="next").acquire()
        self.assertEqual((after.slot, after.reclaimed), (1, []))  # not a false reclaim

    def test_release_without_a_slot_does_nothing(self) -> None:
        self.pool().release()


class StaleTest(SlotsCase):
    def test_the_slot_of_a_killed_process_is_taken_over_and_named(self) -> None:
        code = (
            "import sys, time; from pathlib import Path; "
            f"sys.path.insert(0, {str(ROOT / 'tools')!r}); from runner import slots; "
            f"p = slots.Pool(Path({str(self.where)!r}), 1, 0, me={{'worktree': 'D:/wt/killed', 'branch': None}}); "
            "print('took', p.try_take(), flush=True); time.sleep(120)"
        )
        child = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, cwd=ROOT,
                                 env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})  # fmt: skip
        try:
            assert child.stdout is not None
            self.assertEqual(child.stdout.readline().decode().strip(), "took (1, None)")
            self.assertIsNone(self.pool(count=1, name="probe").try_take())  # held while the child lives
        finally:
            kill_tree(child)  # type: ignore[arg-type]
            if child.stdout is not None:
                child.stdout.close()
        pool = slots.Pool(self.where, 1, 10.0, me={"worktree": "D:/wt/next"}, say=self.said.append, poll=0.1)
        self.addCleanup(pool.release)
        taken = pool.acquire()  # the system frees a dead process's lock (on Windows within moments)
        self.assertEqual(taken.slot, 1)
        self.assertEqual([(h.worktree, h.pid) for h in taken.reclaimed], [("D:/wt/killed", child.pid)])
        self.assertTrue(any("ended without releasing it" in line for line in self.said), self.said)
        self.assertEqual(taken.record()["reclaimed"], 1)


class SettingsTest(unittest.TestCase):
    def test_the_folder_is_machine_local_and_outside_every_checkout(self) -> None:
        env = {"LOCALAPPDATA": "C:/Users/x/AppData/Local", "XDG_CACHE_HOME": "/home/x/.cache"}
        where = slots.folder(env)
        self.assertEqual(where.parts[-2:], ("prime-game", "verify-slots"))
        self.assertFalse(where.is_relative_to(ROOT))
        self.assertTrue(str(where).startswith(str(Path(env["LOCALAPPDATA" if os.name == "nt" else "XDG_CACHE_HOME"]))))
        self.assertEqual(slots.folder({slots.DIR_VAR: "E:/locks"}), Path("E:/locks"))

    def test_the_environment_overrides_the_count_and_the_wait(self) -> None:
        env = {slots.COUNT_VAR: "3", slots.WAIT_VAR: "40", slots.DIR_VAR: "E:/locks"}
        pool, why = slots.for_verify({}, env=env)
        assert pool is not None
        self.assertEqual((pool.count, pool.max_wait, pool.where, why), (3, 40.0, Path("E:/locks"), ""))
        pool, _ = slots.for_verify({}, env={})
        assert pool is not None
        self.assertEqual((pool.count, pool.max_wait), (slots.DEFAULT_COUNT, slots.DEFAULT_WAIT))

    def test_no_slots_on_ci_inside_a_verify_or_with_a_count_of_zero(self) -> None:
        self.assertEqual(slots.for_verify({}, env={}, ci=True), (None, "no limit on CI"))
        pool, why = slots.for_verify({}, env={}, inside=True)
        self.assertIsNone(pool)
        self.assertIn("outer run", why)
        self.assertEqual(slots.for_verify({}, env={slots.COUNT_VAR: "0"}), (None, f"no limit ({slots.COUNT_VAR}=0)"))

    def test_a_wrong_value_is_named(self) -> None:
        for raw in ("two", "-1", "1.5", "0.5"):
            with self.subTest(raw=raw), self.assertRaisesRegex(Failure, slots.COUNT_VAR):
                slots.for_verify({}, env={slots.COUNT_VAR: raw})

    def test_a_pool_needs_a_slot(self) -> None:
        with self.assertRaises(ValueError):
            slots.Pool(Path("x"), 0, 1)

    def test_the_default_wait_and_a_verify_fit_an_agents_shell_call(self) -> None:
        # An agent's foreground shell call dies at 600 s: the longest wait leaves room, with the margin, for the run
        # that then goes ahead over the limit (one more at once than the slots), the slowest one after a wait.
        self.assertGreater(slots.VERIFY_OVER, slots.VERIFY_RUN)
        self.assertLessEqual(slots.DEFAULT_WAIT + slots.VERIFY_OVER + slots.MARGIN, slots.AGENT_CALL_LIMIT)


if __name__ == "__main__":
    unittest.main()
