"""Noticing a machine that slept (#595): the two-clock Watch with injected clocks, its poll loop, the sleep counter and
the System log's last resume."""

import subprocess
import threading
import unittest
from datetime import UTC, datetime

from runner import suspend
from runner.common import IS_WINDOWS


class Clocks:
    """A wall clock and a monotonic clock that a test moves by hand."""

    def __init__(self) -> None:
        self.wall_t = 1_760_000_000.0
        self.mono_t = 5_000.0

    def wall(self) -> float:
        return self.wall_t

    def mono(self) -> float:
        return self.mono_t

    def run(self, seconds: float, slept: float = 0.0, mono_counts_sleep: bool = True) -> None:
        """`seconds` of work, then `slept` seconds of a sleeping machine: the wall clock counts both; the monotonic
        clock counts the sleep on Windows (QueryPerformanceCounter) and not on Linux (CLOCK_MONOTONIC)."""
        self.wall_t += seconds + slept
        self.mono_t += seconds + (slept if mono_counts_sleep else 0.0)


class WatchTest(unittest.TestCase):
    def setUp(self) -> None:
        self.clocks = Clocks()
        self.watch = suspend.Watch(self.clocks.wall, self.clocks.mono)

    def test_polls_a_few_seconds_apart_are_no_suspend(self) -> None:
        for _ in range(100):
            self.clocks.run(suspend.TICK)
            self.assertIsNone(self.watch.tick())

    def test_a_sleep_that_both_clocks_count_is_noticed_as_on_windows(self) -> None:
        self.clocks.run(suspend.TICK)
        self.assertIsNone(self.watch.tick())
        self.clocks.run(2.0, slept=37_277.0)  # 2026-10-08 20:59:58Z to 10-09 07:21:15Z
        self.assertEqual(self.watch.tick(), 37_279.0)
        self.clocks.run(suspend.TICK)
        self.assertIsNone(self.watch.tick(), "each gap is measured from the poll before it")

    def test_a_wall_clock_jump_past_the_monotonic_progress_is_noticed_as_on_linux(self) -> None:
        self.clocks.run(3.0, slept=600.0, mono_counts_sleep=False)
        self.assertEqual(self.watch.tick(), 603.0)

    def test_a_gap_just_under_the_limit_is_survived_and_one_at_it_is_not(self) -> None:
        self.clocks.run(suspend.SUSPEND_GAP - 1)
        self.assertIsNone(self.watch.tick())
        self.clocks.run(suspend.SUSPEND_GAP)
        self.assertEqual(self.watch.tick(), suspend.SUSPEND_GAP)

    def test_a_wall_clock_set_back_is_no_suspend(self) -> None:
        self.clocks.wall_t -= 3600
        self.clocks.mono_t += suspend.TICK
        self.assertIsNone(self.watch.tick())

    def test_the_message(self) -> None:
        self.assertEqual(suspend.message(38146.4), "the machine slept or was suspended (38146 s)")

    def test_the_gap_dwarfs_a_poll_and_stays_far_under_the_lane_timeout(self) -> None:
        from runner import verify, wait

        self.assertGreaterEqual(suspend.SUSPEND_GAP, 10 * max(suspend.TICK, wait.POLL_SECONDS))
        self.assertLessEqual(suspend.SUSPEND_GAP, verify.LANE_TIMEOUT / 10)


class RunWatchTest(unittest.TestCase):
    def test_it_polls_until_stopped_and_calls_back_once_at_the_first_suspend(self) -> None:
        clocks = Clocks()
        watch = suspend.Watch(clocks.wall, clocks.mono)
        gaps = iter([5.0, 5.0, 40_000.0, 5.0])
        polls: list[float] = []

        def stopped(tick: float) -> bool:
            polls.append(tick)
            clocks.run(next(gaps))
            return False

        found: list[float] = []
        suspend.run_watch(watch, found.append, stopped)
        self.assertEqual(found, [40_000.0])
        self.assertEqual(polls, [suspend.TICK] * 3, "it ends at the suspend")

    def test_a_stop_ends_it_without_a_callback(self) -> None:
        found: list[float] = []
        suspend.run_watch(suspend.Watch(), found.append, lambda _tick: True)
        self.assertEqual(found, [])

    def test_the_background_thread_ends_when_stopped(self) -> None:
        stop = threading.Event()
        thread = suspend.watch_in_background(lambda _gap: None, stop)
        self.assertTrue(thread.daemon)
        stop.set()
        thread.join(10)
        self.assertFalse(thread.is_alive())


class AsleepTest(unittest.TestCase):
    def test_the_sleep_counter_is_a_number_of_seconds_where_the_system_has_one(self) -> None:
        asleep = suspend.asleep_seconds()
        if asleep is None:
            self.assertFalse(IS_WINDOWS, "Windows always has the interrupt-time counters")
            return
        self.assertGreaterEqual(asleep, 0.0)
        later = suspend.asleep_seconds()
        assert later is not None
        self.assertLess(abs(later - asleep), suspend.SUSPEND_GAP, "it moves only while the machine sleeps")


class LastResumeTest(unittest.TestCase):
    XML = (
        "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider "
        "Name='Microsoft-Windows-Kernel-Power'/><EventID>507</EventID><TimeCreated "
        "SystemTime='2026-10-09T07:21:15.9113257Z'/></System><EventData><Data Name='SleepEntered'>true</Data>"
        "</EventData></Event>"
    )

    def test_the_newest_events_time_is_read(self) -> None:
        self.assertEqual(suspend.parse_resume(self.XML), datetime(2026, 10, 9, 7, 21, 15, tzinfo=UTC))
        self.assertIsNone(suspend.parse_resume(""))

    def test_the_query_asks_for_real_sleeps_only(self) -> None:
        self.assertIn("EventID=507", suspend.RESUME_QUERY)
        self.assertIn("EventID=107", suspend.RESUME_QUERY)
        self.assertIn("@Name='SleepEntered']='true'", suspend.RESUME_QUERY, "a screen that went off is no sleep")

    @unittest.skipUnless(IS_WINDOWS, "the System log is Windows'")
    def test_wevtutil_is_asked_for_one_event_newest_first(self) -> None:
        calls: list[list[str]] = []

        def run(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, self.XML, "")

        self.assertEqual(suspend.last_resume(run), datetime(2026, 10, 9, 7, 21, 15, tzinfo=UTC))
        self.assertEqual(calls[0][:3], ["wevtutil", "qe", "System"])
        self.assertIn("/c:1", calls[0])
        self.assertIn("/rd:true", calls[0])

    @unittest.skipUnless(IS_WINDOWS, "the System log is Windows'")
    def test_a_failing_or_missing_wevtutil_is_no_resume(self) -> None:
        def missing(*_args: object, **_kwargs: object) -> subprocess.CompletedProcess[str]:
            raise FileNotFoundError("wevtutil")

        self.assertIsNone(suspend.last_resume(missing))
        failed = subprocess.CompletedProcess([], 15007, "", "channel not found")
        self.assertIsNone(suspend.last_resume(lambda *_a, **_k: failed))

    @unittest.skipIf(IS_WINDOWS, "elsewhere there is no System log")
    def test_no_system_log_elsewhere(self) -> None:
        self.assertIsNone(suspend.last_resume(lambda *_a, **_k: self.fail("no process")))


if __name__ == "__main__":
    unittest.main()
