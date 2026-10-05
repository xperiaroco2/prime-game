"""Machine-wide verify slots (#185): real lock files in a temporary folder, a fake clock for the waits, and a child
process that takes a slot and is killed for the stale reclaim."""

import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Callable
from contextlib import redirect_stderr, redirect_stdout
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest import mock

from runner import cli, slots
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
             kind: str = slots.VERIFY) -> slots.Pool:  # fmt: skip
        fake = clock or FakeClock()
        pool = slots.Pool(
            self.where, count, max_wait, kind=kind, me={"worktree": f"D:/wt/{name}", "branch": f"tooling/1-{name}"},
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
        self.assertEqual(holder["kind"], "verify")
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

    def test_with_the_default_wait_a_run_gets_the_slot_the_longest_measured_need_freed(self) -> None:
        # #388: with 95 s this run went ahead over the limit; the default wait now covers every wait the verify
        # history needed (slots.NEEDED), so it gets the slot its holder frees.
        holder = self.pool(count=1, name="busy")
        holder.acquire()
        env = {slots.COUNT_VAR: "1", slots.DIR_VAR: str(self.where)}
        pool, _ = slots.for_verify({"worktree": "D:/wt/late"}, env=env, say=self.said.append)
        assert pool is not None
        self.addCleanup(pool.release)
        fake = FakeClock()
        pool.clock, pool.sleep = fake.clock, fake.sleep
        fake.at.append((fake.now + max(slots.NEEDED), holder.release))
        taken = pool.acquire()
        self.assertEqual((taken.slot, taken.over), (1, False))
        self.assertGreaterEqual(taken.waited, max(slots.NEEDED))
        reports = [line for line in self.said if line.startswith("verify: waiting for a slot")]
        self.assertEqual(len(reports), 9, self.said)  # at 0, 60, ..., 480 s
        self.assertIn(f"at most {slots.DEFAULT_WAIT:.0f}s", reports[0])

    def test_past_the_default_wait_the_run_still_goes_ahead_and_says_so(self) -> None:
        self.pool(count=1, name="stuck").acquire()
        env = {slots.COUNT_VAR: "1", slots.DIR_VAR: str(self.where)}
        pool, _ = slots.for_verify({}, env=env, say=self.said.append)
        assert pool is not None
        fake = FakeClock()
        pool.clock, pool.sleep = fake.clock, fake.sleep
        taken = pool.acquire()
        self.assertTrue(taken.over)
        self.assertAlmostEqual(taken.waited, slots.DEFAULT_WAIT)
        self.assertTrue(any("this verify runs OVER THE LIMIT" in line and "D:/wt/stuck" in line for line in self.said))

    def test_a_zero_wait_never_sleeps(self) -> None:
        self.pool(count=1, name="busy").acquire()
        fake = FakeClock()
        self.assertTrue(self.pool(count=1, max_wait=0, name="now", clock=fake).acquire().over)
        self.assertEqual(fake.slept, [])


class LoadRunTest(SlotsCase):
    """#388: a load run (`load`) takes a slot like a verify run, so the verify runs see it."""

    def test_a_load_run_holds_a_slot_that_a_waiting_verify_names(self) -> None:
        load = self.pool(count=1, name="loaded", kind=slots.LOAD)
        self.assertEqual(load.acquire().slot, 1)
        self.assertEqual(json.loads((self.where / "slot-1.json").read_text(encoding="utf-8"))["kind"], "load")
        fake = FakeClock()
        fake.at.append((fake.now + 70, load.release))
        taken = self.pool(count=1, name="verifying", clock=fake).acquire()
        self.assertEqual((taken.slot, taken.over), (1, False))
        reports = [line for line in self.said if line.startswith("verify: waiting for a slot")]
        self.assertEqual(len(reports), 2, self.said)
        for line in reports:
            self.assertIn("slot 1: load run in D:/wt/loaded (tooling/1-loaded, pid", line)

    def test_a_load_run_counts_against_the_slots_of_the_verify_runs(self) -> None:
        self.pool(count=2, name="verify").acquire()
        self.pool(count=2, name="loaded", kind=slots.LOAD).acquire()
        taken = self.pool(count=2, max_wait=30, name="third", clock=FakeClock()).acquire()
        self.assertTrue(taken.over)
        self.assertEqual([h.kind for h in taken.holders], [slots.VERIFY, slots.LOAD])
        self.assertIn("slot 2: load run in D:/wt/loaded", taken.summary())

    def test_a_load_run_waits_like_a_verify_and_past_the_wait_says_it_does_not_start(self) -> None:
        self.pool(count=1, name="busy").acquire()
        taken = self.pool(count=1, max_wait=150, name="loaded", clock=FakeClock(), kind=slots.LOAD).acquire()
        self.assertTrue(taken.over)
        self.assertAlmostEqual(taken.waited, 150.0)
        self.assertTrue(any(line.startswith("load: waiting for a slot") for line in self.said), self.said)
        warning = next(line for line in self.said if "WARN" in line)
        self.assertIn("this load run does not start", warning)
        self.assertNotIn("OVER THE LIMIT", warning)

    def test_a_holder_file_without_a_kind_is_a_verify(self) -> None:
        # Holder files written before #388 name no kind.
        self.where.mkdir(parents=True)
        (self.where / "slot-1.json").write_text(json.dumps({"worktree": "D:/wt/old", "pid": 7}), encoding="utf-8")
        holder = self.pool(count=1, name="reader").holder(1)
        assert holder is not None
        self.assertEqual(holder.kind, slots.VERIFY)
        self.assertEqual(holder.line(), "slot 1: D:/wt/old (detached, pid 7, since ?)")

    def test_a_pool_knows_only_verify_and_load_runs(self) -> None:
        with self.assertRaises(ValueError):
            slots.Pool(self.where, 1, 1, kind="perf")
        pool, _ = slots.for_verify({}, env={slots.DIR_VAR: str(self.where)}, kind=slots.LOAD)
        assert pool is not None
        self.assertEqual((pool.kind, pool.max_wait), (slots.LOAD, slots.DEFAULT_WAIT))


class HoldersTest(SlotsCase):
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


NOW = datetime(2026, 10, 5, 12, 0, tzinfo=UTC)


class QuietTest(SlotsCase):
    """#416: `slots --quiet <hours>` leaves one slot to the new runs of every checkout until its end time."""

    def env(self, count: str = "2") -> dict[str, str]:
        return {slots.DIR_VAR: str(self.where), slots.COUNT_VAR: count}

    def quiet(self, arg: str, now: datetime = NOW) -> list[str]:
        out: list[str] = []
        me = {"worktree": "D:/prime-game", "branch": "main"}
        self.assertEqual(slots.quiet_command(arg, self.env(), now=now, me=me, out=out.append), 0)
        return out

    def verify_pool(self, now: datetime, max_wait: float = 30.0, kind: str = slots.VERIFY) -> slots.Pool:
        pool, why = slots.for_verify({"worktree": "D:/wt/late", "branch": None}, env=self.env(), say=self.said.append,
                                     now=now, kind=kind)  # fmt: skip
        assert pool is not None, why
        self.addCleanup(pool.release)
        fake = FakeClock()
        pool.clock, pool.sleep, pool.max_wait = fake.clock, fake.sleep, max_wait
        return pool

    def test_quiet_hours_writes_one_slot_and_its_end_into_the_shared_folder(self) -> None:
        out = self.quiet("3")
        data = json.loads((self.where / slots.QUIET_FILE).read_text(encoding="utf-8"))
        self.assertEqual(
            data,
            {"until": "2026-10-05T15:00:00Z", "since": "2026-10-05T12:00:00Z", "slots": 1,
             "worktree": "D:/prime-game", "branch": "main"},
        )  # fmt: skip
        self.assertIn("slots: quiet until 2026-10-05T15:00:00Z", out[0])
        self.assertIn("take 1 of the 2 slots", out[0])
        self.assertEqual(self.where, slots.folder(self.env()))  # the folder every checkout's verify reads

    def test_a_verify_in_a_quiet_window_takes_one_slot_and_says_so_in_its_slot_line(self) -> None:
        self.quiet("3")
        pool = self.verify_pool(NOW + timedelta(hours=1))
        self.assertEqual((pool.count, pool.configured), (1, 2))
        taken = pool.acquire()
        self.assertEqual(taken.slot, 1)
        note = "quiet window until 2026-10-05T15:00:00Z: 1 of 2 slots"
        self.assertEqual(taken.summary(), f"slot: 1 of 1 ({note}), waited 0.0s for a verify slot")
        self.assertEqual(taken.record()["quiet"], note)

    def test_in_a_quiet_window_a_second_run_waits_although_slot_2_is_free(self) -> None:
        self.quiet("3")
        self.pool(count=2, name="first").acquire()  # slot 1
        taken = self.verify_pool(NOW + timedelta(hours=1)).acquire()
        self.assertTrue(taken.over)
        self.assertIn("quiet window until 2026-10-05T15:00:00Z", taken.summary())
        waiting = [line for line in self.said if line.startswith("verify: waiting for a slot")]
        self.assertTrue(waiting and "1 of 1 held; quiet window until" in waiting[0], self.said)
        self.assertNotIn("slot 2", waiting[0])  # no new run takes the second slot in a quiet window

    def test_a_run_holding_slot_2_when_the_window_starts_keeps_it(self) -> None:
        self.pool(count=2, name="a").acquire()
        second = self.pool(count=2, name="b")
        self.assertEqual(second.acquire().slot, 2)
        self.quiet("1")
        self.assertIsNone(self.verify_pool(NOW).try_take())
        self.assertEqual(self.pool(count=2, name="reader").holder(2).worktree, "D:/wt/b")  # type: ignore[union-attr]

    def test_a_run_already_waiting_when_the_window_starts_does_not_take_slot_2(self) -> None:
        self.pool(count=2, name="a").acquire()
        second = self.pool(count=2, name="b")
        second.acquire()  # both slots held: the late run waits
        late = self.verify_pool(NOW, max_wait=30.0)
        fake = FakeClock()
        late.clock, late.sleep = fake.clock, fake.sleep
        fake.at.append((fake.now + 10, lambda: self.quiet("3")))
        fake.at.append((fake.now + 20, second.release))  # slot 2 frees inside the window
        taken = late.acquire()
        self.assertTrue(taken.over, taken.summary())  # it did not take slot 2
        self.assertEqual((late.count, late.configured), (1, 2))
        self.assertIn("1 of 2 slots", taken.summary())
        self.assertTrue(any("began while waiting" in line for line in self.said), self.said)
        self.assertIsNone(late.holder(2))  # slot 2 stays free for the engineer's own use

    def test_a_run_waiting_when_no_window_starts_still_takes_slot_2(self) -> None:
        self.pool(count=2, name="a").acquire()
        second = self.pool(count=2, name="b")
        second.acquire()
        late = self.verify_pool(NOW, max_wait=30.0)
        fake = FakeClock()
        late.clock, late.sleep = fake.clock, fake.sleep
        fake.at.append((fake.now + 20, second.release))
        self.assertEqual(late.acquire().slot, 2)
        self.assertFalse(any("quiet" in line for line in self.said), self.said)

    def test_a_load_run_in_a_quiet_window_takes_one_slot_too(self) -> None:
        self.quiet("2")
        pool = self.verify_pool(NOW, kind=slots.LOAD)
        self.assertEqual((pool.kind, pool.count), (slots.LOAD, 1))

    def test_quiet_off_ends_the_window(self) -> None:
        self.quiet("3")
        ended = "slots: quiet window ended; new verify and load runs take any of the 2 slots again"
        self.assertEqual(self.quiet("off"), [ended])
        self.assertFalse((self.where / slots.QUIET_FILE).exists())
        self.assertEqual(self.verify_pool(NOW).count, 2)
        self.assertEqual(self.quiet("OFF"), ["slots: no quiet window to end"])

    def test_a_new_window_replaces_the_last(self) -> None:
        self.quiet("3")
        self.quiet("0.5", now=NOW + timedelta(hours=1))
        quiet = slots.read_quiet(self.where, now=NOW + timedelta(hours=1))
        assert quiet is not None
        self.assertEqual(slots.stamp(quiet.until), "2026-10-05T13:30:00Z")

    def test_an_expired_quiet_file_is_ignored_with_a_warning(self) -> None:
        self.quiet("1")
        pool = self.verify_pool(NOW + timedelta(hours=1, seconds=1))
        self.assertEqual((pool.count, pool.quiet), (2, None))
        self.assertTrue(any("warn" in line and "the quiet window ended at 2026-10-05T13:00:00Z" in line
                            for line in self.said), self.said)  # fmt: skip
        self.assertNotIn("quiet", pool.acquire().summary())

    def test_an_unreadable_or_malformed_quiet_file_is_ignored_with_a_warning(self) -> None:
        far = slots.stamp(NOW + timedelta(hours=slots.MAX_QUIET_HOURS + 1))
        for text in ("", "{", "[]", '{"slots": 1}', '{"until": "soon"}', json.dumps({"until": far})):
            with self.subTest(text=text):
                self.where.mkdir(parents=True, exist_ok=True)
                (self.where / slots.QUIET_FILE).write_text(text, encoding="utf-8")
                self.said.clear()
                self.assertEqual(self.verify_pool(NOW).count, 2)
                self.assertTrue(any("warn" in line and "ignored" in line for line in self.said), self.said)
        (self.where / slots.QUIET_FILE).unlink()
        (self.where / slots.QUIET_FILE).mkdir()  # a quiet "file" that cannot be read as one
        self.said.clear()
        self.assertEqual(self.verify_pool(NOW).count, 2)
        self.assertTrue(any("cannot be read" in line for line in self.said), self.said)

    def test_no_quiet_file_is_no_window_and_no_warning(self) -> None:
        self.assertEqual(self.verify_pool(NOW).count, 2)
        self.assertEqual(self.said, [])

    def test_the_hours_are_bounded(self) -> None:
        for arg in ("0", "-1", "24.5", "nan", "inf", "three", ""):
            with self.subTest(arg=arg), self.assertRaisesRegex(Failure, "--quiet"):
                self.quiet(arg)
        self.assertFalse(self.where.exists())
        self.quiet(str(slots.MAX_QUIET_HOURS))
        self.assertIsNotNone(slots.read_quiet(self.where, now=NOW + timedelta(hours=23)))


class WaiterTest(SlotsCase):
    """#416: a waiting run names itself in a waiter file while it waits, and while it runs without a slot."""

    def waiters(self) -> list[slots.Waiter]:
        return slots.read_waiters(self.where)

    def test_a_waiting_run_has_a_waiter_file_until_it_takes_a_slot(self) -> None:
        holder = self.pool(count=1, name="busy")
        holder.acquire()
        seen: list[list[slots.Waiter]] = []
        fake = FakeClock()
        fake.at.append((fake.now + 10, lambda: seen.append(self.waiters())))
        fake.at.append((fake.now + 20, holder.release))
        taken = self.pool(count=1, name="waiting", clock=fake).acquire()
        self.assertEqual(taken.slot, 1)
        found = [(w.worktree, w.branch, w.pid, w.kind, w.state) for w in seen[0]]
        self.assertEqual(found, [("D:/wt/waiting", "tooling/1-waiting", os.getpid(), slots.VERIFY, slots.WAITING)])
        self.assertEqual(self.waiters(), [])

    def test_a_verify_over_the_limit_keeps_its_file_until_it_ends(self) -> None:
        self.pool(count=1, name="busy").acquire()
        late = self.pool(count=1, max_wait=30, name="late", clock=FakeClock())
        self.assertTrue(late.acquire().over)
        self.assertEqual([w.state for w in self.waiters()], [slots.OVER])
        late.release()
        self.assertEqual(self.waiters(), [])

    def test_a_load_run_past_the_wait_and_a_failing_folder_leave_no_waiter_file(self) -> None:
        self.pool(count=1, name="busy").acquire()
        self.assertTrue(self.pool(count=1, max_wait=30, name="load", clock=FakeClock(), kind=slots.LOAD).acquire().over)
        self.assertEqual(self.waiters(), [])

    def test_a_run_that_takes_a_slot_at_once_writes_no_waiter_file(self) -> None:
        self.pool(name="a").acquire()
        self.assertEqual([p.name for p in self.where.iterdir() if p.name.startswith(slots.WAITER_PREFIX)], [])


class StatusTest(SlotsCase):
    """#416: `slots --status`."""

    def setUp(self) -> None:
        super().setUp()
        self.history = self.where.parent / "verify-history.jsonl"

    def status(self, now: datetime = NOW, alive: Callable[[int], bool] | None = None) -> list[str]:
        out: list[str] = []
        env = {slots.DIR_VAR: str(self.where), slots.COUNT_VAR: "2"}
        rc = slots.status(env, now=now, alive=alive or (lambda pid: pid == os.getpid()),
                          histories=lambda: [self.history], out=out.append)  # fmt: skip
        self.assertEqual(rc, 0)
        return out

    def test_an_empty_folder_shows_free_slots_and_no_waiters(self) -> None:
        out = self.status()
        self.assertEqual(out[1:], [
            "quiet: none (slots --quiet <hours> starts one)",
            "holders:",
            "  slot 1: free",
            "  slot 2: free",
            "waiters: none",
            "without a slot in the last hour (verify history): none",
            "slots: no run waits for a slot (0 of 2 held)",
        ])  # fmt: skip
        self.assertIn(str(self.where), out[0])

    def test_holders_waiters_and_the_quiet_window(self) -> None:
        holder = self.pool(count=1, name="busy")
        holder.acquire()
        now = datetime.now(UTC)  # the waiter file is stamped with the real time, and a stale one is left out
        slots.write_quiet(self.where, 2, now=now - timedelta(minutes=30), me={"worktree": "D:/prime-game"})
        left = json.dumps({"worktree": "D:/wt/killed", "pid": 999999})
        (self.where / "slot-2.json").write_text(left, encoding="utf-8")
        seen: list[list[str]] = []
        fake = FakeClock()
        fake.at.append((fake.now + 10, lambda: seen.append(self.status(now=datetime.now(UTC)))))
        fake.at.append((fake.now + 20, holder.release))
        self.pool(count=1, name="waiting", clock=fake).acquire()
        out = seen[0]
        until = slots.stamp(now + timedelta(minutes=90))
        quiet = f"quiet: until {until} (90 min left): a new verify or load run takes 1 of 2 slots"
        self.assertIn(quiet, out[1])
        self.assertTrue(out[3].startswith(f"  slot 1: D:/wt/busy (tooling/1-busy, pid {os.getpid()}, since "), out)
        self.assertEqual(out[4], "  slot 2: free (its last holder, pid 999999 in D:/wt/killed, ended without "
                                 "releasing it; the next run takes it over)")  # fmt: skip
        self.assertEqual(out[5], "waiters: 1")
        waiter = f"verify in D:/wt/waiting (tooling/1-waiting, pid {os.getpid()}) waiting for a slot since"
        self.assertIn(waiter, out[6])
        self.assertEqual(out[-1], "slots: 1 run(s) waiting for a slot (1 of 2 held): launch nothing now")

    def test_a_run_over_the_limit_shows_until_it_ends_and_is_no_waiter(self) -> None:
        self.pool(count=1, name="busy").acquire()
        late = self.pool(count=1, max_wait=30, name="late", clock=FakeClock())
        late.acquire()
        out = self.status()
        self.assertIn("waiters: none", out)
        at = out.index("running without a slot now: 1")
        self.assertIn("verify in D:/wt/late (tooling/1-late", out[at + 1])
        self.assertIn("running OVER THE LIMIT, without a slot, since", out[at + 1])
        self.assertEqual(out[-1], "slots: 1 running over the limit (1 of 2 held): launch nothing now")
        late.release()
        out = self.status()
        self.assertNotIn("running without a slot now: 1", out)
        self.assertTrue(out[-1].startswith("slots: no run waits for a slot"))

    def test_the_file_of_a_killed_waiter_is_left_out_and_removed(self) -> None:
        self.where.mkdir(parents=True)
        stale = self.where / f"{slots.WAITER_PREFIX}999999-dead.json"
        stale.write_text(json.dumps({"worktree": "D:/wt/killed", "pid": 999999, "since": "2026-10-05T11:00:00Z",
                                     "state": slots.WAITING}), encoding="utf-8")  # fmt: skip
        out = self.status()
        self.assertIn("waiters: none", out)
        self.assertFalse(stale.exists())

    def test_a_waiting_file_older_than_its_wait_is_a_ghost_even_when_its_pid_lives(self) -> None:
        # The run was killed while it waited and Windows gave its pid to a long-lived process: the pid looks alive.
        self.where.mkdir(parents=True)

        def waiter(name: str, since: datetime, state: str, wait: float | None) -> Path:
            data: dict[str, object] = {"worktree": f"D:/wt/{name}", "pid": os.getpid(), "since": slots.stamp(since),
                                       "state": state}  # fmt: skip
            if wait is not None:
                data["wait"] = wait
            path = self.where / f"{slots.WAITER_PREFIX}{os.getpid()}-{name}.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            return path

        margin = timedelta(seconds=slots.STALE_MARGIN)
        ghost = waiter("ghost", NOW - timedelta(seconds=600) - margin - timedelta(seconds=5), slots.WAITING, 600)
        no_wait = waiter("nowait", NOW - timedelta(seconds=slots.DEFAULT_WAIT) - margin * 2, slots.WAITING, None)
        fresh = waiter("fresh", NOW - timedelta(seconds=500), slots.WAITING, 600)
        patient = waiter("patient", NOW - timedelta(seconds=900), slots.WAITING, 3600)  # a longer wait, its own
        over = waiter("over", NOW - timedelta(hours=2), slots.OVER, 600)  # a verify runs as long as it runs
        out = self.status()
        self.assertIn("waiters: 2", out)
        self.assertEqual([ghost.exists(), no_wait.exists()], [False, False])
        self.assertTrue(fresh.exists() and patient.exists() and over.exists())
        self.assertIn("running without a slot now: 1", out)

    def test_the_last_hours_runs_without_a_slot_come_from_the_verify_history(self) -> None:
        def run(start: str, slot: object, seconds: float = 400.0, status: str = "passed") -> dict[str, object]:
            return {"start": start, "worktree": "D:/wt/x", "branch": "tooling/9-x", "status": status,
                    "seconds": seconds, "slot": slot}  # fmt: skip

        over = {"slot": None, "of": 2, "waited": 600.0, "over": True, "reclaimed": 0}
        records = [
            run("2026-10-05T10:00:00Z", over),  # ended 10:16:40, before the hour
            run("2026-10-05T10:45:00Z", over, status="FAILED"),  # ended 11:01:40
            run("2026-10-05T11:40:00Z", {"slot": 1, "of": 2, "waited": 3.0, "over": False, "reclaimed": 0}),
            run("2026-10-05T11:50:00Z", None),  # CI or no limit: no slot record
            run("2026-10-05T11:30:00Z", {"slot": None, "of": 2, "waited": 0.0, "over": True, "reclaimed": 0,
                                         "error": "OSError: denied"}),  # fmt: skip
        ]
        self.history.parent.mkdir(parents=True, exist_ok=True)
        self.history.write_text("".join(json.dumps(r) + "\n" for r in records) + "not json\n", encoding="utf-8")
        out = self.status()
        at = out.index("without a slot in the last hour (verify history): 2")
        self.assertEqual(out[at + 1:at + 3], [
            "  2026-10-05T10:45:00Z D:/wt/x (tooling/9-x): over the limit, FAILED in 400.0 s after waiting 600.0 s",
            "  2026-10-05T11:30:00Z D:/wt/x (tooling/9-x): the slot folder failed, passed in 400.0 s after waiting "
            "0.0 s",
        ])  # fmt: skip

    def test_with_no_limit_it_says_so(self) -> None:
        out: list[str] = []
        env = {slots.DIR_VAR: str(self.where), slots.COUNT_VAR: "0"}
        slots.status(env, now=NOW, histories=lambda: [], out=out.append)
        self.assertIn("no limit", out[0])
        self.assertIn("  none (no limit)", out)


class CommandTest(unittest.TestCase):
    """#416: the `slots` command line."""

    def run_cli(self, *argv: str) -> tuple[int, str]:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        out = io.StringIO()
        with mock.patch.dict(os.environ, {slots.DIR_VAR: tmp.name, slots.COUNT_VAR: "2"}), redirect_stdout(out):
            rc = cli.main(["slots", *argv])
            rc2 = cli.main(["slots", "--status"])
        return rc, out.getvalue() + f"\nstatus rc={rc2}"

    def test_quiet_then_status(self) -> None:
        rc, out = self.run_cli("--quiet", "2")
        self.assertEqual(rc, 0, out)
        self.assertIn("slots: quiet until", out)
        self.assertIn("quiet: until", out)
        self.assertIn("status rc=0", out)

    def test_a_wrong_hours_value_fails(self) -> None:
        rc, out = self.run_cli("--quiet", "100")
        self.assertEqual(rc, 1, out)

    def test_status_or_quiet_is_required_and_not_both(self) -> None:
        for argv in ([], ["--status", "--quiet", "1"]):
            with self.subTest(argv=argv), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                cli.build_parser().parse_args(["slots", *argv])

    def test_the_help_describes_status_and_quiet(self) -> None:
        parser = dict(next(a for a in cli.build_parser()._actions if hasattr(a, "choices") and a.choices
                           and "slots" in a.choices).choices)["slots"]  # fmt: skip
        text = " ".join(parser.format_help().split())
        for phrase in ("--status", "holders (worktree, branch, pid, since)", "waiting for a slot", "last hour",
                       "over the limit", "verify history", "--quiet <hours>", "one slot", "--quiet off",
                       "expired", "ignored"):  # fmt: skip
            self.assertIn(phrase, text)


class SettingsTest(unittest.TestCase):
    def test_the_folder_is_machine_local_and_outside_every_checkout(self) -> None:
        env = {"LOCALAPPDATA": "C:/Users/x/AppData/Local", "XDG_CACHE_HOME": "/home/x/.cache"}
        where = slots.folder(env)
        self.assertEqual(where.parts[-2:], ("prime-game", "verify-slots"))
        self.assertFalse(where.is_relative_to(ROOT))
        self.assertTrue(str(where).startswith(str(Path(env["LOCALAPPDATA" if os.name == "nt" else "XDG_CACHE_HOME"]))))
        self.assertEqual(slots.folder({slots.DIR_VAR: "E:/locks"}), Path("E:/locks"))

    def test_the_environment_overrides_the_count_and_the_wait(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        env = {slots.COUNT_VAR: "3", slots.WAIT_VAR: "40", slots.DIR_VAR: tmp.name}
        pool, why = slots.for_verify({}, env=env)
        assert pool is not None
        self.assertEqual((pool.count, pool.max_wait, pool.where, why), (3, 40.0, Path(tmp.name), ""))
        # Only the folder is the test's own: a quiet window on this PC (#416) would lower the real folder's count.
        pool, _ = slots.for_verify({}, env={slots.DIR_VAR: tmp.name})
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

    def test_the_default_wait_covers_the_measured_waits_and_fits_a_background_run(self) -> None:
        # #388: the longest wait covers every wait an over-limit run of the verify history needed for a slot, and the
        # whole wait plus the slowest green slotted verify still ends within a background command's limit. (Until
        # #388 it had to fit an agent's 600 s foreground call; agents run verify in the background since #303.)
        self.assertGreaterEqual(slots.DEFAULT_WAIT, max(slots.NEEDED))
        self.assertLessEqual(slots.DEFAULT_WAIT + slots.SLOWEST_GREEN, slots.BACKGROUND_LIMIT)


if __name__ == "__main__":
    unittest.main()
