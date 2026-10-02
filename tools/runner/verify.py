"""`verify` (definition of done: exactly what CI runs, in the same order) and `selftest`."""

from __future__ import annotations

import random
import socket
import time
import unittest
from collections.abc import Callable

from . import bots, check, doctor, gdunit, hostjoin, launch, lint
from .common import ROOT, Failure, bad, git_status, ok, say

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

# Below the ephemeral ranges of Windows (49152+) and Linux (32768+): an ENet client's own socket never takes it.
ENET_PORTS = range(20000, 32000)
PORT_TRIES = 50


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
        ("freeze", freeze),
        ("stall", stall),
        ("bots", bots_one_process),
        ("bots-enet", bots_enet),
        ("game", game),
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
