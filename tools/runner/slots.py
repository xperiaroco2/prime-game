"""Machine-wide verify slots (#185): at most N `verify` runs at once on one PC, across every checkout.

Each slot is a lock file, `slot-<i>.lock`, in a machine-local folder outside every checkout (folder()), so the main
checkout and every worktree share them. A run takes a slot with an operating-system lock on its file (msvcrt on
Windows, flock elsewhere): the system releases it when the process ends, however it ends, so the lock of a process
that is gone (killed by a tool timeout, Ctrl+C, a crash) is free again at once and the next run takes it. Beside each
lock, `slot-<i>.json` names its holder (worktree, branch, pid, since): the waiting run prints it every minute, and a
holder file that was never cleared when its slot is taken again names a run that ended without releasing it (a
reclaimed slot).

The wait is bounded (max_wait, #388: about one whole verify run on a loaded PC, so a slot frees within it unless a
holder is stuck). After max_wait the run goes ahead without a slot, with a loud warning that the summary and the
history record repeat: a slot never skips or weakens a step, it only orders the runs. Agents therefore run verify
in the background and poll it with `wait` (#303): a foreground shell call dies at 600 s, before a long wait and the
run after it end.

A load run (`load`, #388: bounded busy loops an agent starts on purpose to test under load, as #318 and #354 did)
takes a slot too, so the verify runs see it: while it runs, one verify fewer runs beside it, and the waiting line
names it ("load run in ..."). Past max_wait a load run does not start: unlike a verify, it is no gate, and it would
make the verify runs beside it run over the limit.

The `slots` command (#416, P2 of the weekly budget ADR) reads and quiets the slots. `slots --status` prints the holders,
the runs waiting for a slot (each waiting run keeps a `waiter-<pid>-<token>.json` in the folder while it waits, and,
when it goes ahead over the limit, until it ends) and the runs of the last hour that ran without a slot (from the verify
history files of the main checkout and its worktrees). `slots --quiet <hours>` writes `quiet.json` into the same
folder, so every checkout of the PC sees it: until its end time a new verify or load run takes one slot (QUIET_SLOTS),
and its slot line names the quiet window; `slots --quiet off` removes it. The quiet file fails safe: a missing,
unreadable, malformed or expired one, or one ending more than MAX_QUIET_HOURS ahead, is ignored (with a warning), and a
quiet window only lowers the count, so a run still waits at most max_wait and never waits for ever.
"""

from __future__ import annotations

import contextlib
import json
import math
import os
import time
import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path

from .common import IS_WINDOWS, ROOT, Failure, git

# The number of slots, the longest wait in seconds, and the folder of the lock files; each overrides the default.
COUNT_VAR = "PRIME_VERIFY_SLOTS"
WAIT_VAR = "PRIME_VERIFY_SLOT_WAIT"
DIR_VAR = "PRIME_VERIFY_SLOTS_DIR"
# Measured on the engineer's PC (8 cores, 16 logical CPUs; #185, 2026-10-02, with #182's four GdUnit4 shards and
# selftest's four workers, beside the other sessions' runs): k verify runs at once took 316 s (k = 1), 315 and 386 s
# (k = 2), 431 and 441 s (k = 3) and 452 s (k = 4) per batch, so 11, 19 to 23, 25 and 32 runs an hour. Two at once
# cost a run little and fill the 16 logical CPUs (2 x (4 shards + 4 workers)); a third or fourth makes every run a
# third longer and `test`, whose load-sensitive suites already fail under the other sessions' load, red more often.
# freeze, stall, enet and bots-enet stayed green.
DEFAULT_COUNT = 2
# The longest wait (#388). Until then it was 95 s, so that the wait and a verify fit an agent's foreground shell call
# (600 s); since #303 agents run verify and publish in the background and poll them with `wait`, so the wait no longer
# has to fit one call. With 95 s, `metrics` counted 11 runs over the limit in the agents' verify summaries to
# 2026-10-04 22:00 UTC, and the verify history files left (59 runs) 7, all on 2026-10-04 with three or four tracks
# verifying at once. Those seven were slow: 388 to 895 s (median 603 s) against a median of 359 s for the 51 slotted
# runs, and two were red (stall, selftest). For each of the five over-limit runs whose holders are in the history
# files, a slot freed NEEDED seconds after its wait began (the end of the earlier of the holders' runs): the longest
# wait covers all of them with a margin. A wait never needs longer than the rest of one holder's run, at most a whole
# verify on a loaded PC (45 of the 51 slotted runs took under 600 s); past that a holder is likely stuck, and the run
# goes ahead, as before. A run started in the background (Claude Code's default limit for a background command: 30
# minutes, BACKGROUND_LIMIT) still ends within it after the whole wait and the slowest green slotted run measured
# (SLOWEST_GREEN, 2026-10-04, three runs at once).
NEEDED = (207.0, 229.0, 341.0, 522.0, 536.0)
SLOWEST_GREEN = 960.0
BACKGROUND_LIMIT = 1800.0
DEFAULT_WAIT = 600.0
# What a slot's holder is: a verify run, or a load run (`load`).
VERIFY = "verify"
LOAD = "load"
# How often a waiting run tries the slots again, and how often it says who holds them.
POLL = 2.0
REPORT_EVERY = 60.0
# The quiet window (#416): its file in the slots folder, the slots a run may take while it lasts (one leaves half the
# PC to the engineer's own use, N3 (b) of the weekly budget ADR), and the longest window `slots --quiet` writes; a
# file that ends later than that (plus a minute for clocks) was not written by it and is ignored.
QUIET_FILE = "quiet.json"
QUIET_SLOTS = 1
MAX_QUIET_HOURS = 24.0
# A waiting run's file (#416), and the window of `slots --status`'s runs without a slot.
WAITER_PREFIX = "waiter-"
RECENT = 3600.0
# A waiter file in the WAITING state older than its run's wait plus this many seconds is a ghost (#416): its run was
# killed and Windows gave its pid to another process, so the pid looks alive. `slots --status` removes it.
STALE_MARGIN = 60.0
# What a waiter file says the run does: it waits for a slot, or it went ahead without one (a verify past max_wait).
WAITING = "waiting"
OVER = "over"


def stamp(moment: datetime) -> str:
    """A UTC time as the slot files write it: 2026-10-05T12:00:00Z."""
    return moment.astimezone(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_stamp(text: object) -> datetime | None:
    """A time the slot files wrote (ISO 8601; without a zone, UTC), or None."""
    if not isinstance(text, str) or not text.strip():
        return None
    try:
        moment = datetime.fromisoformat(text.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return moment if moment.tzinfo is not None else moment.replace(tzinfo=UTC)

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


def this_checkout() -> dict[str, object]:
    """This checkout and its branch, as a holder, waiter or quiet file names them."""
    branch = git("rev-parse", "--abbrev-ref", "HEAD").out.strip()
    return {"worktree": ROOT.as_posix(), "branch": None if branch in ("", "HEAD") else branch}


def configured_count(env: dict[str, str] | os._Environ[str] = os.environ) -> int:
    """The number of slots: COUNT_VAR, else DEFAULT_COUNT (0: no limit)."""
    value = setting(env, COUNT_VAR, DEFAULT_COUNT)
    # float(): DEFAULT_COUNT is an int, and int.is_integer() is new in Python 3.12 (the runner's minimum is 3.11).
    if not float(value).is_integer():  # 0.5 would truncate to 0, "no limit"
        raise Failure(f"{COUNT_VAR}={env.get(COUNT_VAR)!r} is not a whole number")
    return int(value)


@dataclass
class Quiet:
    """A quiet window (#416): until `until`, a new run takes at most QUIET_SLOTS slots."""

    until: datetime
    since: str = "?"
    worktree: str = "?"
    branch: str | None = None

    def note(self, count: int, configured: int) -> str:
        return f"quiet window until {stamp(self.until)}: {count} of {configured} slots"


def read_quiet(
    where: Path, *, now: datetime | None = None, say: Callable[[str], None] = print
) -> Quiet | None:
    """The quiet window in force, or None. Fails safe: a missing file is no window, and an unreadable, malformed or
    expired file, or one ending more than MAX_QUIET_HOURS ahead, is ignored with a warning (a quiet file never stops a
    run, nor holds the PC at one slot for ever)."""
    now = now or datetime.now(UTC)
    path = where / QUIET_FILE
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except OSError as exc:
        say(f"  warn  the quiet file {path} cannot be read ({exc}); ignored, no quiet window")
        return None
    try:
        data = json.loads(text)
    except ValueError:
        data = None
    until = parse_stamp(data.get("until")) if isinstance(data, dict) else None
    if not isinstance(data, dict) or until is None:
        say(f"  warn  the quiet file {path} names no end time ('until'); ignored, no quiet window")
        return None
    if until <= now:
        say(f"  warn  the quiet window ended at {stamp(until)}; ignored ({path}; slots --quiet off removes it)")
        return None
    if until > now + timedelta(hours=MAX_QUIET_HOURS, minutes=1):
        say(
            f"  warn  the quiet file {path} ends at {stamp(until)}, more than {MAX_QUIET_HOURS:g} h ahead, which "
            "slots --quiet never writes; ignored, no quiet window"
        )
        return None
    branch = data.get("branch")
    since, worktree = str(data.get("since", "?")), str(data.get("worktree", "?"))
    return Quiet(until, since, worktree, branch if isinstance(branch, str) else None)


def write_quiet(
    where: Path, hours: float, *, now: datetime | None = None, me: dict[str, object] | None = None
) -> Quiet:
    """Start a quiet window of `hours` (more than 0, at most MAX_QUIET_HOURS) from now, replacing any other."""
    if not (math.isfinite(hours) and 0 < hours <= MAX_QUIET_HOURS):
        raise Failure(f"--quiet {hours:g}: give hours, more than 0 and at most {MAX_QUIET_HOURS:g}, or off")
    now = now or datetime.now(UTC)
    me = me or {}
    branch = me.get("branch")
    worktree = str(me.get("worktree", "?"))
    quiet = Quiet(now + timedelta(hours=hours), stamp(now), worktree, branch if isinstance(branch, str) else None)
    data = {"until": stamp(quiet.until), "since": quiet.since, "slots": QUIET_SLOTS, "worktree": quiet.worktree,
            "branch": quiet.branch}  # fmt: skip
    try:
        where.mkdir(parents=True, exist_ok=True)
        (where / QUIET_FILE).write_text(json.dumps(data), encoding="utf-8")
    except OSError as exc:
        raise Failure(f"could not write the quiet file in {where}: {exc}") from None
    return quiet


def end_quiet(where: Path) -> bool:
    """End the quiet window: remove its file. False when there was none."""
    try:
        (where / QUIET_FILE).unlink()
    except FileNotFoundError:
        return False
    except OSError as exc:
        raise Failure(f"could not remove the quiet file in {where}: {exc}") from None
    return True


@dataclass
class Holder:
    """Who holds a slot, as its holder file says."""

    slot: int
    worktree: str = "?"
    branch: str | None = None
    pid: int | None = None
    since: str = "?"
    kind: str = VERIFY  # VERIFY or LOAD: what holds the slot

    def line(self) -> str:
        what = f"{self.worktree} ({self.branch or 'detached'}, pid {self.pid}, since {self.since})"
        return f"slot {self.slot}: {'load run in ' if self.kind == LOAD else ''}{what}"


@dataclass
class Waiter:
    """A run waiting for a slot (or, `state` OVER, a verify that went ahead without one), as its waiter file says."""

    path: Path
    worktree: str = "?"
    branch: str | None = None
    pid: int | None = None
    since: str = "?"
    kind: str = VERIFY
    state: str = WAITING
    wait: float | None = None  # the run's longest wait, in seconds (None: the file does not say)

    def line(self, now: datetime | None = None) -> str:
        started = parse_stamp(self.since)
        ago = f", {((now or datetime.now(UTC)) - started).total_seconds():.0f} s ago" if started else ""
        doing = "waiting for a slot" if self.state == WAITING else "running OVER THE LIMIT, without a slot,"
        what = "load run" if self.kind == LOAD else "verify"
        who = f"{self.worktree} ({self.branch or 'detached'}, pid {self.pid})"
        return f"{what} in {who} {doing} since {self.since}{ago}"


def read_waiters(where: Path) -> list[Waiter]:
    """Every waiter file in the folder, oldest first (a blank or unreadable one, caught half-written, is left out)."""
    found: list[Waiter] = []
    for path in sorted(where.glob(f"{WAITER_PREFIX}*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8") or "null")
        except (OSError, ValueError):
            continue
        if not isinstance(data, dict):
            continue
        pid, branch = data.get("pid"), data.get("branch")
        found.append(
            Waiter(
                path,
                worktree=str(data.get("worktree", "?")),
                branch=branch if isinstance(branch, str) else None,
                pid=pid if isinstance(pid, int) else None,
                since=str(data.get("since", "?")),
                kind=LOAD if data.get("kind") == LOAD else VERIFY,
                state=OVER if data.get("state") == OVER else WAITING,
                wait=float(data["wait"]) if isinstance(data.get("wait"), (int, float)) else None,
            )
        )
    return sorted(found, key=lambda w: w.since)


@dataclass
class Taken:
    """The outcome of a wait for a slot: the slot (None: the run went ahead without one), the seconds waited, and the
    holders of slots this run took over from a run that ended without releasing them."""

    count: int
    slot: int | None
    waited: float
    reclaimed: list[Holder] = field(default_factory=list)
    holders: list[Holder] = field(default_factory=list)  # who held every slot when the wait ran out
    error: str | None = None  # the slot folder failed (unwritable, missing): the run went ahead without a slot
    quiet: str | None = None  # the run started in a quiet window (#416): Quiet.note()

    @property
    def over(self) -> bool:
        return self.slot is None

    @property
    def note(self) -> str:
        """The slot line's note of a run that started in a quiet window, `(quiet window until ...: 1 of 2 slots)`."""
        return f" ({self.quiet})" if self.quiet else ""

    def record(self) -> dict[str, object]:
        """The history record's `slot` entry (with `error` only when the slot folder failed, and `quiet` only in a
        quiet window)."""
        record: dict[str, object] = {
            "slot": self.slot,
            "of": self.count,
            "waited": round(self.waited, 1),
            "over": self.over,
            "reclaimed": len(self.reclaimed),
        }
        if self.error is not None:
            record["error"] = self.error
        if self.quiet is not None:
            record["quiet"] = self.quiet
        return record

    def summary(self) -> str:
        if self.error is not None:
            return f"slot: NONE of {self.count}: the verify slots failed ({self.error}); ran without a slot{self.note}"
        if self.over:
            return (
                f"slot: NONE of {self.count}{self.note} after waiting {self.waited:.1f}s: ran over the limit "
                f"(held by {'; '.join(h.line() for h in self.holders) or 'unknown'})"
            )
        return f"slot: {self.slot} of {self.count}{self.note}, waited {self.waited:.1f}s for a verify slot"


class Pool:
    """`count` slots in `where`, waited on by a run of `kind` (VERIFY or LOAD). Clock, sleep and say are injectable so
    a test waits without waiting."""

    def __init__(
        self,
        where: Path,
        count: int,
        max_wait: float,
        *,
        kind: str = VERIFY,
        me: dict[str, object] | None = None,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
        say: Callable[[str], None] = print,
        poll: float = POLL,
        every: float = REPORT_EVERY,
        quiet: Quiet | None = None,
    ) -> None:
        if count < 1:
            raise ValueError(f"a pool needs at least one slot, not {count}")
        if kind not in (VERIFY, LOAD):
            raise ValueError(f"a slot is held by a {VERIFY} or a {LOAD} run, not {kind!r}")
        self.where = where
        self.kind = kind
        # In a quiet window (#416) a run takes at most QUIET_SLOTS of the `count` slots: the first ones, so a run that
        # took a later slot before the window began holds it to its end, and no new run takes it.
        self.configured = count
        self.quiet = quiet
        self.count = min(count, QUIET_SLOTS) if quiet is not None else count
        self.max_wait = max_wait
        self.me = me or {}
        self.clock = clock
        self.sleep = sleep
        self.say = say
        self.poll = poll
        self.every = every
        self._fd: int | None = None
        self._slot: int | None = None
        self._waiter: Path | None = None
        self._waiting_since = ""

    @property
    def quiet_note(self) -> str | None:
        return self.quiet.note(self.count, self.configured) if self.quiet is not None else None

    @property
    def what(self) -> str:
        return "load run" if self.kind == LOAD else "verify"

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
            kind=LOAD if data.get("kind") == LOAD else VERIFY,  # a holder file without a kind is a verify's
        )

    def holders(self) -> list[Holder]:
        """The holder files of every slot, as last written (a slot being taken may still name its last holder); an
        empty Holder for a slot whose file is missing, cleared or unreadable."""
        return [self.holder(slot) or Holder(slot) for slot in range(1, self.count + 1)]

    def _write_holder(self, slot: int, data: dict[str, object] | None) -> None:
        # In place, not a temporary file and a rename: on Windows a rename fails while a waiting run has the file open
        # for its report. The slot's lock admits one writer, and a reader that sees a half-written file gets None.
        self._holder_path(slot).write_text(json.dumps(data) if data else "", encoding="utf-8")

    def _mark_waiting(self, state: str) -> None:
        """Write this run's waiter file (#416): it waits for a slot (WAITING), or went ahead without one (OVER). The
        file only names the run for `slots --status`; a failing write never stops it."""
        if self._waiter is None:
            self._waiter = self.where / f"{WAITER_PREFIX}{os.getpid()}-{uuid.uuid4().hex[:8]}.json"
            self._waiting_since = stamp(datetime.now(UTC))
        data = {**self.me, "kind": self.kind, "pid": os.getpid(), "since": self._waiting_since, "state": state,
                "wait": self.max_wait}  # fmt: skip
        with contextlib.suppress(OSError):
            self._waiter.write_text(json.dumps(data), encoding="utf-8")

    def _clear_waiting(self) -> None:
        if self._waiter is not None:
            with contextlib.suppress(OSError):
                self._waiter.unlink(missing_ok=True)
            self._waiter = None

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
                self._write_holder(slot, {**self.me, "kind": self.kind, "pid": os.getpid(), "since": since})
            return slot, left
        return None

    def acquire(self) -> Taken:
        """Wait for a slot, saying every `every` seconds who holds them; after max_wait, or when the slot folder
        fails, go ahead without one (a slot only orders the runs: it never stops the gate). A load run's caller does
        not start after max_wait (`Taken.over`; the warning says so)."""
        started = self.clock()
        next_report = started
        quiet = self.quiet_note
        while True:
            try:
                got = self.try_take()
            except OSError as exc:
                self._clear_waiting()
                self.say(
                    f"  WARN  the verify slots in {self.where} failed ({exc}); this {self.what} runs without a slot"
                )
                error = f"{type(exc).__name__}: {exc}"
                return Taken(self.count, None, self.clock() - started, error=error, quiet=quiet)
            now = self.clock()
            if got is not None:
                self._clear_waiting()
                slot, left = got
                taken = Taken(self.count, slot, now - started, [left] if left else [], quiet=quiet)
                if left:
                    self.say(
                        f"  warn  verify slot {slot} was left by a run that ended without releasing it "
                        f"({left.line()}); taken over"
                    )
                return taken
            if now - started >= self.max_wait:
                holders = self.holders()
                if self.kind == LOAD:
                    self._clear_waiting()
                    outcome = "does not start: it would make the verify runs beside it run over the limit"
                else:
                    self._mark_waiting(OVER)  # `slots --status` names it until it ends (release())
                    outcome = (
                        f"runs OVER THE LIMIT, beside {self.count} others, so the timing-sensitive steps (freeze, "
                        "stall) are less reliable"
                    )
                self.say(
                    f"  WARN  no verify slot after {now - started:.0f}s (all {self.count} held); this {self.what} "
                    f"{outcome}. Holders: {'; '.join(h.line() for h in holders)}"
                )
                return Taken(self.count, None, now - started, holders=holders, quiet=quiet)
            if self._waiter is None:
                self._mark_waiting(WAITING)
            if now >= next_report:
                held = "; ".join(h.line() for h in self.holders())
                self.say(
                    f"{self.kind}: waiting for a slot ({self.count} of {self.count} held"
                    f"{'; ' + quiet if quiet else ''}; waited {now - started:.0f}s, at most {self.max_wait:.0f}s): "
                    f"{held}"
                )
                next_report = now + self.every
            self.sleep(min(self.poll, started + self.max_wait - now))

    def release(self) -> None:
        """Clear the holder file, then free the slot (the system frees it anyway when the process ends); remove the
        waiter file of a run that went ahead without a slot."""
        self._clear_waiting()
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
    kind: str = VERIFY,
    now: datetime | None = None,
) -> tuple[Pool | None, str]:
    """The pool a verify run (or a load run, `kind` LOAD) waits on, or None with the reason: CI (one run per runner),
    a run inside a verify (the outer run holds the slot), or COUNT_VAR=0. In a quiet window (#416, read_quiet) the
    pool has QUIET_SLOTS slots."""
    if ci:
        return None, "no limit on CI"
    if inside:
        return None, "no slot inside a verify (the outer run holds one)"
    count = configured_count(env)
    if count == 0:
        return None, f"no limit ({COUNT_VAR}=0)"
    wait = setting(env, WAIT_VAR, DEFAULT_WAIT)
    where = folder(env)
    quiet = read_quiet(where, now=now, say=say)
    return Pool(where, count, wait, kind=kind, me=me, say=say, quiet=quiet), ""


# --- the slots command (#416) --------------------------------------------------------------------------------------


def history_runs_without_slot(paths: list[Path], now: datetime, window: float = RECENT) -> list[dict[str, object]]:
    """The verify runs of the history files that ended within `window` seconds before `now` without a slot (over the
    limit, or the slot folder failed), oldest first."""
    from .metrics import read_json_lines

    found: list[tuple[datetime, dict[str, object]]] = []
    for path in paths:
        for rec in read_json_lines(path):
            slot = rec.get("slot")
            start = parse_stamp(rec.get("start"))
            if not isinstance(slot, dict) or start is None or not (slot.get("over") or slot.get("error")):
                continue
            waited = slot.get("waited") if isinstance(slot.get("waited"), (int, float)) else 0.0
            seconds = rec.get("seconds") if isinstance(rec.get("seconds"), (int, float)) else 0.0
            ended = start + timedelta(seconds=float(waited) + float(seconds))  # type: ignore[arg-type]
            if now - timedelta(seconds=window) <= ended <= now + timedelta(minutes=1):
                found.append((start, rec))
    return [rec for _, rec in sorted(found, key=lambda item: item[0])]


def _history_paths() -> list[Path]:
    from . import metrics

    return metrics.history_paths(metrics.main_checkout())


def _alive(pid: int) -> bool:
    from . import sessions

    return sessions.process_alive(pid)


def stale_waiter(waiter: Waiter, now: datetime, default_wait: float) -> bool:
    """A WAITING file older than its run's longest wait (plus STALE_MARGIN): the run is gone, whatever its pid says. An
    OVER file has no bound (a verify runs as long as it runs)."""
    started = parse_stamp(waiter.since)
    if waiter.state != WAITING or started is None:
        return False
    limit = waiter.wait if waiter.wait is not None else default_wait
    return (now - started).total_seconds() > limit + STALE_MARGIN


def status(
    env: dict[str, str] | os._Environ[str] = os.environ,
    *,
    now: datetime | None = None,
    alive: Callable[[int], bool] = _alive,
    histories: Callable[[], list[Path]] = _history_paths,
    out: Callable[[str], None] = print,
) -> int:
    """`slots --status`: the quiet window, who holds each slot, the runs waiting for one (and those that went ahead
    without one and still run), and the verify runs of the last hour that ran without a slot. A manager launches only
    when no run waits (N3 (b) of the weekly budget ADR); the last line says whether one does."""
    now = now or datetime.now(UTC)
    where = folder(env)
    count = configured_count(env)
    wait = setting(env, WAIT_VAR, DEFAULT_WAIT)
    if count == 0:
        out(f"slots: no limit on this PC ({COUNT_VAR}=0); folder {where}")
    else:
        out(f"slots: {count} machine-wide verify slots, a wait of at most {wait:.0f} s; folder {where}")
    quiet = read_quiet(where, now=now, say=out)
    if quiet is None:
        out("quiet: none (slots --quiet <hours> starts one)")
    else:
        left = (quiet.until - now).total_seconds() / 60
        out(
            f"quiet: until {stamp(quiet.until)} ({left:.0f} min left): a new verify or load run takes "
            f"{min(count, QUIET_SLOTS)} of {count} slots; started {quiet.since} in {quiet.worktree} "
            f"({quiet.branch or 'detached'}); slots --quiet off ends it"
        )
    out("holders:")
    pool = Pool(where, max(count, 1), 0)
    held = 0
    for holder in pool.holders()[:count]:
        if holder.pid is not None and alive(holder.pid):
            held += 1
            out(f"  {holder.line()}")
        elif holder.pid is not None:
            out(f"  slot {holder.slot}: free (its last holder, pid {holder.pid} in {holder.worktree}, ended without "
                "releasing it; the next run takes it over)")  # fmt: skip
        else:
            out(f"  slot {holder.slot}: free")
    if count == 0:
        out("  none (no limit)")
    waiters: list[Waiter] = []
    for waiter in read_waiters(where) if where.is_dir() else []:
        if waiter.pid is not None and alive(waiter.pid) and not stale_waiter(waiter, now, wait):
            waiters.append(waiter)
        else:  # its run was killed while it waited or ran (its pid may live on in another process): nothing removed it
            with contextlib.suppress(OSError):
                waiter.path.unlink(missing_ok=True)
    waiting = [w for w in waiters if w.state == WAITING]
    over_now = [w for w in waiters if w.state == OVER]
    out(f"waiters: {len(waiting) or 'none'}")
    for waiter in waiting:
        out(f"  {waiter.line(now)}")
    if over_now:
        out(f"running without a slot now: {len(over_now)}")
        for waiter in over_now:
            out(f"  {waiter.line(now)}")
    try:
        recent = history_runs_without_slot(histories(), now)
    except (OSError, Failure) as exc:
        out(f"  warn  the verify history files could not be read ({exc})")
        recent = []
    out(f"without a slot in the last hour (verify history): {len(recent) or 'none'}")
    for rec in recent:
        slot: dict = rec["slot"]  # type: ignore[assignment]  # history_runs_without_slot keeps only dicts
        why = "the slot folder failed" if slot.get("error") else "over the limit"
        out(
            f"  {rec.get('start')} {rec.get('worktree', '?')} ({rec.get('branch') or 'detached'}): {why}, "
            f"{rec.get('status', '?')} in {rec.get('seconds', '?')} s after waiting {slot.get('waited', '?')} s"
        )
    if waiting:
        out(f"slots: {len(waiting)} run(s) waiting for a slot ({held} of {count} held): launch nothing now")
    else:
        out(f"slots: no run waits for a slot ({held} of {count} held)")
    return 0


def quiet_command(
    arg: str,
    env: dict[str, str] | os._Environ[str] = os.environ,
    *,
    now: datetime | None = None,
    me: dict[str, object] | None = None,
    out: Callable[[str], None] = print,
) -> int:
    """`slots --quiet <hours>` starts a quiet window machine-wide (replacing any other); `slots --quiet off` ends it."""
    where = folder(env)
    count = configured_count(env)
    if arg.strip().lower() == "off":
        if end_quiet(where):
            out(f"slots: quiet window ended; new verify and load runs take any of the {count} slots again")
        else:
            out("slots: no quiet window to end")
        return 0
    try:
        hours = float(arg)
    except ValueError:
        raise Failure(f"--quiet {arg!r}: give hours, more than 0 and at most {MAX_QUIET_HOURS:g}, or off") from None
    quiet = write_quiet(where, hours, now=now, me=me)
    local = quiet.until.astimezone().strftime("%H:%M")
    if count == 0:
        out(f"slots: quiet until {stamp(quiet.until)} ({local} local time); this shell has no limit ({COUNT_VAR}=0)")
        return 0
    out(
        f"slots: quiet until {stamp(quiet.until)} ({local} local time): every checkout's new verify and load runs on "
        f"this PC take {min(count, QUIET_SLOTS)} of the {count} slots (a run already in a slot finishes there); "
        "slots --quiet off ends it sooner"
    )
    return 0
