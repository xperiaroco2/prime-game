"""`verify` (definition of done: exactly what CI runs, in the same order) and `selftest`."""

from __future__ import annotations

import random
import socket
import time
import unittest
from collections.abc import Callable

from . import check, doctor, gdunit, launch, lint
from .common import ROOT, Failure, bad, git_status, ok, say

# The headless ENet run (#40): a host with its own client and two clients, one process each, on 127.0.0.1 only.
ENET_RUN = "tests/integration/net/enet_host_and_two_clients.gd"
ENET_INSTANCES = 3
ENET_SECONDS = 90
# Below the ephemeral ranges of Windows (49152+) and Linux (32768+): an ENet client's own socket never takes it.
ENET_PORTS = range(20000, 32000)
PORT_TRIES = 50


def free_udp_port(pick: Callable[[range], int] = random.choice) -> int:
    """A random UDP port on 127.0.0.1 that nothing holds right now, so worktrees verifying at once rarely share one.

    A port that fails to bind (in use, or in a range Windows reserves) is skipped. The probe socket closes before
    Godot binds the port, so two worktrees can still pick the same one in that window (about 1 in 12,000); the host
    then fails with "host on 127.0.0.1:<port> failed", and running `verify` again picks a new port.
    """
    for _ in range(PORT_TRIES):
        port = pick(ENET_PORTS)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                continue
        return port
    raise Failure(f"no free UDP port on 127.0.0.1 in {ENET_PORTS.start}-{ENET_PORTS.stop - 1} after {PORT_TRIES} tries")


def enet() -> int:
    """`run <ENET_RUN> --headless --instances 3 --seconds 90 -- --port=<free>`: any failed instance fails it."""
    port = free_udp_port()
    return launch.main(
        ENET_RUN, headless=True, seconds=ENET_SECONDS, instances=ENET_INSTANCES, user_args=[f"--port={port}"]
    )


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
        ("enet", enet),
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
