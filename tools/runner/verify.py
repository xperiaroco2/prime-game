"""`verify` (the definition of done: exactly what CI runs) and `selftest`.

`doctor --quick` runs first, and a red one stops everything. Then two lanes run at once, each in a process of its
own and serial inside (LANES): the Python lane (`lint`, then `selftest`: the runner tests that start no Godot, in
worker processes) and the Godot lane (`check`, then `selftest-godot`: the runner tests that start Godot, then
`test`, `enet`, `freeze`, `stall`, `bots`, `bots-enet`, `chaos` and `game`), so the timing-sensitive ENet runs never
overlap.
Every step runs and a red one fails `verify`; each step's output is printed whole when the step ends. After both
lanes: the clean-tree check, and the runner tests counted against a serial discovery (every test a serial `selftest`
would run ran once, skipped where it would be skipped). The summary lists the steps in STEP_ORDER (the order of the
serial `verify` before #179) with each lane's wall time; each run appends a record to HISTORY.
"""

from __future__ import annotations

import concurrent.futures
import contextlib
import json
import multiprocessing
import os
import random
import re
import socket
import subprocess
import sys
import threading
import time
import traceback
import unittest
import uuid
from collections import Counter
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from . import bots, check, doctor, gdunit, hostjoin, launch, lint, slots
from .common import (
    IS_CI,
    LOGS,
    ROOT,
    Failure,
    app_data_dir,
    bad,
    ensure_out,
    git,
    git_status,
    group_kwargs,
    kill_tree,
    ok,
    say,
    take_starts,
    temp_app_data,
    warn,
)

# The headless ENet run (#40): a host with its own client and two clients, one process each, on 127.0.0.1 only.
ENET_RUN = "tests/integration/net/enet_host_and_two_clients.gd"
ENET_INSTANCES = 3
ENET_SECONDS = 90
# A 5.2 s main-thread freeze of the host, then of a client, over ENet (#70): no drop, and the LATEST backlog merged.
# About 16 s; three instances on 127.0.0.1 like the ENet run.
FREEZE_RUN = "tests/integration/net/enet_freeze.gd"
FREEZE_SECONDS = 60
# ENet's timeouts on both sides, measured by stalling one side of a pair, and a backlog of more datagrams than one
# ENet service reads, taken in one poll (#95). About 22 s; one process whose three hosts take the port and the next two.
STALL_RUN = "tests/integration/net/enet_stall.gd"
STALL_SECONDS = 60
STALL_PORTS = 3
# The bot scenarios and the information-leak test (#102): every scenario in one process on a simulated clock (about
# 8 s), then one scenario over ENet, one process per bot on the real clock: about 48 s since M4-3 (#139), whose
# scenario ends by time up on a 40 s clock it forces (BotScenario.clock_s).
BOTS_ENET_SCENARIO = "dissident_kills_the_crew"
BOTS_ENET_INSTANCES = 3
# The chaos bots (#188): one seed, the short match, three runs in one process over the loopback (about 6 s).
CHAOS_SEED = 188001

# Below the ephemeral ranges of Windows (49152+) and Linux (32768+): an ENet client's own socket never takes it.
ENET_PORTS = range(20000, 32000)
PORT_TRIES = 50

# The summary's order: the serial verify's order before #179, with the runner tests that start Godot after selftest.
STEP_ORDER = (
    "doctor",
    "lint",
    "check",
    "test",
    "enet",
    "freeze",
    "stall",
    "bots",
    "bots-enet",
    "chaos",
    "game",
    "selftest",
    "selftest-godot",
)
# After doctor, both lanes at once; each one serial. The Godot lane holds every step that starts Godot, so no two
# Godot runs (and no two real-time ENet sessions) ever overlap, and its runner tests come after check: a fresh CI
# checkout has imported the project (.godot/) before RealSessionTest is discovered.
LANES: dict[str, tuple[str, ...]] = {
    "python": ("lint", "selftest"),
    "godot": ("check", "selftest-godot", "test", "enet", "freeze", "stall", "bots", "bots-enet", "chaos", "game"),
}
# A lane process that outlives this is stopped and its unfinished steps fail (CI's whole job has 20 minutes).
LANE_TIMEOUT = 30 * 60
# The line a lane process prints after each step, then the step's result as JSON. Printable on purpose: Python's
# str.splitlines() also splits at control characters such as \x1e.
MARK = "::verify-step:: "
# One JSON line per verify run (docs/AGENT_WORKFLOW.md §11); `metrics` (#178) reads it.
HISTORY = LOGS / "verify-history.jsonl"
# The runner tests' results per group (the Python and the Godot lane): per-test outcome and seconds, read back by
# verify's count check and by the next run, which starts the slowest tests first.
SELFTEST_RESULTS = "selftest-{group}.json"
RUN_ID_VAR = "PRIME_VERIFY_RUN"
# Set in every lane process and selftest worker, whose children inherit it: lanes refuse to start below one, so a
# runner test that reaches verify's real lanes fails instead of starting verify inside verify without end.
INSIDE_VAR = "PRIME_VERIFY_INSIDE"
TESTS = ROOT / "tools" / "runner" / "tests"


def free_udp_port(pick: Callable[[range], int] = random.choice, count: int = 1) -> int:
    """A random UDP port on 127.0.0.1 that nothing holds right now, so worktrees verifying at once rarely share one.

    With `count`, the port and the next `count - 1` are all free. A port that fails to bind (in use, or in a range
    Windows reserves) is skipped. The probe socket closes before Godot binds the port, so two worktrees can still
    pick the same one in that window (about 1 in 12,000); the host then fails with "host on 127.0.0.1:<port>
    failed", and running `verify` again picks a new port.
    """
    for _ in range(PORT_TRIES):
        port = pick(range(ENET_PORTS.start, ENET_PORTS.stop - count + 1))
        if all(_binds(each) for each in range(port, port + count)):
            return port
    raise Failure(f"no free UDP port on 127.0.0.1 in {ENET_PORTS.start}-{ENET_PORTS.stop - 1} after {PORT_TRIES} tries")


def _binds(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True


def enet() -> int:
    """`run <ENET_RUN> --headless --instances 3 --seconds 90 -- --port=<free>`: any failed instance fails it."""
    return _headless_on_free_port(ENET_RUN, ENET_SECONDS)


def freeze() -> int:
    """`run <FREEZE_RUN> --headless --instances 3 --seconds 60 -- --port=<free>`: any failed instance fails it."""
    return _headless_on_free_port(FREEZE_RUN, FREEZE_SECONDS)


def stall() -> int:
    """`run <STALL_RUN> --headless --seconds 60 -- --port=<free>`: one process, whose hosts take three ports."""
    port = free_udp_port(count=STALL_PORTS)
    return launch.main(STALL_RUN, headless=True, seconds=STALL_SECONDS, instances=1, user_args=[f"--port={port}"])


def bots_one_process() -> int:
    """`bots`: every scenario in one process over the loopback."""
    return bots.main()


def bots_enet() -> int:
    """`bots <BOTS_ENET_SCENARIO> --instances 3`: one scenario over ENet on a free port."""
    return bots.main([BOTS_ENET_SCENARIO], instances=BOTS_ENET_INSTANCES)


def chaos() -> int:
    """`bots --chaos --seed <CHAOS_SEED>`: the chaos bots' short seeded run (the night job runs random seeds)."""
    return bots.chaos(seed=CHAOS_SEED)


def game() -> int:
    """The game's main scene through its real command line (#149): client/app/game.tscn headless, a host and one
    client over ENet on a free port of 127.0.0.1, both welcomed into the lobby, then stopped through the stop file
    (hostjoin.game_check). About 5 s."""
    return hostjoin.game_check(free_udp_port())


def _headless_on_free_port(target: str, seconds: int) -> int:
    port = free_udp_port()
    return launch.main(
        target, headless=True, seconds=seconds, instances=ENET_INSTANCES, user_args=[f"--port={port}"]
    )


def steps() -> dict[str, Callable[[], int]]:
    """Each step by name, looked up when called (tests replace the functions)."""
    return {
        "doctor": lambda: doctor.main(quick=True),
        "lint": lambda: lint.main(),
        "check": lambda: check.main(),
        # As `test` with no paths: gdunit.FIXED_FPS_SUITES at fixed fps in shards of their own, the rest real-time
        "test": lambda: gdunit.main(run_import=False),
        "enet": enet,
        "freeze": freeze,
        "stall": stall,
        "bots": bots_one_process,
        "bots-enet": bots_enet,
        "chaos": chaos,
        "game": game,
        "selftest": lambda: selftest("python"),
        "selftest-godot": lambda: selftest("godot"),
    }


def run_step(name: str) -> int:
    """Run one step; a Failure or any other exception is its red result, never the end of the lane."""
    try:
        return steps()[name]()
    except Failure as exc:
        bad(str(exc))
    except Exception:  # noqa: BLE001 - a crashed step is a red step; the other steps still run
        bad(f"{name} crashed:", traceback.format_exc().rstrip())
    return 1


# --- the lanes --------------------------------------------------------------------------------------------------


@dataclass
class StepRun:
    name: str
    lane: str
    status: str  # "passed" or "FAILED"
    seconds: float
    output: str = ""
    detail: dict[str, object] = field(default_factory=dict)  # the step's own fields of the history record


Emit = Callable[[StepRun], None]
RunLane = Callable[[str, tuple[str, ...], Emit], None]


def lane_main(lane: str) -> int:
    """The body of a lane process: its steps in order, each followed by a MARK line with its result."""
    for name in LANES[lane]:
        started = time.monotonic()
        rc = run_step(name)
        seconds = time.monotonic() - started
        say()
        sys.stdout.flush()
        mark: dict[str, object] = {"step": name, "rc": rc, "seconds": round(seconds, 1)}
        detail = step_detail(name)
        if detail:
            mark["detail"] = detail
        print(MARK + json.dumps(mark), flush=True)
    return 0


def step_detail(name: str) -> dict[str, object] | None:
    """A step's own fields of the history record, taken in the lane process right after it ran: `test`'s GdUnit4
    processes and failing tests (gdunit.take_last_run, #273), any step's `not_started`, the process starts that
    Windows refused while it ran (common.take_starts, #441), and the `check` step's `exit_crash`, whether its project
    check passed although Godot crashed at exit (check.take_exit_crashes, #442, #449): written true or false on every
    check step since #449, so a record without it is known to predate the field."""
    detail = dict(gdunit.take_last_run() or {}) if name == "test" else {}
    starts = take_starts()
    if starts:
        detail["not_started"] = starts
    crashes = check.take_exit_crashes()  # taken after every step, so one step's crash is never the next one's
    if name == "check":
        detail["exit_crash"] = crashes > 0
    return detail or None


class LaneReader:
    """Turns a lane process's output into one StepRun per step: the lines before each MARK are that step's output."""

    def __init__(self, lane: str, names: tuple[str, ...], emit: Emit) -> None:
        self.lane = lane
        self.waiting = list(names)
        self.emit = emit
        self.lines: list[str] = []

    def feed(self, line: str) -> None:
        try:
            data = json.loads(line[len(MARK) :]) if line.startswith(MARK) else None
            name, rc, seconds = str(data["step"]), data["rc"], float(data["seconds"])
            detail = data.get("detail")
        except (TypeError, ValueError, KeyError):  # not a mark (or a broken one): part of the step's output
            self.lines.append(line)
            return
        if name not in self.waiting:  # another lane's step, or one already reported: output, never a result
            self.lines.append(line)
            return
        self.waiting.remove(name)
        status = "passed" if rc == 0 else "FAILED"
        own = detail if isinstance(detail, dict) else {}
        self.emit(StepRun(name, self.lane, status, seconds, "".join(self.lines), own))
        self.lines = []

    def close(self, why: str) -> None:
        """The process ended: every step it never reported failed, the first one with the output left over."""
        for name in self.waiting:
            output = "".join(self.lines) + f"  FAIL  the {self.lane} lane ended before {name} did: {why}\n"
            self.emit(StepRun(name, self.lane, "FAILED", 0.0, output))
            self.lines = []
        self.waiting = []


def lane_command(lane: str) -> list[str]:
    tools = str(ROOT / "tools")
    code = (
        f"import sys; sys.path.insert(0, {tools!r}); sys.dont_write_bytecode = True; "
        f"from runner import verify; sys.exit(verify.lane_main({lane!r}))"
    )
    return [sys.executable, "-u", "-c", code]


_LIVE: set[subprocess.Popen[bytes]] = set()
_LIVE_LOCK = threading.Lock()


def run_lane_process(
    lane: str,
    names: tuple[str, ...],
    emit: Emit,
    *,
    cmd: list[str] | None = None,
    timeout: float = LANE_TIMEOUT,
) -> None:
    """Run a lane in a process of its own and emit each step as it ends. Its Godot runs and worker processes are its
    children, so every line they print reaches this lane's output, never the other lane's."""
    if cmd is None and os.environ.get(INSIDE_VAR):
        raise Failure(f"no verify lanes inside a lane or a selftest worker ({INSIDE_VAR} is set): stub run_lane")
    env = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONDONTWRITEBYTECODE": "1", INSIDE_VAR: "1"}
    proc = subprocess.Popen(
        cmd or lane_command(lane),
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        **group_kwargs(),  # type: ignore[arg-type]
    )
    with _LIVE_LOCK:
        _LIVE.add(proc)
    reader = LaneReader(lane, names, emit)
    fired = threading.Event()

    def stop() -> None:
        fired.set()
        kill_tree(proc)

    timer = threading.Timer(timeout, stop)
    timer.daemon = True
    timer.start()
    try:
        assert proc.stdout is not None
        for raw in iter(proc.stdout.readline, b""):
            reader.feed(raw.decode("utf-8", errors="replace").replace("\r\n", "\n"))
        proc.wait()
    finally:
        timer.cancel()
        if proc.stdout is not None:
            proc.stdout.close()
        with _LIVE_LOCK:
            _LIVE.discard(proc)
    reader.close(f"stopped after {timeout:.0f}s" if fired.is_set() else f"its process exited {proc.returncode}")


def run_lanes(run_lane: RunLane, emit: Emit, printing: threading.Lock | None = None) -> dict[str, float]:
    """Every lane at once, one thread each; returns each lane's wall time in seconds. Ctrl+C stops the lanes'
    processes (each runs in a process group of its own, which Ctrl+C does not reach). `printing` is the lock emit
    prints under: a crashed lane's message takes it too, so it never lands inside another step's block."""
    walls: dict[str, float] = {}
    printing = printing or threading.Lock()

    def one(lane: str, names: tuple[str, ...]) -> None:
        started = time.monotonic()
        try:
            run_lane(lane, names, emit)
        except Exception:  # noqa: BLE001 - its unreported steps fail in the summary
            with printing:
                bad(f"the {lane} lane crashed:", traceback.format_exc().rstrip())
        walls[lane] = time.monotonic() - started

    threads = [threading.Thread(target=one, args=item, daemon=True) for item in LANES.items()]
    try:
        for thread in threads:
            thread.start()
        for thread in threads:
            while thread.is_alive():
                thread.join(0.5)  # a bounded join lets Ctrl+C through on Windows
    except BaseException:
        with _LIVE_LOCK:
            live = list(_LIVE)
        for proc in live:
            kill_tree(proc)
        raise
    return walls


# --- selftest ---------------------------------------------------------------------------------------------------

# The Python lane runs beside the Godot lane's timing-sensitive freeze and stall runs, and on the engineer's PC beside
# another worktree's verify run (slots.DEFAULT_COUNT, #185) and the other sessions' work (8 cores, 16 logical CPUs).
# Its runner tests therefore take at most a quarter of the logical CPUs (half the physical cores: 4 there, 1 on CI's
# 4-vCPU runner), which still ends the lane long before the Godot lane reaches freeze (measured on the PC with four
# other runs going, 2026-10-02, before the verify slots: the Python lane about 125 to 150 s, the Godot lane's check,
# selftest-godot and test alone about 370 s).
WORKER_SHARE = 4


def selftest_workers(cpus: int | None = None) -> int:
    return max(1, (cpus if cpus is not None else os.cpu_count() or 1) // WORKER_SHARE)


def starts_godot(cls: type[unittest.TestCase]) -> type[unittest.TestCase]:
    """Marks a runner test class that starts Godot: it runs in the Godot lane, after `check`, serially. Its tests run
    with the app-data variable pointed at a temporary folder of the class's own (common.temp_app_data, #233), so no
    Godot they start adds a folder to the real app-data folder. `cls.app_data` is that folder, `cls.outer_app_data`
    the one the class would have used without it (the real one, or selftest's stand-in)."""
    cls.starts_godot = True  # type: ignore[attr-defined]
    own = cls.__dict__.get("setUpClass")

    def set_up_class(klass: type[unittest.TestCase]) -> None:
        klass.outer_app_data = app_data_dir()  # type: ignore[attr-defined]
        klass.app_data = klass.enterClassContext(temp_app_data())  # type: ignore[attr-defined]
        if isinstance(own, classmethod):
            own.__func__(klass)
        else:
            super(cls, klass).setUpClass()  # type: ignore[misc]

    cls.setUpClass = classmethod(set_up_class)  # type: ignore[assignment,method-assign]
    return cls


def discover() -> list[unittest.TestCase]:
    """Every runner test, as a serial `selftest` loads them (stdlib unittest, tools/runner/tests)."""
    suite = unittest.defaultTestLoader.discover(str(TESTS), top_level_dir=str(ROOT / "tools"))
    return list(_flatten(suite))


def _flatten(suite: unittest.TestSuite) -> Iterator[unittest.TestCase]:
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from _flatten(item)
        else:
            yield item  # type: ignore[misc]


def group_of(test: unittest.TestCase) -> str:
    return "godot" if getattr(type(test), "starts_godot", False) else "python"


def statically_skipped(test: unittest.TestCase) -> bool:
    """Skipped by a decorator of its class or method, decided when its module was imported."""
    method = getattr(test, getattr(test, "_testMethodName", ""), None)
    return bool(getattr(type(test), "__unittest_skip__", False) or getattr(method, "__unittest_skip__", False))


def _import_failure(test: unittest.TestCase) -> bool:
    """A module that failed to import: discovery's stand-in test, which only a run in this process can show."""
    return type(test).__module__ == "unittest.loader"


def run_case(test: unittest.TestCase, test_id: str | None = None) -> dict[str, object]:
    """One test's outcome: passed, failed or skipped, its seconds, whether a decorator skipped it, and why."""
    started = time.monotonic()
    static = statically_skipped(test)
    result = unittest.TestResult()
    unittest.TestSuite([test]).run(result)  # with the class fixtures, as a serial run has them
    problems = [trace for _case, trace in result.errors + result.failures]
    problems += ["unexpected success"] * len(result.unexpectedSuccesses)
    if problems:
        outcome, detail = "failed", "\n".join(problems)
    elif result.skipped:
        outcome, detail = "skipped", result.skipped[0][1]
    elif result.testsRun == 0:
        outcome, detail = "failed", "the test never ran"
    else:
        outcome, detail = "passed", ""
    return {
        "id": test_id or test.id(),
        "outcome": outcome,
        "static": static,
        "seconds": round(time.monotonic() - started, 3),
        "detail": detail,
    }


def run_ids(ids: list[str]) -> list[dict[str, object]]:
    """A worker process's task: load each test by its id and run it."""
    entries: list[dict[str, object]] = []
    for test_id in ids:
        try:
            tests = list(_flatten(unittest.defaultTestLoader.loadTestsFromName(test_id)))
        except Exception:  # noqa: BLE001 - reported as the test's failure
            entries.append({"id": test_id, "outcome": "failed", "static": False, "seconds": 0.0,
                            "detail": traceback.format_exc()})  # fmt: skip
            continue
        if len(tests) != 1:
            entries.append({"id": test_id, "outcome": "failed", "static": False, "seconds": 0.0,
                            "detail": f"{len(tests)} tests by this id, not one"})  # fmt: skip
            continue
        entries.append(run_case(tests[0], test_id))
    return entries


def run_in_workers(ids: list[str], workers: int) -> list[dict[str, object]]:
    """Each test in one of `workers` processes (spawned: no fork of a process with threads), as they free up."""
    if not ids:
        return []
    entries: list[dict[str, object]] = []
    context = multiprocessing.get_context("spawn")
    with concurrent.futures.ProcessPoolExecutor(max_workers=min(workers, len(ids)), mp_context=context) as pool:
        futures = {pool.submit(run_ids, [test_id]): test_id for test_id in ids}
        for future in concurrent.futures.as_completed(futures):
            try:
                entries.extend(future.result())
            except Exception:  # noqa: BLE001 - a worker that died fails its test, never the whole run
                entries.append({"id": futures[future], "outcome": "failed", "static": False, "seconds": 0.0,
                                "detail": traceback.format_exc()})  # fmt: skip
    return entries


def _results_path(group: str) -> Path:
    return LOGS / SELFTEST_RESULTS.format(group=group)


def read_results(group: str) -> dict[str, object] | None:
    try:
        data = json.loads(_results_path(group).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _slowest_first(group: str, ids: list[str]) -> list[str]:
    """The last run's slowest tests start first, so no long test starts last; new tests count as slow."""
    previous = read_results(group) or {}
    tests = previous.get("tests")
    seconds: dict[str, float] = {}
    for entry in tests if isinstance(tests, list) else []:
        if isinstance(entry, dict):
            seconds[str(entry.get("id"))] = float(entry.get("seconds", 0.0))
    return sorted(ids, key=lambda test_id: -seconds.get(test_id, float("inf")))


def _run_group(group: str, tests: list[unittest.TestCase], workers: int) -> tuple[list[dict[str, object]], float]:
    """Run a group's tests and write their results (for verify's count check and the next run's order); return them
    and the group's seconds."""
    started = time.monotonic()
    inline = [t for t in tests if _import_failure(t)]
    ids = _slowest_first(group, [t.id() for t in tests if not _import_failure(t)])
    entries = [run_case(t) for t in inline] + run_in_workers(ids, workers)
    ensure_out()
    record = {"group": group, "run": os.environ.get(RUN_ID_VAR), "workers": workers, "tests": entries}
    _results_path(group).write_text(json.dumps(record, indent=1) + "\n", encoding="utf-8", newline="\n")
    return entries, time.monotonic() - started


def _show(text: str) -> None:
    for line in text.rstrip().splitlines():
        say(f"        {line}")


def _report(group: str, entries: list[dict[str, object]], workers: int, seconds: float) -> bool:
    """Print a group's failures (with their tracebacks), its count and its slowest tests; True when it passed."""
    what = {"python": " that start no Godot", "godot": " that start Godot"}.get(group, "")
    failed = [e for e in entries if e["outcome"] == "failed"]
    for entry in failed:
        detail = str(entry["detail"]).rstrip() or "failed"
        bad(f"{entry['id']}: {detail.splitlines()[-1]}")
        _show(detail)
    if not entries and group != "godot":
        bad("no runner tests found")
        return False
    skipped = sum(e["outcome"] == "skipped" for e in entries)
    plural = "es" if workers > 1 else ""
    counted = (
        f"{len(entries) - skipped} runner tests{what} run, {skipped} skipped, "
        f"in {seconds:.1f}s on {workers} worker process{plural}"
    )
    if failed:
        bad(f"{len(failed)} failed of {counted}")
        return False
    ok(f"{counted}: passed")
    ran = [e for e in entries if e["outcome"] != "skipped"]
    slowest = sorted(ran, key=lambda e: -float(str(e["seconds"])))[:3]
    if slowest:
        named = [f"{str(e['id']).removeprefix('runner.tests.')} {float(str(e['seconds'])):.1f}s" for e in slowest]
        say("        slowest: " + ", ".join(named))
    return True


def selftest(group: str = "all") -> int:
    """Unit tests of the runner itself (stdlib unittest, tools/runner/tests), each in a worker process.

    `python`: the tests that start no Godot, on selftest_workers() processes. `godot`: the tests marked
    @starts_godot, serially in one process. `all` (the `selftest` command): both at once, then the count check.
    """
    say("selftest-godot" if group == "godot" else "selftest")
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"  # the spawned workers import the runner afresh
    os.environ[INSIDE_VAR] = "1"  # and inherit this: a test that reaches the real lanes fails (run_lane_process)
    tests = discover()
    groups = ("python", "godot") if group == "all" else (group,)
    workers = {name: 1 if name == "godot" else selftest_workers() for name in groups}
    # Every worker inherits a stand-in app-data folder: a test that writes to the app-data folder outside a
    # @starts_godot class (which has its own) would have written to the real one, and fails the run (#233).
    with temp_app_data(prefix="prime-selftest-app-data-") as stand_in:
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(groups)) as threads:
            futures = {
                name: threads.submit(_run_group, name, [t for t in tests if group_of(t) == name], workers[name])
                for name in groups
            }
            done = {name: future.result() for name, future in futures.items()}
        reached = app_data_written(stand_in)
    entries = {name: found for name, (found, _seconds) in done.items()}
    passed = all([_report(name, entries[name], workers[name], done[name][1]) for name in groups])
    if reached:
        bad(
            f"runner tests wrote to the app-data folder, which outside selftest is the real one: {', '.join(reached)}",
            "Mark a test class that starts Godot with @starts_godot (verify.starts_godot): it gives the class a "
            "temporary app-data folder of its own. Any other test points the app-data variable at a temporary folder.",
        )
        passed = False
    if group == "all":
        reference = {t.id(): statically_skipped(t) for t in tests}
        problems, line = count_check(reference, entries["python"] + entries["godot"])
        for problem in problems:
            bad(problem)
        (bad if problems else ok)(line)
        passed = passed and not problems
    say(f"selftest: {'passed' if passed else 'FAILED'}")
    return 0 if passed else 1


def app_data_written(folder: Path | None, limit: int = 5) -> list[str]:
    """What the runner tests wrote to selftest's stand-in app-data folder (its files, and each user:// folder in Godot's
    app_userdata/ that has none, because a leaked folder is the harm even when empty; at most `limit` named, as paths
    relative to it): nothing, when every test that starts Godot carries @starts_godot."""
    if folder is None or not folder.is_dir():
        return []
    written = sorted(p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_file())
    for godot in (p for p in folder.iterdir() if p.name in ("Godot", "godot")):  # by listing: Windows ignores case
        user_dirs = godot / "app_userdata"
        for user in sorted(user_dirs.iterdir()) if user_dirs.is_dir() else []:
            if user.is_dir() and not any(p.is_file() for p in user.rglob("*")):
                written.append(user.relative_to(folder).as_posix() + "/")
    return written[:limit] + ([f"and {len(written) - limit} more"] if len(written) > limit else [])


def count_check(reference: dict[str, bool], entries: list[dict[str, object]]) -> tuple[list[str], str]:
    """Compare the runs with a serial discovery in the same state (`reference`: test id -> skipped by a decorator).

    Every test a serial `selftest` would run must have run exactly once, and a decorator must have skipped it in its
    worker exactly when it skips it in the serial discovery (a skip that depends on the moment of discovery, such as
    RealSessionTest's before `check` imported the project, shows up here). Returns the problems and the count line.
    """
    counts = Counter(str(e["id"]) for e in entries)
    problems = []
    missing = sorted(set(reference) - set(counts))
    extra = sorted(set(counts) - set(reference))
    doubled = sorted(test_id for test_id, n in counts.items() if n > 1)
    skips = sorted(
        str(e["id"])
        for e in entries
        if str(e["id"]) in reference and bool(e["static"]) != reference[str(e["id"])]
    )
    for label, ids in (
        ("never ran", missing),
        ("ran but a serial run has no such test", extra),
        ("ran more than once", doubled),
        ("skipped by a decorator in one run and not in the other", skips),
    ):
        if ids:
            problems.append(f"{len(ids)} runner tests {label}: {', '.join(ids[:5])}{' ...' if len(ids) > 5 else ''}")
    skipped = sum(e["outcome"] == "skipped" for e in entries)
    serial_run = sum(not static for static in reference.values())
    line = (
        f"runner tests: {len(entries) - skipped} run and {skipped} skipped of {len(entries)}; "
        f"a serial run: {serial_run} run of {len(reference)}"
    )
    return problems, line


def count_after_lanes(run_id: str) -> tuple[list[str], str, dict[str, int]]:
    """verify's count check: both lanes' runner tests against a serial discovery now, after both lanes, where the
    serial verify ran selftest (after check had imported the project)."""
    entries: list[dict[str, object]] = []
    problems = []
    for group in ("python", "godot"):
        data = read_results(group)
        if data is None or data.get("run") != run_id:
            where = f"tools/out/logs/{_results_path(group).name}"
            problems.append(f"selftest {group} left no results of this run ({where})")
            continue
        tests = data.get("tests")
        entries += [e for e in tests if isinstance(e, dict)] if isinstance(tests, list) else []
    found, line = count_check({t.id(): statically_skipped(t) for t in discover()}, entries)
    skipped = sum(e["outcome"] == "skipped" for e in entries)
    return problems + found, line, {"run": len(entries) - skipped, "skipped": skipped}


# --- verify -----------------------------------------------------------------------------------------------------


def _print_step(step: StepRun) -> None:
    sys.stdout.write(f"== {step.name} ({step.lane} lane, {step.seconds:.1f}s, {step.status})\n{step.output}")
    sys.stdout.flush()


def git_facts(clean: bool) -> dict[str, str | None]:
    """The checkout's branch, HEAD, HEAD's tree (only with a clean tree) and the runner's version (the tree hash of
    tools/runner/ at HEAD)."""

    def rev(*args: str) -> str | None:
        res = git(*args)
        return res.out.strip() if res.rc == 0 and res.out.strip() else None

    branch = rev("rev-parse", "--abbrev-ref", "HEAD")
    return {
        "branch": None if branch == "HEAD" else branch,
        "head": rev("rev-parse", "HEAD"),
        "tree": rev("rev-parse", "HEAD^{tree}") if clean else None,
        "runner": rev("rev-parse", "HEAD:tools/runner"),
    }


# A red step's first failure line (#273): its first `FAIL` line, with the reason that line points at when the output
# holds one (the first engine error line, or the first line under a bots or chaos run's FAILED header, such as
# "a Correction outside a placement ..."), clipped like the failing tests' messages. Without a FAIL line: the reason,
# else the output's last line. A reason is looked for only in the steps that run the game itself: a runner test's
# traceback or a lint message can hold an indented "ERROR: " line that is not the cause.
FAIL_LINE = "  FAIL  "
REASON_STEPS = frozenset({"check", "enet", "freeze", "stall", "bots", "bots-enet", "chaos", "game"})
RUN_FAILED_RE = re.compile(r"^(?:BOTS|CHAOS)\b.*\bFAILED\b")
# What the runner puts before a Godot line it repeats: an indent, `-> ` (a FAIL line's detail) and `#<instance> `
# (bots.show_failures over ENet).
INSTANCE_RE = re.compile(r"^\s*(?:-> )?(?:#\d+ )?")
INSTANCE_ONLY_RE = re.compile(r"^\s*#\d+ ")


def first_failure(step: str, output: str) -> str:
    lines = [gdunit.ANSI_RE.sub("", line).rstrip() for line in output.splitlines()]
    head = next((line[len(FAIL_LINE) :].strip() for line in lines if line.startswith(FAIL_LINE)), "")
    reason = ""
    for index, line in enumerate(lines if step in REASON_STEPS else ()):
        text = INSTANCE_RE.sub("", line, count=1)
        if launch.ERROR_RE.match(text):
            reason = text
        elif RUN_FAILED_RE.match(text):
            under = INSTANCE_ONLY_RE.sub("", lines[index + 1], count=1) if index + 1 < len(lines) else ""
            reason = under.strip() if under.startswith("  ") and under.strip() else text
        if reason:
            break
    if head and reason and reason not in head:
        return gdunit.clip(f"{head} | {reason}")
    return gdunit.clip(head or reason or next((line for line in reversed(lines) if line.strip()), ""))


def step_record(step: StepRun) -> dict[str, object]:
    """A step in the history record: name, lane, status and seconds; its own fields (`test`: shards, failing tests);
    and when it is red, its first failure line."""
    record: dict[str, object] = {"name": step.name, "lane": step.lane, "status": step.status,
                                 "seconds": round(step.seconds, 1), **step.detail}  # fmt: skip
    if step.status != "passed" and (line := first_failure(step.name, step.output)):
        record["failure"] = line
    return record


# The summary row's note on a step whose project check passed although Godot crashed at exit (#442): the summary is
# what publish's verify tail and the PR bodies carry, so the crash is seen there (#449). The row keeps its
# `<status> <name> <seconds>s` start, which metrics.STEP_LINE reads.
EXIT_CRASH_NOTE = "(Godot crashed at exit, #442)"


def step_note(step: StepRun) -> str:
    """What the summary prints after a step's seconds: '' for most steps. A red check step whose project check passed
    the crash failed for another reason (the warnings policy, the import, UID lint, credits), and its row says so."""
    if not step.detail.get("exit_crash"):
        return ""
    if step.status != "passed":
        return f"  {EXIT_CRASH_NOTE[:-1]}; red for another reason)"
    return f"  {EXIT_CRASH_NOTE}"


def not_started_line(steps: list[StepRun]) -> str:
    """The summary's line on the process starts Windows refused (#441), '' when there were none: how many, in which
    steps, how many restarts ran, and what a red step that names them means."""
    totals: Counter[str] = Counter()
    where = []
    for step in steps:
        counts = step.detail.get("not_started")
        if isinstance(counts, dict):
            totals.update({key: int(value) for key, value in counts.items() if isinstance(value, int)})
            where.append(step.name)
    if not totals["refused"]:
        return ""
    return (
        f"NOT STARTED: Windows refused {totals['refused']} process start(s) (exit 3221225794, 0xC0000142) in"
        f" {', '.join(where)}; {totals['restarted']} restarted once, {totals['recovered']} of them ran. A step red only"
        " with `could not start` is this PC's load, not the change: run verify again (`slots --status`, #441)"
    )


def append_history(record: dict[str, object]) -> None:
    try:
        ensure_out()
        with HISTORY.open("a", encoding="utf-8", newline="\n") as out:
            out.write(json.dumps(record) + "\n")
    except OSError as exc:
        warn(f"could not append to {HISTORY}: {exc}")


def slot_pool(facts: dict[str, str | None]) -> tuple[slots.Pool | None, str]:
    """The machine-wide verify slots this run waits on (#185), or None and why: none on CI, none inside a verify."""
    me: dict[str, object] = {"worktree": ROOT.as_posix(), "branch": facts.get("branch")}
    return slots.for_verify(me, ci=IS_CI, inside=bool(os.environ.get(INSIDE_VAR)), say=say)


def main(run_lane: RunLane = run_lane_process) -> int:
    started = time.monotonic()
    start_time = datetime.now(UTC)
    before = git_status()
    facts = git_facts(clean=not before)
    run_id = uuid.uuid4().hex
    os.environ[RUN_ID_VAR] = run_id  # the lane processes inherit it; their selftest results carry it
    runs: dict[str, StepRun] = {}
    walls: dict[str, float] = {}
    t0 = time.monotonic()
    rc = run_step("doctor")
    say()
    runs["doctor"] = StepRun("doctor", "main", "passed" if rc == 0 else "FAILED", time.monotonic() - t0)
    extra: list[StepRun] = []
    count_line, counts = "", {}
    taken: slots.Taken | None = None
    slot_line = ""
    if rc == 0:  # a wrong environment makes every later step meaningless
        pool, why = slot_pool(facts)
        slot_line = f"slot: {why}" if pool is None else ""
        with pool.held() if pool is not None else contextlib.nullcontext() as taken:
            if taken is not None:
                slot_line = taken.summary()
                say(f"verify: {slot_line}")
            described = "; ".join(f"{lane}: {', '.join(names)}" for lane, names in LANES.items())
            say(f"verify: two lanes at once ({described}); each step's output follows whole when it ends")
            say()
            printing = threading.Lock()

            def emit(step: StepRun) -> None:
                with printing:
                    runs[step.name] = step
                    _print_step(step)

            walls = run_lanes(run_lane, emit, printing)
        for lane, names in LANES.items():
            for name in names:
                runs.setdefault(name, StepRun(name, lane, "FAILED", 0.0))  # its lane never reported it
        problems, count_line, counts = count_after_lanes(run_id)
        if problems:
            for problem in problems:
                bad(problem)
            extra.append(StepRun("selftest-count", "main", "FAILED", 0.0))
    leftovers = sorted(git_status() - before)
    if leftovers:
        bad("verify left new or changed files in the working tree:", "\n".join(leftovers))
        extra.append(StepRun("clean tree", "main", "FAILED", 0.0))
    ordered = [runs[name] for name in STEP_ORDER if name in runs] + extra
    say("verify summary")
    for step in ordered:
        say(f"  {step.status:<7} {step.name:<14} {step.seconds:6.1f}s{step_note(step)}")
    if walls:
        say("  lanes: " + ", ".join(f"{lane} {seconds:.1f}s" for lane, seconds in walls.items())
            + f"; {os.cpu_count()} CPUs, selftest on {selftest_workers()} worker processes")  # fmt: skip
    if count_line:
        say(f"  {count_line}")
    if slot_line:
        say(f"  {slot_line}")
    if starts_line := not_started_line(ordered):
        say(f"  {starts_line}")
    failed = any(step.status != "passed" for step in ordered) or len(runs) < len(STEP_ORDER)
    waited = taken.waited if taken is not None else 0.0
    seconds = time.monotonic() - started - waited  # the run itself; the wait is its own field
    after = f" (after {waited:.1f}s waiting for a verify slot)" if taken is not None else ""
    over = "; it ran OVER THE LIMIT of verify slots" if taken is not None and taken.over else ""
    say(f"verify: {'FAILED' if failed else 'passed'} in {seconds:.1f}s{after}{over}")
    append_history(
        {
            "start": start_time.isoformat(timespec="seconds").replace("+00:00", "Z"),
            "worktree": ROOT.as_posix(),
            **facts,
            "status": "FAILED" if failed else "passed",
            "seconds": round(seconds, 1),
            "steps": [step_record(s) for s in ordered],
            "lanes": {lane: round(wall, 1) for lane, wall in walls.items()},
            "cpus": os.cpu_count(),
            "workers": selftest_workers(),
            "selftest": counts,
            "slot": taken.record() if taken is not None else None,
        }
    )
    return 1 if failed else 0


