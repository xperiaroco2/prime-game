"""`test`: GdUnit4 headless, judged by exit code and the JUnit XML (never the console summary); with no paths in
several processes at once (#182, the shards section)."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import threading
import xml.etree.ElementTree as ET
from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from pathlib import Path

from .common import (
    LOGS,
    OUT,
    ROOT,
    SCRATCH,
    Failure,
    Result,
    app_data_var,
    bad,
    ensure_out,
    git,
    godot,
    kill_tree,
    ok,
    require_godot,
    say,
    warn,
)
from .perf import FIXED_FPS

TIMEOUT = 600
REPORT_DIR = OUT / "gdunit"
# GdUnitCmdTool exit codes (GdUnit4 6.2.1, GdUnitTestSessionRunner.gd).
EXIT_MEANING = {
    0: "all tests passed",
    100: "tests failed",
    101: "orphan nodes detected: free the Nodes a test creates, or wrap them in auto_free(). Orphans fail the build",
    103: "GdUnit4 refused to run headless (missing --ignoreHeadlessMode)",
    104: "GdUnit4 does not support this Godot version",
    105: "script errors while discovering tests (a test file does not compile; run `check`)",
}


@dataclass
class JUnit:
    tests: int = 0
    failures: list[str] = field(default_factory=list)


def parse_junit(path: Path) -> JUnit:
    """Totals and failure messages from a GdUnit4 results.xml."""
    root = ET.parse(path).getroot()
    result = JUnit()
    for case in root.iter("testcase"):
        result.tests += 1
        for tag in ("failure", "error"):
            for node in case.findall(tag):
                where = f"{case.get('classname', '?')}::{case.get('name', '?')}"
                head = (node.get("message") or tag).strip()
                # The body holds the expectation, e.g. "Expecting: 3 but was 2"; keep it on one line.
                body = [line.strip() for line in (node.text or "").splitlines() if line.strip()]
                body = [line for line in body if not line.startswith("at '")][:6]
                result.failures.append(f"{where}: {head}" + (f" | {' '.join(body)}" if body else ""))
    return result


# Orphans appear only in the console log, never in results.xml (GdUnit4 6.2.1, GdUnitConsoleTestReporter.gd).
# The log is ANSI-coloured. A test's orphans (including leaks in before_test/after_test) follow its status line
# "res://<suite>.gd > <test> PASSED"; a suite's before()/after() orphans follow "<suite_name> > finalize()".
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
SUITE_RE = re.compile(r"Run Test Suite: (res://\S+)")
TEST_RE = re.compile(r"^\s*(res://\S+) > (.+?) (?:STARTED|PASSED|FAILED|WARNING|SKIPPED|FLAKY)\b")
FINALIZE_RE = re.compile(r"^\s*\S+ > finalize\(\)")
ORPHANS_RE = re.compile(r"Detected (\d+) (?:possible )?orphan nodes")


def orphan_leaks(log: str) -> list[tuple[str, str, int]]:
    """Each leak of a GdUnit4 console log: (the suite's res:// path, the test or "before()/after()", "" for a leak
    outside both, and how many nodes)."""
    suite, test, found = "?", "", []
    for raw in log.splitlines():
        line = ANSI_RE.sub("", raw)
        if match := SUITE_RE.search(line):
            suite, test = match.group(1), ""
        elif match := TEST_RE.match(line):
            suite, test = match.group(1), match.group(2)
        elif FINALIZE_RE.match(line):
            test = "before()/after()"
        elif match := ORPHANS_RE.search(line):
            found.append((suite, test, int(match.group(1))))
    return found


def parse_orphans(log: str) -> list[str]:
    """Which test or suite hook leaked how many nodes, from a GdUnit4 console log."""
    return [f"{suite}{f' > {test}' if test else ''}: {count} orphan node(s)" for suite, test, count in orphan_leaks(log)]


# --- the history record (#273) ----------------------------------------------------------------------------------
# What the last `test` run found, for verify's history record (docs/AGENT_WORKFLOW.md §11): each GdUnit4 process's
# exit code and seconds (shard 1 is the one process of a run without shards), and the tests that failed or leaked
# nodes, as "<suite>::<test>" in GdUnit4's names. main() sets it; verify's lane takes it after the step. Capped, so the
# history file stays small: at most RECORD_CAP tests (the rest counted) and MESSAGE_CAP characters per message.
RECORD_CAP = 20
MESSAGE_CAP = 240
LAST_RUN: dict[str, object] | None = None


def clip(text: str, cap: int = MESSAGE_CAP) -> str:
    """One line of at most `cap` characters."""
    text = " ".join(text.split())
    return text if len(text) <= cap else text[: cap - 3] + "..."


def failed_cases(path: Path) -> list[dict[str, object]]:
    """Each failed test of a results.xml: {test: "<suite>::<test>", message: its first failure on one line}. A test
    with several failed asserts takes one entry, so it never pushes other tests past RECORD_CAP."""
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return []
    found: list[dict[str, object]] = []
    for case in root.iter("testcase"):
        for node in [child for child in case if child.tag in ("failure", "error")][:1]:
            # The body is the assertion over several lines ("Expecting:", " 3", " but was", " 2"), then the stack
            # ("at '<test>' in <file>:<line>"); the message attribute only names the line.
            lines: list[str] = []
            for line in (node.text or "").splitlines():
                if line.strip().startswith("at '"):
                    break
                lines += [line.strip()] if line.strip() else []
            first = " ".join(lines) or node.get("message") or node.tag
            found.append({"test": f"{case.get('classname', '?')}::{case.get('name', '?')}", "message": clip(first)})
    return found


def leaked_cases(log: str) -> list[dict[str, object]]:
    """Each orphan leak of a console log: {test: "<suite>::<test or before()/after()>", orphans: nodes}."""
    return [
        {"test": f"{Path(suite).stem}::{test or '?'}", "orphans": count} for suite, test, count in orphan_leaks(log)
    ]


def process_record(shard: int, res: Result | None, reports: list[Path], error: str = "") -> dict[str, object]:
    """One GdUnit4 process: its exit code and seconds; timed_out, a missing results.xml (a crash) and an error that
    kept it from starting only when they happened."""
    if res is None:
        return {"shard": shard, "rc": None, "seconds": 0.0, "error": clip(error)}
    entry: dict[str, object] = {"shard": shard, "rc": res.rc, "seconds": round(res.seconds, 1)}
    if res.timed_out:
        entry["timed_out"] = True
    if not reports:
        entry["results"] = False
    return entry


def _failed(res: Result | None, reports: list[Path]) -> list[dict[str, object]]:
    if res is None:
        return []
    return (failed_cases(reports[-1]) if reports else []) + (leaked_cases(res.out) if res.rc == 101 else [])


def _remember(processes: list[dict[str, object]], failed: list[dict[str, object]]) -> None:
    global LAST_RUN
    record: dict[str, object] = {"shards": processes}
    if failed:
        record["failed_tests"] = failed[:RECORD_CAP]
        if len(failed) > RECORD_CAP:
            record["failed_tests_more"] = len(failed) - RECORD_CAP
    LAST_RUN = record


def take_last_run() -> dict[str, object] | None:
    """The last run's record (above), once: the next call returns None until another run."""
    global LAST_RUN
    record, LAST_RUN = LAST_RUN, None
    return record


def default_suites(tests_dir: Path) -> list[str]:
    """What a run with no paths covers: every folder and script under tests/ except the scratch folder.

    GdUnit4 loads every script it scans before `-i` can skip one, so a broken probe in tests/scratch/ would fail the
    whole run (exit 105): the scratch folder is left out of the scan instead of ignored.
    """
    scratch = SCRATCH.removeprefix("tests/")
    return [
        "res://tests/" + entry.name
        for entry in sorted(tests_dir.iterdir())
        if not entry.name.startswith(".")
        and entry.name != scratch
        and (entry.is_dir() or entry.suffix == ".gd")
    ]


def main(
    paths: list[str] | None = None, run_import: bool = True, shards: int | None = None, fixed_fps: bool = False
) -> int:
    """`test`: with no paths, the suites in several GdUnit4 processes at once (the shards below); with paths, or
    with one shard, one process as before #182. `shards` is `--shards K` (1: one process). `fixed_fps` is
    `test --fixed-fps` (#280, the fixed-fps section below): never on unless asked for, so verify stays real-time."""
    global LAST_RUN
    LAST_RUN = None
    say("test" + (f" --fixed-fps ({FIXED_FPS})" if fixed_fps else ""))
    ensure_out()
    tests_dir = ROOT / "tests"
    if not tests_dir.is_dir():
        raise Failure("no tests/ directory")
    count, why = shard_count(paths, shards)
    if fixed_fps and not paths and count < 2:
        raise Failure(
            "--fixed-fps with no paths runs the listed suites in a process of their own, which needs a per-process "
            "user:// (Windows: APPDATA, Linux: XDG_DATA_HOME)"
            if why == "no per-process user://"
            else f"--fixed-fps with no paths runs the listed suites in a process of their own, but {why} gives one "
            "process: give --shards 2 or more"
        )
    if run_import:
        # The class cache must be current, or new class_name suites fail to resolve. One import for every shard.
        from .check import run_import as do_import

        for line in do_import("test-import"):
            bad(f"import: {line} (run `check` for details)")
    shutil.rmtree(REPORT_DIR, ignore_errors=True)
    failed = run_shards(selectors(paths, tests_dir), count, why, fixed_fps, bool(paths)) if count > 1 else None
    if failed is None:
        # One process: at fixed fps only for named paths (a run without paths keeps the rest real-time).
        fixed = fixed_fps and bool(paths)
        res = godot(_args(paths, tests_dir, FIXED_FPS_ARGS if fixed else ()), timeout=TIMEOUT, log="test")
        reports = _reports()
        _remember([process_record(1, res, reports)], _failed(res, reports))
        if res.timed_out:
            raise Failure(f"tests timed out after {TIMEOUT}s (log: tools/out/logs/test.log)")
        failed = _judge(res.rc, res.out, reports, "tools/out/logs/test.log")
        record_times(reports[-1:], FIXED_KEY if fixed else SUITES_KEY)
    say("test: FAILED" if failed else "test: passed")
    return 1 if failed else 0


def selectors(paths: list[str] | None, tests_dir: Path) -> list[str]:
    """The res:// paths a run covers: the given ones, or default_suites."""
    return [
        item if item.startswith("res://") else "res://" + item.replace("\\", "/")
        for item in paths or default_suites(tests_dir)
    ]


def _args(paths: list[str] | None, tests_dir: Path, engine_args: Sequence[str] = ()) -> list[str]:
    return _command(selectors(paths, tests_dir), "res://tools/out/gdunit", engine_args)


def _command(items: list[str], report_dir: str, engine_args: Sequence[str] = ()) -> list[str]:
    """GdUnit4's command line. `engine_args` (FIXED_FPS_ARGS) go before `-s`: GdUnitCmdTool's argument parser skips
    everything before its own script, so the engine reads them and GdUnit4 never sees them."""
    selected: list[str] = []
    for item in items:
        selected += ["-a", item]
    return [
        "--headless",
        *engine_args,
        "-s",
        "res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
        "--ignoreHeadlessMode",
        "-c",
        *selected,
        "-rd",
        report_dir,
        "-rc",
        "1",
    ]


def _reports() -> list[Path]:
    return sorted(REPORT_DIR.glob("report_*/results.xml"))


def _judge(rc: int, out: str, reports: list[Path], log: str, label: str = "") -> bool:
    """Print what went wrong in one GdUnit4 run (a shard's lines start with its label); True when it failed."""
    bad, ok = _labelled(label)
    junit = parse_junit(reports[-1]) if reports else None
    failed = rc != 0
    if rc not in EXIT_MEANING:
        bad(f"GdUnit4 crashed or exited unexpectedly (exit {rc}); log: {log}")
    elif rc != 0:
        bad(f"exit {rc}: {EXIT_MEANING[rc]}")
    if rc == 101:
        leaks = parse_orphans(out)
        for line in leaks:
            bad(line)
        if not leaks:
            bad(f"could not tell which test leaked; log: {log}")
    if junit is None:
        failed = True
        bad(f"no results.xml written; log: {log}")
    else:
        for line in junit.failures:
            bad(line)
        if junit.failures:
            failed = True
        if junit.tests == 0:
            failed = True
            bad("no tests ran; an empty suite is not a pass")
        elif not failed:
            ok(f"{junit.tests} tests passed (report: {reports[-1].relative_to(ROOT).as_posix()})")
    return failed


def _labelled(label: str) -> tuple[Callable[[str], None], Callable[[str], None]]:
    """bad and ok, with a shard's label before each line."""
    if not label:
        return bad, ok
    return (lambda text: bad(f"{label}: {text}")), (lambda text: ok(f"{label}: {text}"))


# --- shards (#182) ----------------------------------------------------------------------------------------------
# `test` with no paths runs the suites in K GdUnit4 processes at once (a shard each), balanced by the last per-suite
# times. Each shard process gets a user:// of its own through the app-data variable (common.app_data_var), since
# GdUnit4 clears and fills user://tmp on every run; each writes its report to tools/out/gdunit/shard-<i>/ and its log
# to tools/out/logs/test-shard<i>.log. Every shard is judged as a one-process run is (exit code, results.xml,
# orphans); then the merged tools/out/gdunit/results.xml is checked against a one-process scan: every suite such a
# run would run ran exactly once, with every test function it declares.
SHARDS_VAR = "PRIME_TEST_SHARDS"
# K = half the logical CPUs, at most SHARD_CAP: CI's 4 vCPUs give 2, the engineer's PC (16 logical, 8 physical) the
# cap, so the shards and the Python lane's 4 selftest workers together fill its 8 cores. Measured there on a quiet
# machine (#182, 2026-10-02): `test` in 295 s with one process, 156 s with 2, 108 s with 3, 86 s with 4, 72 s with 5.
SHARD_CAP = 4
SHARD_USER = OUT / "gdunit-user"
TIMES = LOGS / "gdunit-times.json"
EXTENDS_RE = re.compile(r"^(?:class_name\s+\w+\s+)?extends\s+(\"[^\"]+\"|'[^']+'|[\w.]+)", re.MULTILINE)
CLASS_NAME_RE = re.compile(r"^class_name\s+(\w+)", re.MULTILINE)
TEST_FUNC_RE = re.compile(r"^func\s+(test_\w+)\s*\(", re.MULTILINE)


def default_shards(cpus: int | None = None) -> int:
    return max(1, min(SHARD_CAP, (cpus if cpus is not None else os.cpu_count() or 1) // 2))


def shard_count(paths: list[str] | None, shards: int | None) -> tuple[int, str]:
    """How many processes a run takes, and why: `--shards K`, else one for named paths, else PRIME_TEST_SHARDS, else
    default_shards(). Without a per-process user:// on this OS, one."""
    if shards is not None:
        if shards < 1:
            raise Failure("--shards must be at least 1")
        count, why = shards, f"--shards {shards}"
    elif paths:
        return 1, "named paths"
    elif os.environ.get(SHARDS_VAR):
        try:
            count = int(os.environ[SHARDS_VAR])
        except ValueError:
            count = 0
        if count < 1:
            raise Failure(f"{SHARDS_VAR} must be a whole number of at least 1, not {os.environ[SHARDS_VAR]!r}")
        why = f"{SHARDS_VAR}={count}"
    else:
        count = default_shards()
        why = f"{os.cpu_count()} CPUs, at most {SHARD_CAP}"
    if count > 1 and app_data_var() is None:
        warn("no per-process user:// on this OS (Windows: APPDATA, Linux: XDG_DATA_HOME): one process")
        return 1, "no per-process user://"
    return count, why


def _res(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def _walk(folder: Path) -> list[Path]:
    """The .gd files GdUnit4's scanner loads under a folder: hidden entries and folders with a .gdignore left out."""
    if (folder / ".gdignore").exists():
        return []
    found: list[Path] = []
    for entry in sorted(folder.iterdir()):
        if entry.name.startswith("."):
            continue
        if entry.is_dir():
            found += _walk(entry)
        elif entry.suffix == ".gd":
            found.append(entry)
    return found


def script_files(items: list[str]) -> list[str]:
    """Every script a one-process run loads for these selectors, as res:// paths, each once: a .gd file as given, a
    folder walked as GdUnit4 walks it. Together the shards load exactly these, so they find the suites a one-process
    run finds (GdUnit4 decides which are suites, as it does in a folder)."""
    found: dict[str, None] = {}
    for item in items:
        path = ROOT / item.removeprefix("res://")
        if path.is_dir():
            found.update(dict.fromkeys(_res(p) for p in _walk(path)))
        elif path.is_file() and path.suffix == ".gd":
            found[_res(path)] = None
    return list(found)


def static_suites(files: list[str]) -> dict[str, list[str]]:
    """The suites among files as a one-process scan finds them (a script whose `extends` chain reaches
    GdUnitTestSuite, through a class_name under tests/ or a quoted path), each with the test functions it declares."""
    texts: dict[str, str] = {}

    def text(res: str) -> str:
        if res not in texts:
            try:
                texts[res] = (ROOT / res.removeprefix("res://")).read_text(encoding="utf-8")
            except OSError:
                texts[res] = ""
        return texts[res]

    classes: dict[str, str] = {}
    for path in _walk(ROOT / "tests") if (ROOT / "tests").is_dir() else []:
        if match := CLASS_NAME_RE.search(text(_res(path))):
            classes[match.group(1)] = _res(path)

    def is_suite(res: str, seen: set[str]) -> bool:
        match = EXTENDS_RE.search(text(res))
        if match is None or res in seen:
            return False
        base = match.group(1)
        if base == "GdUnitTestSuite":
            return True
        if base[0] in "\"'":
            target = base[1:-1]
            if not target.startswith("res://"):
                try:
                    target = _res((ROOT / res.removeprefix("res://")).parent.joinpath(target).resolve())
                except ValueError:  # a path outside the project: no suite of ours
                    return False
        elif base in classes:
            target = classes[base]
        else:
            return False
        return is_suite(target, seen | {res})

    return {res: TEST_FUNC_RE.findall(text(res)) for res in files if is_suite(res, set())}


def suite_key(suite: ET.Element) -> str:
    """A results.xml testsuite as the res:// path of its script (GdUnit4 names a suite after its file)."""
    package = (suite.get("package") or "").strip("/")
    return f"res://{package}/{suite.get('name') or '?'}.gd"


def suite_times(report: Path) -> dict[str, float]:
    times: dict[str, float] = {}
    try:
        for suite in ET.parse(report).getroot().iter("testsuite"):
            times[suite_key(suite)] = float(suite.get("time") or 0.0)
    except (OSError, ET.ParseError, ValueError):
        pass
    return times


# TIMES holds a map per clock: real-time seconds under SUITES_KEY (what the shards of verify and CI are balanced by)
# and seconds at --fixed-fps under FIXED_KEY (#280), so a fixed-fps run never skews a real-time plan.
SUITES_KEY, FIXED_KEY = "suites", "fixed_fps"


def _load_file(path: Path) -> dict[str, object]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _load_times(path: Path, key: str = SUITES_KEY) -> dict[str, float]:
    suites = _load_file(path).get(key)
    try:
        return {str(k): float(v) for k, v in suites.items()} if isinstance(suites, dict) else {}
    except (ValueError, TypeError):
        return {}


def record_times(reports: list[Path], key: str = SUITES_KEY) -> None:
    """Merge the suites' seconds of a run into TIMES under `key` (a suite this run did not run keeps its last time;
    one whose script is gone is dropped); every other key of the file is kept. Every run records, a run of named
    paths too."""
    found: dict[str, float] = {}
    for report in reports:
        found.update(suite_times(report))
    if not found:
        return
    data = _load_file(TIMES)
    merged = {**_load_times(TIMES, key), **found}
    data[key] = {k: v for k, v in sorted(merged.items()) if (ROOT / k.removeprefix("res://")).is_file()}
    try:
        ensure_out()
        TIMES.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8", newline="\n")
    except OSError as exc:
        warn(f"could not write {TIMES}: {exc}")


def read_times(key: str = SUITES_KEY) -> tuple[dict[str, float], str]:
    """The last per-suite times under `key` and where they came from: this checkout's TIMES, else (a fresh worktree)
    the newest TIMES of another checkout of this clone (read only), else none (then every suite counts the same)."""
    own = _load_times(TIMES, key)
    if own:
        return own, TIMES.relative_to(ROOT).as_posix()
    res = git("worktree", "list", "--porcelain")
    others = []
    for line in res.lines if res.rc == 0 else []:
        if line.startswith("worktree "):
            folder = Path(line.removeprefix("worktree ").strip())
            candidate = folder / TIMES.relative_to(ROOT)
            if folder.resolve() != ROOT.resolve() and candidate.is_file():
                others.append((candidate.stat().st_mtime, candidate))
    for _mtime, candidate in sorted(others, reverse=True):
        times = _load_times(candidate, key)
        if times:
            return times, f"{candidate.as_posix()} (this checkout has no times yet)"
    return {}, "no times yet: every suite counts the same"


def estimates(files: list[str], suites: dict[str, list[str]], times: dict[str, float]) -> dict[str, float]:
    """Each script's expected seconds: a suite's last time (at least a millisecond), a suite with none the mean of
    the known ones (1 s without any), any other script 0."""
    known = [times[res] for res in suites if res in times]
    fallback = sum(known) / len(known) if known else 1.0
    return {res: max(times.get(res, fallback), 0.001) if res in suites else 0.0 for res in files}


def plan_shards(costs: dict[str, float], count: int) -> list[list[str]]:
    """Longest first, each to the shard with the least so far (ties: the lower shard). With count at most the number
    of scripts that cost something, every shard gets at least one of them. Each shard's scripts in path order."""
    loads = [0.0] * count
    shards: list[list[str]] = [[] for _ in range(count)]
    for res in sorted(costs, key=lambda r: (-costs[r], r)):
        index = min(range(count), key=lambda i: (loads[i], i))
        shards[index].append(res)
        loads[index] += costs[res]
    return [sorted(shard) for shard in shards]


# --- fixed fps (#280) -------------------------------------------------------------------------------------------
# `test --fixed-fps` runs frame-bound suites with the engine's `--fixed-fps 60`: each frame then counts as 1/60 s of
# game time however fast the machine renders it, so a suite that steps physics frames on a simulated clock (NetPair's
# or the test's own over the LoopbackHub) runs as fast as the CPU allows instead of at wall-clock speed. 60 is the
# project's physics ticks per second (the default; project.godot sets none) and perf's FIXED_FPS, so each frame runs
# exactly one physics step. That is also what it hides: a frame never runs several physics steps, the condition
# behind #222 and #225, so verify, CI and the nightly flaky job stay real-time (that coverage; #280 keeps the flag off
# by default) and only a human asks for it. A CLI flag, never an environment variable, so a local verify equals CI
# (N4 (a) of docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md).
FIXED_FPS_ARGS: tuple[str, ...] = ("--fixed-fps", FIXED_FPS)
# The suites a run without paths takes at fixed fps, in shards of their own: frame-bound, on NetPair's or the test's
# simulated clock over the LoopbackHub, measured green 10 runs in a row each (#280). Never an audio or ENet suite.
FIXED_FPS_SUITES: tuple[str, ...] = (
    "res://tests/integration/client/app/game_loop_test.gd",
    "res://tests/integration/client/life/life_network_test.gd",
    "res://tests/integration/client/life/spectate_network_test.gd",
    "res://tests/integration/client/player/player_controller_downed_test.gd",
    "res://tests/integration/client/player/player_controller_push_test.gd",
    "res://tests/integration/client/player/player_controller_test.gd",
    "res://tests/integration/client/player/player_network_push_test.gd",
    "res://tests/integration/client/player/player_network_sprint_test.gd",
    "res://tests/integration/client/player/player_network_test.gd",
)
# A fixed-fps suite with no time at fixed fps yet is planned at its real-time seconds over this, so the first
# `test --fixed-fps` of a checkout is balanced too. Measured in #280 on a quiet PC: the 9 took 284 s real-time and
# 22.7 s at fixed fps (medians of 10 runs each, 12.5x), and their shard 28 to 32 s with its start-up: 10x. A CPU-bound
# suite on a busy PC gains less (2.3x seen beside a 100 % CPU load).
FIXED_FPS_SPEEDUP = 10.0


def fixed_set(suites: dict[str, list[str]], paths: list[str] | None) -> set[str]:
    """The suites of a --fixed-fps run that run at fixed fps: every one of named paths, else FIXED_FPS_SUITES (a
    listed suite the scan did not find is named, since the list has gone stale)."""
    if paths:
        return set(suites)
    gone = [res for res in FIXED_FPS_SUITES if res not in suites]
    if gone:
        warn(f"--fixed-fps: listed suites the scan did not find ({len(gone)}): {', '.join(gone)}; "
             "update gdunit.FIXED_FPS_SUITES")  # fmt: skip
    return {res for res in FIXED_FPS_SUITES if res in suites}


def fixed_times(fixed: set[str], times: dict[str, float], at_fixed: dict[str, float]) -> dict[str, float]:
    """The planning seconds of the fixed-fps suites: the last time at fixed fps, else the real-time one over
    FIXED_FPS_SPEEDUP (a suite with neither keeps estimates' real-time mean)."""
    found = {res: times[res] / FIXED_FPS_SPEEDUP for res in fixed if res in times}
    found.update({res: at_fixed[res] for res in fixed if res in at_fixed})
    return found


def split_shards(costs: dict[str, float], fixed: set[str], count: int) -> list[tuple[list[str], bool]]:
    """The scripts in `count` shards, each real-time (False) or at fixed fps (True): plan_shards on each group, with
    the number of fixed shards that gives the shortest longest shard (ties: fewer fixed shards). Every shard gets a
    suite that costs something; the scripts that cost nothing (helpers) go with the real-time group, or with the fixed
    group when every suite is fixed. Needs count at most the number of scripts that cost something."""
    paid = [res for res in costs if costs[res] > 0]
    fixed_paid = [res for res in paid if res in fixed]
    real_paid = [res for res in paid if res not in fixed]
    free = {res: 0.0 for res in costs if costs[res] <= 0}
    if not fixed_paid:
        return [(shard, False) for shard in plan_shards(costs, count)]
    if not real_paid:
        return [(shard, True) for shard in plan_shards(costs, count)]

    def makespan(group: list[str], n: int) -> float:
        return max(sum(costs[res] for res in shard) for shard in plan_shards({r: costs[r] for r in group}, n))

    low, high = max(1, count - len(real_paid)), min(count - 1, len(fixed_paid))
    best = min(range(low, high + 1), key=lambda f: (max(makespan(fixed_paid, f), makespan(real_paid, count - f)), f))
    fixed_plan = plan_shards({res: costs[res] for res in fixed_paid}, best)
    real_plan = plan_shards({**{res: costs[res] for res in real_paid}, **free}, count - best)
    return [(shard, True) for shard in fixed_plan] + [(shard, False) for shard in real_plan]


def merge_junit(reports: list[Path]) -> ET.Element:
    """One <testsuites> of every report's suites (in path order, renumbered), with the reports' totals summed."""
    totals: Counter[str] = Counter()
    suites: list[ET.Element] = []
    first_id = ""
    for report in reports:
        root = ET.parse(report).getroot()
        first_id = first_id or root.get("id", "")
        for key in ("tests", "failures", "skipped", "flaky"):
            totals[key] += int(root.get(key) or 0)
        suites += root.findall("testsuite")
    suites.sort(key=lambda s: (s.get("package") or "", s.get("name") or ""))
    seconds = sum(float(s.get("time") or 0.0) for s in suites)
    attrs = {"id": first_id, "name": "merged", **{k: str(totals[k]) for k in ("tests", "failures", "skipped", "flaky")}}
    merged = ET.Element("testsuites", {**attrs, "time": f"{seconds:.3f}"})
    for index, suite in enumerate(suites):
        suite.set("id", str(index))
        merged.append(suite)
    return merged


def _base_name(name: str) -> str:
    match = re.match(r"\w+", name)
    return match.group(0) if match else name


def coverage(expected: dict[str, list[str]], merged: ET.Element, shards: int) -> tuple[list[str], list[str], str]:
    """The merged results against a one-process scan: (problems that fail the run, warnings, the count line). A suite
    that declares no test function (a base class) runs no test case of its own, so it is not expected to appear."""
    expected = {key: tests for key, tests in expected.items() if tests}
    ran: Counter[str] = Counter()
    names: dict[str, set[str]] = {}
    cases = 0
    for suite in merged.iter("testsuite"):
        key = suite_key(suite)
        ran[key] += 1
        found = [case.get("name", "") for case in suite.iter("testcase")]
        cases += len(found)
        names.setdefault(key, set()).update(_base_name(name) for name in found)
    missing = sorted(set(expected) - set(ran))
    doubled = sorted(key for key, n in ran.items() if n > 1)
    short = sorted(
        f"{key} ({', '.join(sorted(set(tests) - names[key])[:3])})"
        for key, tests in expected.items()
        if key in names and set(tests) - names[key]
    )
    extra = sorted(set(ran) - set(expected))

    def listed(items: list[str]) -> str:
        return f"({len(items)}): " + ", ".join(items[:5]) + (" ..." if len(items) > 5 else "")

    problems = [
        f"suites {label} {listed(items)}"
        for label, items in (
            ("that a one-process run would run but that never ran", missing),
            ("that ran in more than one shard", doubled),
            ("that ran without some of their test functions", short),
        )
        if items
    ]
    warnings = (
        [f"suites that ran (once each) but the runner's scan did not expect {listed(extra)}; "
         "teach gdunit.static_suites their base class"]  # fmt: skip
        if extra
        else []
    )
    functions = sum(len(tests) for tests in expected.values())
    line = (
        f"{len(ran)} suites and {cases} test cases ran in {shards} processes; "
        f"a one-process scan finds {len(expected)} suites with {functions} test functions"
    )
    return problems, warnings, line


@dataclass
class ShardRun:
    index: int
    scripts: list[str]
    expected_seconds: float
    engine_args: list[str] = field(default_factory=list)  # FIXED_FPS_ARGS for a fixed-fps shard (#280)
    result: Result | None = None
    error: str = ""

    @property
    def clock(self) -> str:
        """How the shard's lines end: its engine args, or nothing for a real-time shard."""
        return f" at {' '.join(self.engine_args)}" if self.engine_args else ""

    @property
    def log(self) -> str:
        return f"test-shard{self.index}"

    @property
    def report_dir(self) -> Path:
        return REPORT_DIR / f"shard-{self.index}"

    @property
    def user_root(self) -> Path:
        return SHARD_USER / f"shard-{self.index}"


def run_shards(
    items: list[str], count: int, why: str, fixed_fps: bool = False, named: bool = False
) -> bool | None:
    """Run the suites under the selectors in `count` processes at once; True when the run failed. None when fewer
    than two suites are found: the caller runs them in one process. With `fixed_fps`, the fixed-fps suites (every
    suite of `named` paths, else FIXED_FPS_SUITES) run at --fixed-fps in shards of their own (split_shards)."""
    files = script_files(items)
    # Only a suite that declares a test function weighs in the plan: a base class alone runs no test case, and a
    # GdUnit4 process given no test case writes no results.xml.
    suites = {res: tests for res, tests in static_suites(files).items() if tests}
    if len(suites) < 2:
        return None
    count = min(count, len(suites))
    times, source = read_times()
    costs = estimates(files, suites, times)
    fixed: set[str] = set()
    if fixed_fps:
        fixed = fixed_set(suites, items if named else None)
        at_fixed, fixed_source = read_times(FIXED_KEY)
        costs.update({res: max(s, 0.001) for res, s in fixed_times(fixed, times, at_fixed).items()})
        by = fixed_source if at_fixed else f"their real-time seconds / {FIXED_FPS_SPEEDUP:g}"
        source += f"; the {len(fixed)} at --fixed-fps {FIXED_FPS} by {by}"
    plan = split_shards(costs, fixed, count)
    runs = [
        ShardRun(i, scripts, sum(costs[s] for s in scripts), list(FIXED_FPS_ARGS) if at_fps else [])
        for i, (scripts, at_fps) in enumerate(plan, 1)
    ]
    say(f"test: {count} GdUnit4 processes at once ({why}), {len(suites)} suites balanced by {source}")
    for shard in runs:
        n = sum(s in suites for s in shard.scripts)
        say(f"        shard {shard.index}: {n} suites, about {shard.expected_seconds:.0f}s by those times{shard.clock}")
    shutil.rmtree(SHARD_USER, ignore_errors=True)
    _run_parallel(runs)
    return _judge_shards(runs, suites)


def _run_parallel(runs: list[ShardRun]) -> None:
    """Each shard in a thread of its own; Ctrl+C stops every shard's process tree."""
    require_godot()  # once, before the threads: the version check and the worktree's override.cfg
    var = app_data_var()
    assert var is not None
    live: list[subprocess.Popen[bytes]] = []
    lock = threading.Lock()

    def started(proc: subprocess.Popen[bytes]) -> None:
        with lock:
            live.append(proc)

    def one(shard: ShardRun) -> None:
        try:
            shard.result = godot(
                _command(shard.scripts, "res://" + shard.report_dir.relative_to(ROOT).as_posix(), shard.engine_args),
                timeout=TIMEOUT,
                log=shard.log,
                env={var: str(shard.user_root)},
                on_start=started,
            )
        except Exception as exc:  # noqa: BLE001 - a shard that could not start fails the run, not the other shards
            shard.error = str(exc) or type(exc).__name__

    threads = [threading.Thread(target=one, args=(shard,), daemon=True) for shard in runs]
    try:
        for thread in threads:
            thread.start()
        for thread in threads:
            while thread.is_alive():
                thread.join(0.5)  # a bounded join lets Ctrl+C through on Windows
    except BaseException:
        with lock:
            procs = list(live)
        for proc in procs:
            kill_tree(proc)
        raise


def _judge_shards(runs: list[ShardRun], suites: dict[str, list[str]]) -> bool:
    """Each shard judged as a one-process run is, then the merged results.xml against the one-process scan."""
    failed = False
    reports: list[Path] = []
    fixed_reports: list[Path] = []
    processes, failures = [], []
    for shard in runs:
        found = sorted(shard.report_dir.glob("report_*/results.xml"))
        processes.append(process_record(shard.index, shard.result, found, shard.error))
        failures += _failed(shard.result, found)
    _remember(processes, failures)
    for shard in runs:
        label, log = f"shard {shard.index}", f"tools/out/logs/{shard.log}.log"
        found = sorted(shard.report_dir.glob("report_*/results.xml"))
        res = shard.result
        if res is None:
            bad(f"{label}: could not start: {shard.error}")
            failed = True
            continue
        say(f"        {label}: {res.seconds:.1f}s (expected about {shard.expected_seconds:.0f}s), exit {res.rc}"
            f"{shard.clock}")  # fmt: skip
        if res.timed_out:
            bad(f"{label}: timed out after {TIMEOUT}s (log: {log})")
            failed = True
        else:
            failed = _judge(res.rc, res.out, found, log, label) or failed
        if not (shard.user_root.is_dir() and any(shard.user_root.iterdir())):
            bad(f"{label}: Godot put nothing under {shard.user_root.relative_to(ROOT).as_posix()}, so its user:// "
                "may be the shared one. Run `test --shards 1` and report it")  # fmt: skip
            failed = True
        reports += found[-1:]
        fixed_reports += found[-1:] if shard.engine_args else []
    _combined_log(runs)
    if not reports:
        bad("no shard wrote a results.xml")
        return True
    merged = merge_junit(reports)
    path = REPORT_DIR / "results.xml"
    ET.ElementTree(merged).write(path, encoding="UTF-8", xml_declaration=True)
    problems, warnings, line = coverage(suites, merged, len(runs))
    for problem in problems:
        bad(problem)
    for text in warnings:
        warn(text)
    (bad if problems else ok)(line)
    junit = parse_junit(path)
    if problems or junit.failures:
        failed = True
    if not failed:
        ok(f"{junit.tests} tests passed in {len(runs)} processes (report: {path.relative_to(ROOT).as_posix()})")
    record_times([report for report in reports if report not in fixed_reports])
    record_times(fixed_reports, FIXED_KEY)
    return failed


def _combined_log(runs: list[ShardRun]) -> None:
    """tools/out/logs/test.log: every shard's log in turn, where a one-process run leaves its log."""
    parts = []
    for shard in runs:
        out = shard.result.out if shard.result else shard.error + "\n"
        parts.append(f"===== shard {shard.index} ({len(shard.scripts)} scripts; tools/out/logs/{shard.log}.log)\n{out}")
    ensure_out()
    (LOGS / "test.log").write_text("".join(parts), encoding="utf-8")


# `test --repeat N` (the nightly flaky-test job, docs/AGENT_WORKFLOW.md "Night jobs"): the same suites N times in a
# row, each run's report kept, and a per-suite and per-test comparison of the runs.
RUNS_DIR = OUT / "gdunit-runs"
PASSED, FAILED, SKIPPED = "passed", "failed", "skipped"


@dataclass
class RunOutcome:
    run: int
    status: str  # "passed" or "FAILED": the same judgement as a plain `test`
    note: str  # GdUnit4's exit code in words, or what stopped the run
    cases: dict[str, str] = field(default_factory=dict)  # "<package>/<suite>::<test>" -> passed, failed or skipped


def case_results(path: Path) -> dict[str, str]:
    """Every test case of a GdUnit4 results.xml as "<package>/<suite>::<test>" -> passed, failed or skipped."""
    cases: dict[str, str] = {}
    for suite in ET.parse(path).getroot().iter("testsuite"):
        package = (suite.get("package") or "").strip("/")
        name = suite.get("name") or "?"
        prefix = f"{package}/{name}" if package else name
        for case in suite.iter("testcase"):
            if case.find("failure") is not None or case.find("error") is not None:
                status = FAILED
            elif case.find("skipped") is not None:
                status = SKIPPED
            else:
                status = PASSED
            cases[f"{prefix}::{case.get('name', '?')}"] = status
    return cases


def summarize(outcomes: list[RunOutcome]) -> dict[str, object]:
    """Runs, suites and tests compared across the runs. A test is flaky when it passed in one run and failed in
    another; a test missing from a run (the run crashed or timed out) or skipped in it counts neither way."""
    runs = [
        {
            "run": o.run,
            "status": o.status,
            "note": o.note,
            "tests": len(o.cases),
            "failed": sorted(k for k, v in o.cases.items() if v == FAILED),
        }
        for o in outcomes
    ]
    tests = sorted({key for o in outcomes for key in o.cases})
    flaky, every = [], []
    for key in tests:
        seen = [(o.run, o.cases[key]) for o in outcomes if o.cases.get(key, SKIPPED) != SKIPPED]
        failed_in = [run for run, status in seen if status == FAILED]
        if failed_in and any(status == PASSED for _, status in seen):
            flaky.append({"test": key, "failed_in_runs": failed_in})
        elif failed_in and len(failed_in) == len(seen):
            every.append(key)
    sizes: dict[str, int] = {}
    failed_per_run: dict[str, list[int]] = {}
    for key in tests:
        suite = key.split("::", 1)[0]
        sizes[suite] = sizes.get(suite, 0) + 1
        counts = failed_per_run.setdefault(suite, [0] * len(outcomes))
        for index, o in enumerate(outcomes):
            counts[index] += o.cases.get(key) == FAILED
    return {
        "runs": runs,
        "flaky": flaky,
        "failed_every_run": every,
        "suites": [{"suite": s, "tests": sizes[s], "failed_per_run": failed_per_run[s]} for s in sorted(sizes)],
    }


def summary_markdown(summary: dict[str, object]) -> str:
    """The summary as Markdown for the GitHub job summary: suites with a failure only; the JSON holds every suite."""
    runs = summary["runs"]
    assert isinstance(runs, list)
    lines = [f"## GdUnit4, {len(runs)} runs", "", "| run | status | tests | failed | note |", "|---|---|---|---|---|"]
    lines += [f"| {r['run']} | {r['status']} | {r['tests']} | {len(r['failed'])} | {r['note']} |" for r in runs]
    flaky, every, suites = summary["flaky"], summary["failed_every_run"], summary["suites"]
    assert isinstance(flaky, list) and isinstance(every, list) and isinstance(suites, list)
    lines += ["", "### Flaky tests (passed in one run, failed in another)", ""]
    lines += [f"- `{f['test']}`: failed in run(s) {', '.join(map(str, f['failed_in_runs']))}" for f in flaky] or ["None."]
    lines += ["", "### Failed in every run", ""]
    lines += [f"- `{key}`" for key in every] or ["None."]
    failing = [s for s in suites if any(s["failed_per_run"])]
    lines += ["", f"### Suites with a failure ({len(failing)} of {len(suites)})", ""]
    if failing:
        lines += ["| suite | tests | " + " | ".join(f"failed in run {r['run']}" for r in runs) + " |"]
        lines += ["|---|---|" + "---|" * len(runs)]
        lines += [f"| `{s['suite']}` | {s['tests']} | " + " | ".join(map(str, s["failed_per_run"])) + " |" for s in failing]
    else:
        lines += ["None."]
    return "\n".join(lines) + "\n"


def repeat(runs: int, paths: list[str] | None = None, run_import: bool = True, fixed_fps: bool = False) -> int:
    """`test --repeat N`: N runs one after another; any failed run fails it. Each run's report goes to
    tools/out/gdunit-runs/run-<i>/ and its log to tools/out/logs/test-run<i>.log; summary.json and summary.md compare
    them. `fixed_fps` (named paths only) runs every one at FIXED_FPS_ARGS, and summary.json says so."""
    if runs < 1:
        raise Failure("--repeat must be at least 1")
    if fixed_fps and not paths:
        raise Failure("--repeat with --fixed-fps needs the paths to run at fixed fps")
    say(f"test --repeat {runs}" + (f" --fixed-fps ({FIXED_FPS})" if fixed_fps else ""))
    ensure_out()
    tests_dir = ROOT / "tests"
    if not tests_dir.is_dir():
        raise Failure("no tests/ directory")
    if run_import:
        from .check import run_import as do_import

        for line in do_import("test-import"):
            bad(f"import: {line} (run `check` for details)")
    shutil.rmtree(RUNS_DIR, ignore_errors=True)
    RUNS_DIR.mkdir(parents=True)
    engine_args = FIXED_FPS_ARGS if fixed_fps else ()
    args = _args(paths, tests_dir, engine_args)
    outcomes: list[RunOutcome] = []
    for index in range(1, runs + 1):
        say(f"test: run {index} of {runs}")
        shutil.rmtree(REPORT_DIR, ignore_errors=True)
        log = f"test-run{index}"
        res = godot(args, timeout=TIMEOUT, log=log)
        reports = _reports()
        if res.timed_out:
            bad(f"run {index} timed out after {TIMEOUT}s (log: tools/out/logs/{log}.log)")
            outcome = RunOutcome(index, "FAILED", f"timed out after {TIMEOUT}s")
        else:
            failed = _judge(res.rc, res.out, reports, f"tools/out/logs/{log}.log")
            note = EXIT_MEANING.get(res.rc, f"exit {res.rc}: crashed or exited unexpectedly")
            outcome = RunOutcome(index, "FAILED" if failed else "passed", note)
        if reports:
            outcome.cases = case_results(reports[-1])
        if REPORT_DIR.is_dir():
            shutil.copytree(REPORT_DIR, RUNS_DIR / f"run-{index}")
        outcomes.append(outcome)
    summary = summarize(outcomes)
    if engine_args:
        summary["engine_args"] = list(engine_args)
    (RUNS_DIR / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n")
    (RUNS_DIR / "summary.md").write_text(summary_markdown(summary), encoding="utf-8", newline="\n")
    say(f"test --repeat {runs}: " + ", ".join(f"run {o.run} {o.status}" for o in outcomes))
    flaky, every = summary["flaky"], summary["failed_every_run"]
    assert isinstance(flaky, list) and isinstance(every, list)
    for entry in flaky:
        bad(f"flaky: {entry['test']} failed in run(s) {', '.join(map(str, entry['failed_in_runs']))} of {runs}")
    for key in every:
        bad(f"failed in every run: {key}")
    say(f"per-suite results: {(RUNS_DIR / 'summary.json').relative_to(ROOT).as_posix()} and summary.md")
    failed_any = any(o.status != "passed" for o in outcomes)
    say("test: FAILED" if failed_any else "test: passed")
    return 1 if failed_any else 0
