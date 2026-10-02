"""Machine-wide verify slots (#185): at most N `verify` runs at once on one PC, across every checkout.

Each slot is a lock file, `slot-<i>.lock`, in a machine-local folder outside every checkout (folder()), so the main
checkout and every worktree share them. A run takes a slot with an operating-system lock on its file (msvcrt on
Windows, flock elsewhere): the system releases it when the process ends, however it ends, so the lock of a process
that is gone (killed by a tool timeout, Ctrl+C, a crash) is free again at once and the next run takes it. Beside each
lock, `slot-<i>.json` names its holder (worktree, branch, pid, since): the waiting run prints it every minute, and a
holder file that was never cleared when its slot is taken again names a run that ended without releasing it (a
reclaimed slot).

The wait is bounded (max_wait): an agent's foreground shell call dies at 600 s, and a verify that first waited
longer would be killed before it ended. After max_wait the run goes ahead without a slot, with a loud warning that
the summary and the history record repeat: a slot never skips or weakens a step, it only orders the runs.
"""

from __future__ import annotations

import contextlib
import json
import os
import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from .common import IS_WINDOWS, Failure

# The number of slots, the longest wait in seconds, and the folder of the lock files; each overrides the default.
COUNT_VAR = "PRIME_VERIFY_SLOTS"
WAIT_VAR = "PRIME_VERIFY_SLOT_WAIT"
DIR_VAR = "PRIME_VERIFY_SLOTS_DIR"
DEFAULT_COUNT = 2
# An agent's foreground shell call (Claude Code's Bash tool) is killed at 600 s, and agents run verify (and publish,
# which runs it) in the foreground: the longest wait plus a verify run must end before that. VERIFY_RUN is a verify's
# wall time on the engineer's PC with DEFAULT_COUNT runs at once (measured for #185, see its PR).
AGENT_CALL_LIMIT = 600.0
VERIFY_RUN = 420.0
DEFAULT_WAIT = 150.0
# How often a waiting run tries the slots again, and how often it says who holds them.
POLL = 2.0
REPORT_EVERY = 60.0

if IS_WINDOWS:
    import msvcrt

    def _lock(fd: int) -> bool:
        os.lseek(fd, 0, os.SEEK_SET)
        try:
            msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
        except OSError:
            return False
        return True

    def _unlock(fd: int) -> None:
        os.lseek(fd, 0, os.SEEK_SET)
        with contextlib.suppress(OSError):
            msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)

else:
    import fcntl

    def _lock(fd: int) -> bool:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return False
        return True

    def _unlock(fd: int) -> None:
        with contextlib.suppress(OSError):
            fcntl.flock(fd, fcntl.LOCK_UN)


def folder(env: dict[str, str] | os._Environ[str] = os.environ) -> Path:
    """The machine-local folder of the lock files: %LOCALAPPDATA%\\prime-game\\verify-slots on Windows, else
    $XDG_CACHE_HOME (or ~/.cache)/prime-game/verify-slots; DIR_VAR replaces it."""
    if env.get(DIR_VAR):
        return Path(env[DIR_VAR])
    if IS_WINDOWS:
        base = Path(env.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
    else:
        base = Path(env.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return base / "prime-game" / "verify-slots"


def setting(env: dict[str, str] | os._Environ[str], name: str, default: float) -> float:
    """A non-negative number from the environment, else the default (a wrong value is named, never ignored)."""
    raw = env.get(name, "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        raise Failure(f"{name}={raw!r} is not a number") from None
    if value < 0:
        raise Failure(f"{name}={raw!r} is below zero")
    return value


@dataclass
class Holder:
    """Who holds a slot, as its holder file says."""

    slot: int
    worktree: str = "?"
    branch: str | None = None
    pid: int | None = None
    since: str = "?"

    def line(self) -> str:
        what = f"{self.worktree} ({self.branch or 'detached'}, pid {self.pid}, since {self.since})"
        return f"slot {self.slot}: {what}"


@dataclass
class Taken:
    """The outcome of a wait for a slot: the slot (None: the run went ahead without one), the seconds waited, and the
    holders of slots this run took over from a run that ended without releasing them."""

    count: int
    slot: int | None
    waited: float
    reclaimed: list[Holder] = field(default_factory=list)
    holders: list[Holder] = field(default_factory=list)  # who held every slot when the wait ran out

    @property
    def over(self) -> bool:
        return self.slot is None

    def record(self) -> dict[str, object]:
        """The history record's `slot` entry."""
        return {
            "slot": self.slot,
            "of": self.count,
            "waited": round(self.waited, 1),
            "over": self.over,
            "reclaimed": len(self.reclaimed),
        }

    def summary(self) -> str:
        if self.over:
            return (
                f"slot: NONE of {self.count} after waiting {self.waited:.1f}s: ran over the limit "
                f"(held by {'; '.join(h.line() for h in self.holders) or 'unknown'})"
            )
        return f"slot: {self.slot} of {self.count}, waited {self.waited:.1f}s for a verify slot"


class Pool:
    """`count` slots in `where`. Clock, sleep and say are injectable so a test waits without waiting."""

    def __init__(
        self,
        where: Path,
        count: int,
        max_wait: float,
        *,
        me: dict[str, object] | None = None,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
        say: Callable[[str], None] = print,
        poll: float = POLL,
        every: float = REPORT_EVERY,
    ) -> None:
        if count < 1:
            raise ValueError(f"a pool needs at least one slot, not {count}")
        self.where = where
        self.count = count
        self.max_wait = max_wait
        self.me = me or {}
        self.clock = clock
        self.sleep = sleep
        self.say = say
        self.poll = poll
        self.every = every
        self._fd: int | None = None
        self._slot: int | None = None

    def _lock_path(self, slot: int) -> Path:
        return self.where / f"slot-{slot}.lock"

    def _holder_path(self, slot: int) -> Path:
        return self.where / f"slot-{slot}.json"

    def holder(self, slot: int) -> Holder | None:
        """The holder file of a slot; None when it is empty or unreadable."""
        try:
            data = json.loads(self._holder_path(slot).read_text(encoding="utf-8") or "null")
        except (OSError, ValueError):
            return None
        if not isinstance(data, dict):
            return None
        pid = data.get("pid")
        return Holder(
            slot=slot,
            worktree=str(data.get("worktree", "?")),
            branch=data.get("branch") if isinstance(data.get("branch"), str) else None,
            pid=pid if isinstance(pid, int) else None,
            since=str(data.get("since", "?")),
        )

    def holders(self) -> list[Holder]:
        """The holder files of every slot, as last written (a slot being taken may still name its last holder)."""
        return [h or Holder(slot) for h in (self.holder(slot) for slot in range(1, self.count + 1))]

    def _write_holder(self, slot: int, data: dict[str, object] | None) -> None:
        path = self._holder_path(slot)
        tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
        tmp.write_text(json.dumps(data) if data else "", encoding="utf-8")
        os.replace(tmp, path)

    def try_take(self) -> tuple[int, Holder | None] | None:
        """Take the first free slot: (slot, the holder it reclaimed from or None), or None when all are held."""
        self.where.mkdir(parents=True, exist_ok=True)
        for slot in range(1, self.count + 1):
            fd = os.open(self._lock_path(slot), os.O_RDWR | os.O_CREAT, 0o644)
            if not _lock(fd):
                os.close(fd)
                continue
            left = self.holder(slot)  # a holder file nobody cleared: its run ended without releasing the slot
            self._fd, self._slot = fd, slot
            since = datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")
            with contextlib.suppress(OSError):  # the holder file only names the holder; the lock is the slot
                self._write_holder(slot, {**self.me, "pid": os.getpid(), "since": since})
            return slot, left
        return None

    def acquire(self) -> Taken:
        """Wait for a slot, saying every `every` seconds who holds them; after max_wait go ahead without one."""
        started = self.clock()
        next_report = started
        while True:
            got = self.try_take()
            now = self.clock()
            if got is not None:
                slot, left = got
                taken = Taken(self.count, slot, now - started, [left] if left else [])
                if left:
                    self.say(
                        f"  warn  verify slot {slot} was left by a run that ended without releasing it "
                        f"({left.line()}); taken over"
                    )
                return taken
            if now - started >= self.max_wait:
                holders = self.holders()
                self.say(
                    f"  WARN  no verify slot after {now - started:.0f}s (all {self.count} held); this verify runs "
                    f"OVER THE LIMIT, beside {self.count} others, so the timing-sensitive steps (freeze, stall) are "
                    f"less reliable. Holders: {'; '.join(h.line() for h in holders)}"
                )
                return Taken(self.count, None, now - started, holders=holders)
            if now >= next_report:
                held = "; ".join(h.line() for h in self.holders())
                self.say(
                    f"verify: waiting for a slot ({self.count} of {self.count} held; waited {now - started:.0f}s, at "
                    f"most {self.max_wait:.0f}s): {held}"
                )
                next_report = now + self.every
            self.sleep(min(self.poll, started + self.max_wait - now))

    def release(self) -> None:
        """Clear the holder file, then free the slot (the system frees it anyway when the process ends)."""
        if self._fd is None or self._slot is None:
            return
        with contextlib.suppress(OSError):
            self._write_holder(self._slot, None)
        _unlock(self._fd)
        os.close(self._fd)
        self._fd, self._slot = None, None

    @contextlib.contextmanager
    def held(self) -> Iterator[Taken]:
        """acquire(), and release() however the body ends."""
        taken = self.acquire()
        try:
            yield taken
        finally:
            self.release()


def for_verify(
    me: dict[str, object],
    *,
    env: dict[str, str] | os._Environ[str] = os.environ,
    ci: bool = False,
    inside: bool = False,
    say: Callable[[str], None] = print,
) -> tuple[Pool | None, str]:
    """The pool a verify run waits on, or None with the reason: CI (one run per runner), a verify inside a verify
    (the outer run holds the slot), or COUNT_VAR=0."""
    if ci:
        return None, "no limit on CI"
    if inside:
        return None, "no slot inside a verify (the outer run holds one)"
    count = int(setting(env, COUNT_VAR, DEFAULT_COUNT))
    if count == 0:
        return None, f"no limit ({COUNT_VAR}=0)"
    wait = setting(env, WAIT_VAR, DEFAULT_WAIT)
    return Pool(folder(env), count, wait, me=me, say=say), ""
