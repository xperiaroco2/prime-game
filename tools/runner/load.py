"""`load`: bounded busy loops an agent starts on purpose to test something under load (#388).

#318 and #354 tested `playcheck` and the bots under an all-core load with hand-written loops (32 busy Python processes
on 16 logical CPUs), which the verify slots (#185, `slots`) could not see: the verify runs of the other tracks went on
two at a time beside them and ran slow and red. This command makes such a load visible: it first takes a verify slot
like a verify run (the same wait, the same waiting line), so while it runs one verify fewer runs beside it and every
waiting run names it ("load run in ..."). Past the longest wait it does not start (exit 1): a load run is no gate, and
starting it would make the slotted verify runs run over the limit. On CI, or with PRIME_VERIFY_SLOTS=0, it runs
without a slot.

Each loop is its own Python process that ends by itself at most the given seconds after it starts. A killed runner
(a tool timeout, Ctrl+C) frees its slot at once, while its loops may run out their time without a slot; so the longest
load (MAX_SECONDS) plus the longest wait for a slot fits Claude Code's default limit for a background command, and a
load started in the background with that default is never killed by it. The runner also stops every loop that
outlives its time by GRACE. An agent starts `load` in the background, waits for its `load: running` line, runs what it
tests, and lets the load end (or waits for it with `wait <log>`).
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

from . import slots
from .common import IS_CI, ROOT, Failure, git, group_kwargs, kill_tree, say

# One busy loop: spins until its own deadline, whatever happens to the runner that started it.
BUSY = "import sys, time\nend = time.monotonic() + float(sys.argv[1])\nwhile time.monotonic() < end:\n    pass\n"
# Two loops per logical CPU, as #318 and #354 measured with (32 on 16): every core busy, the scheduler's queue full.
LOOPS_PER_CPU = 2
MAX_LOOPS = 256
DEFAULT_SECONDS = 600.0
# How long past its time a loop may run before the runner stops it, and how often the runner looks.
GRACE = 5.0
POLL = 0.5
# Python's start-up, git and the slot folder before the wait, and starting the loops after it.
START_MARGIN = 55.0
# A load is a bounded test aid: the whole wait for a slot, the loops, their grace and the margin fit Claude Code's
# default limit for a background command (half an hour), so the runner is not killed while its loops still run.
MAX_SECONDS = slots.BACKGROUND_LIMIT - slots.DEFAULT_WAIT - GRACE - START_MARGIN

Spawn = Callable[[float], "subprocess.Popen[bytes]"]


def default_loops(cpus: int | None = None) -> int:
    return LOOPS_PER_CPU * max(1, cpus if cpus is not None else os.cpu_count() or 1)


def spawn_loop(seconds: float) -> subprocess.Popen[bytes]:
    return subprocess.Popen(
        [sys.executable, "-c", BUSY, repr(seconds)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        **group_kwargs(),  # type: ignore[arg-type]
    )


def run_loops(
    loops: int,
    seconds: float,
    *,
    spawn: Spawn = spawn_loop,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
    out: Callable[[str], None] = say,
) -> int:
    """Start the loops, wait for them to stop themselves, and stop any that outlive their time by GRACE (or every one
    when the wait is interrupted)."""
    procs: list[subprocess.Popen[bytes]] = []
    try:
        for _ in range(loops):
            procs.append(spawn(seconds))
        until = (datetime.now(UTC) + timedelta(seconds=seconds)).isoformat(timespec="seconds").replace("+00:00", "Z")
        out(f"load: running {loops} busy loops for {seconds:g}s, until {until}")
        started = clock()
        while any(proc.poll() is None for proc in procs) and clock() - started < seconds + GRACE:
            sleep(POLL)
    finally:
        late = [proc for proc in procs if proc.poll() is None]
        for proc in late:
            kill_tree(proc)
    if late:
        out(f"load: stopped {len(late)} busy loops that outlived their {seconds:g}s")
    out(f"load: done: {loops} busy loops for {seconds:g}s")
    return 0


def check_args(loops: int, seconds: float) -> None:
    if not 1 <= loops <= MAX_LOOPS:
        raise Failure(f"--loops {loops}: give 1 to {MAX_LOOPS}")
    if not 0 < seconds <= MAX_SECONDS:
        raise Failure(f"--seconds {seconds:g}: give more than 0 and at most {MAX_SECONDS:.0f}")


def own_pool() -> tuple[slots.Pool | None, str]:
    branch = git("rev-parse", "--abbrev-ref", "HEAD").out.strip()
    me: dict[str, object] = {"worktree": ROOT.as_posix(), "branch": None if branch in ("", "HEAD") else branch}
    return slots.for_verify(me, ci=IS_CI, say=say, kind=slots.LOAD)


def main(
    loops: int | None = None,
    seconds: float = DEFAULT_SECONDS,
    *,
    pool: Callable[[], tuple[slots.Pool | None, str]] = own_pool,
    loop_runner: Callable[[int, float], int] = run_loops,
) -> int:
    count = default_loops() if loops is None else loops
    check_args(count, seconds)
    got, why = pool()
    if got is None:
        say(f"load: {why}; no verify slot taken")
        return loop_runner(count, seconds)
    with got.held() as taken:
        if taken.error is not None:
            return loop_runner(count, seconds)  # the slot folder failed: the warning said so; a slot never stops work
        if taken.over:
            say(f"load: FAILED: no verify slot within {taken.waited:.0f}s; nothing started. Start it again later")
            return 1
        say(f"load: slot {taken.slot} of {taken.count}, waited {taken.waited:.1f}s for a verify slot")
        return loop_runner(count, seconds)
