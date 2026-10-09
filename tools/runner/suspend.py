"""Noticing a machine that slept (#595): `verify` and `wait` stop at once after a resume, `slots --status` marks a
holder from before it.

On 2026-10-08 the laptop entered Modern Standby at 20:59:58Z and woke for good at 07:21:15Z. Every verify in flight
then reported a step of about 38,000 s and ended hours after the night's queue should have run: its lane timeout
(LANE_TIMEOUT, a threading.Timer) never fired, because a Windows wait does not count the time the machine sleeps,
while time.monotonic (QueryPerformanceCounter) and the wall clock do. On Linux it is the other way round:
time.monotonic stops while the machine is suspended and the wall clock jumps. So a Watch compares two polls with both
clocks: a poll that comes SUSPEND_GAP or more after the one before it, by either clock, while its caller only slept a
few seconds, means the machine slept (or the process was stopped, or the clock was set far ahead). A short sleep of the
machine below SUSPEND_GAP goes unnoticed on purpose: a run survives it.

asleep_seconds() is how long the machine has slept since it booted (Windows: the interrupt time minus the unbiased
interrupt time, which Modern Standby stops too, measured on the laptop on 2026-10-09; Linux: CLOCK_BOOTTIME minus
CLOCK_MONOTONIC; macOS: CLOCK_MONOTONIC minus CLOCK_UPTIME_RAW). A slot holder records it when it takes its slot, so
`slots --status` sees whether the machine slept since. last_resume() reads the newest resume from sleep in the Windows
System log, for a holder written by a runner before #595.
"""

from __future__ import annotations

import ctypes
import re
import subprocess
import threading
import time
from collections.abc import Callable
from datetime import UTC, datetime

from .common import IS_WINDOWS

# The gap between two polls that only a sleeping (or stopped) machine makes: polls come every TICK seconds, and a
# loaded PC delays a sleeping thread by seconds, not minutes.
SUSPEND_GAP = 120.0
TICK = 5.0
# The System log query of last_resume: Kernel-Power 507 (Modern Standby ended) where the machine really slept (a
# screen that only went off logs 507 too, with SleepEntered false), or 107 (a resume from S3 or hibernation).
RESUME_QUERY = (
    "*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=507 or EventID=107)] and "
    "(EventData[Data[@Name='SleepEntered']='true'] or System[EventID=107])]"
)
SYSTEM_TIME = re.compile(r"SystemTime='(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?Z'")
LOG_TIMEOUT = 15.0


def message(seconds: float) -> str:
    """The words every runner command prints for a suspend it noticed."""
    return f"the machine slept or was suspended ({seconds:.0f} s)"


class Watch:
    """Two clocks read at each poll; tick() returns the gap since the last poll when it is SUSPEND_GAP or more."""

    def __init__(
        self,
        wall: Callable[[], float] = time.time,
        mono: Callable[[], float] = time.monotonic,
        gap: float = SUSPEND_GAP,
    ) -> None:
        self.wall, self.mono, self.gap = wall, mono, gap
        self.last = (wall(), mono())

    def tick(self) -> float | None:
        wall, mono = self.wall(), self.mono()
        jump = max(wall - self.last[0], mono - self.last[1])
        self.last = (wall, mono)
        return jump if jump >= self.gap else None


def run_watch(
    watch: Watch, on_suspend: Callable[[float], None], stopped: Callable[[float], bool], tick: float = TICK
) -> None:
    """Poll every `tick` seconds until stopped(tick) (which waits that long) is true; at the first suspend call
    on_suspend with its seconds and end."""
    while not stopped(tick):
        gap = watch.tick()
        if gap is not None:
            on_suspend(gap)
            return


def watch_in_background(on_suspend: Callable[[float], None], stop: threading.Event) -> threading.Thread:
    """run_watch in a daemon thread until `stop` is set."""
    thread = threading.Thread(target=run_watch, args=(Watch(), on_suspend, stop.wait), daemon=True)
    thread.start()
    return thread


def asleep_seconds() -> float | None:
    """Seconds this machine has slept (or been suspended) since it booted, or None where that is not known."""
    try:
        if IS_WINDOWS:
            interrupt, unbiased = ctypes.c_ulonglong(), ctypes.c_ulonglong()
            ctypes.windll.kernelbase.QueryInterruptTime(ctypes.byref(interrupt))  # type: ignore[attr-defined]
            if not ctypes.windll.kernel32.QueryUnbiasedInterruptTime(ctypes.byref(unbiased)):  # type: ignore[attr-defined]
                return None
            return max(0.0, (interrupt.value - unbiased.value) / 1e7)  # both in 100 ns units
        if hasattr(time, "CLOCK_BOOTTIME"):
            return max(0.0, time.clock_gettime(time.CLOCK_BOOTTIME) - time.clock_gettime(time.CLOCK_MONOTONIC))
        if hasattr(time, "CLOCK_UPTIME_RAW"):
            return max(0.0, time.clock_gettime(time.CLOCK_MONOTONIC) - time.clock_gettime(time.CLOCK_UPTIME_RAW))
    except (AttributeError, OSError, ValueError):
        return None
    return None


def parse_resume(xml: str) -> datetime | None:
    """The newest event time in wevtutil's XML output (the query reads newest first), or None."""
    match = SYSTEM_TIME.search(xml)
    if not match:
        return None
    return datetime.fromisoformat(match.group(1)).replace(tzinfo=UTC)


def last_resume(run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run) -> datetime | None:
    """The newest resume from sleep in the Windows System log, or None (another system, or the log unreadable)."""
    if not IS_WINDOWS:
        return None
    command = ["wevtutil", "qe", "System", f"/q:{RESUME_QUERY}", "/c:1", "/rd:true", "/f:xml"]
    try:
        done = run(command, capture_output=True, text=True, timeout=LOG_TIMEOUT, errors="replace", check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return parse_resume(done.stdout or "") if done.returncode == 0 else None
