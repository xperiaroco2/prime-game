"""`test`: GdUnit4 headless, judged by exit code and the JUnit XML (never the console summary)."""

from __future__ import annotations

import json
import re
import shutil
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

from .common import OUT, ROOT, SCRATCH, Failure, bad, ensure_out, godot, ok, say

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


def parse_orphans(log: str) -> list[str]:
    """Which test or suite hook leaked how many nodes, from a GdUnit4 console log."""
    suite, subject, found = "?", "?", []
    for raw in log.splitlines():
        line = ANSI_RE.sub("", raw)
        if match := SUITE_RE.search(line):
            suite = subject = match.group(1)
        elif match := TEST_RE.match(line):
            subject = f"{match.group(1)} > {match.group(2)}"
        elif FINALIZE_RE.match(line):
            subject = f"{suite} > before()/after()"
        elif match := ORPHANS_RE.search(line):
            found.append(f"{subject}: {match.group(1)} orphan node(s)")
    return found


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


def main(paths: list[str] | None = None, run_import: bool = True) -> int:
    say("test")
    ensure_out()
    tests_dir = ROOT / "tests"
    if not tests_dir.is_dir():
        raise Failure("no tests/ directory")
    if run_import:
        # The class cache must be current, or new class_name suites fail to resolve.
        from .check import run_import as do_import

        for line in do_import("test-import"):
            bad(f"import: {line} (run `check` for details)")
    shutil.rmtree(REPORT_DIR, ignore_errors=True)
    res = godot(_args(paths, tests_dir), timeout=TIMEOUT, log="test")
    if res.timed_out:
        raise Failure(f"tests timed out after {TIMEOUT}s (log: tools/out/logs/test.log)")
    failed = _judge(res.rc, res.out, _reports(), "tools/out/logs/test.log")
    say("test: FAILED" if failed else "test: passed")
    return 1 if failed else 0


def _args(paths: list[str] | None, tests_dir: Path) -> list[str]:
    selectors: list[str] = []
    for item in paths or default_suites(tests_dir):
        selectors += ["-a", item if item.startswith("res://") else "res://" + item.replace("\\", "/")]
    return [
        "--headless",
        "-s",
        "res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
        "--ignoreHeadlessMode",
        "-c",
        *selectors,
        "-rd",
        "res://tools/out/gdunit",
        "-rc",
        "1",
    ]


def _reports() -> list[Path]:
    return sorted(REPORT_DIR.glob("report_*/results.xml"))


def _judge(rc: int, out: str, reports: list[Path], log: str) -> bool:
    """Print what went wrong in one GdUnit4 run; True when it failed."""
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
    another; a test missing from a run (the run crashed or timed out) counts neither way."""
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
        seen = [(o.run, o.cases[key]) for o in outcomes if key in o.cases]
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


def repeat(runs: int, paths: list[str] | None = None, run_import: bool = True) -> int:
    """`test --repeat N`: N runs one after another; any failed run fails it. Each run's report goes to
    tools/out/gdunit-runs/run-<i>/ and its log to tools/out/logs/test-run<i>.log; summary.json and summary.md compare
    them."""
    if runs < 1:
        raise Failure("--repeat must be at least 1")
    say(f"test --repeat {runs}")
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
    args = _args(paths, tests_dir)
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
