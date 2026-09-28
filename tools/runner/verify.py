"""`verify` (definition of done: exactly what CI runs, in the same order) and `selftest`."""

from __future__ import annotations

import time
import unittest
from collections.abc import Callable

from . import check, doctor, gdunit, lint
from .common import ROOT, Failure, bad, git_status, ok, say


def selftest() -> int:
    """Unit tests of the runner itself (stdlib unittest, tools/runner/tests)."""
    say("selftest")
    suite = unittest.defaultTestLoader.discover(
        str(ROOT / "tools" / "runner" / "tests"), top_level_dir=str(ROOT / "tools")
    )
    result = unittest.TextTestRunner(verbosity=0, stream=_Quiet()).run(suite)
    for test, trace in result.failures + result.errors:
        bad(f"{test.id()}: {trace.strip().splitlines()[-1]}")
    if result.wasSuccessful() and result.testsRun > 0:
        ok(f"{result.testsRun} runner tests passed")
        say("selftest: passed")
        return 0
    if result.testsRun == 0:
        bad("no runner tests found")
    say("selftest: FAILED")
    return 1


class _Quiet:
    def write(self, _text: str) -> None:
        pass

    def flush(self) -> None:
        pass


def main() -> int:
    started = time.monotonic()
    before = git_status()
    steps: list[tuple[str, Callable[[], int]]] = [
        ("doctor", lambda: doctor.main(quick=True)),
        ("lint", lambda: lint.main()),
        ("check", lambda: check.main()),
        ("test", lambda: gdunit.main(run_import=False)),
        ("selftest", selftest),
    ]
    results: list[tuple[str, str, float]] = []
    for name, step in steps:
        t0 = time.monotonic()
        try:
            rc = step()
        except Failure as exc:
            bad(str(exc))
            rc = 1
        results.append((name, "passed" if rc == 0 else "FAILED", time.monotonic() - t0))
        say()
        if rc != 0 and name == "doctor":
            break  # a wrong environment makes every later step meaningless
    leftovers = sorted(git_status() - before)
    if leftovers:
        bad("verify left new or changed files in the working tree:", "\n".join(leftovers))
        results.append(("clean tree", "FAILED", 0.0))
    say("verify summary")
    for name, status, seconds in results:
        say(f"  {status:<7} {name:<10} {seconds:6.1f}s")
    failed = any(status != "passed" for _, status, _ in results) or len(results) < len(steps)
    say(f"verify: {'FAILED' if failed else 'passed'} in {time.monotonic() - started:.1f}s")
    return 1 if failed else 0
