"""`test`: GdUnit4 headless, judged by exit code and the JUnit XML (never the console summary)."""

from __future__ import annotations

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
    selectors: list[str] = []
    for item in paths or default_suites(tests_dir):
        selectors += ["-a", item if item.startswith("res://") else "res://" + item.replace("\\", "/")]
    args = [
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
    res = godot(args, timeout=TIMEOUT, log="test")
    if res.timed_out:
        raise Failure(f"tests timed out after {TIMEOUT}s (log: tools/out/logs/test.log)")
    reports = sorted(REPORT_DIR.glob("report_*/results.xml"))
    junit = parse_junit(reports[-1]) if reports else None

    failed = res.rc != 0
    if res.rc not in EXIT_MEANING:
        bad(f"GdUnit4 crashed or exited unexpectedly (exit {res.rc}); log: tools/out/logs/test.log")
    elif res.rc != 0:
        bad(f"exit {res.rc}: {EXIT_MEANING[res.rc]}")
    if res.rc == 101:
        leaks = parse_orphans(res.out)
        for line in leaks:
            bad(line)
        if not leaks:
            bad("could not tell which test leaked; log: tools/out/logs/test.log")
    if junit is None:
        failed = True
        bad("no results.xml written; log: tools/out/logs/test.log")
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
    say("test: FAILED" if failed else "test: passed")
    return 1 if failed else 0
