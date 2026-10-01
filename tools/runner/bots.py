"""`bots`: the bot scenarios through the network layers, and the information-leak test (docs/ARCHITECTURE.md §4.6).

`bots [scenario ...]` plays every scenario in content/scenarios/ (or those named) in one headless process over the
loopback, on a simulated clock; `bots <scenario> --instances N` plays one over ENet on 127.0.0.1 on a free port, one
process per bot, on the real clock (E12). Both run tests/harness/bots/bots_main.gd through `run`, so a failed
scenario, a non-zero exit, a timeout or an engine error line fails the command. Each run starts with an empty
tools/out/bots/<scenario>/, where the bots write their view files (and, over ENet, their peer ids) and a failed
scenario its command log.
"""

from __future__ import annotations

import re
import shutil

from . import launch
from .common import OUT, Failure, say

TARGET = "tests/harness/bots/bots_main.gd"
BOTS_OUT = OUT / "bots"
# Every scenario in one process: about 8 s on the engineer's machine (#102); the timeout leaves room for slow CI.
ONE_PROCESS_SECONDS = 300
# Over ENet the scenarios run on the real clock: their own length plus joining and the host's wait for the files.
ENET_SECONDS = 180
NAME_RE = re.compile(r"[a-z0-9_]+")


def user_args(scenarios: list[str], port: int | None = None, instances: int = 1) -> list[str]:
    """The arguments after `--` that bots_main.gd reads: over ENet `--port=<p> --instances=<n>`, then the names."""
    enet = [f"--port={port}", f"--instances={instances}"] if port is not None else []
    return enet + scenarios


def check_args(scenarios: list[str], instances: int) -> None:
    """Scenario names are file names in content/scenarios/; --instances N needs exactly one."""
    for name in scenarios:
        if not NAME_RE.fullmatch(name.removesuffix(".tres")):
            raise Failure(f"{name}: give a scenario's file name in content/scenarios/, such as refusals")
    if instances < 1 or instances > launch.MAX_INSTANCES:
        raise Failure(f"--instances must be between 1 and {launch.MAX_INSTANCES}")
    if instances > 1 and len(scenarios) != 1:
        raise Failure("--instances runs exactly one scenario over ENet, one instance per bot: name it")


def clear_out(scenarios: list[str]) -> None:
    """Old view files would pass for this run's (the ENet host waits for them): start each scenario empty."""
    if not scenarios:
        shutil.rmtree(BOTS_OUT, ignore_errors=True)
        return
    for name in scenarios:
        shutil.rmtree(BOTS_OUT / name.removesuffix(".tres"), ignore_errors=True)


def main(scenarios: list[str] | None = None, instances: int = 1, seconds: int | None = None) -> int:
    say("bots")
    names = [name.removesuffix(".tres") for name in scenarios or []]
    check_args(names, instances)
    clear_out(names)
    if instances == 1:
        return launch.main(TARGET, headless=True, seconds=seconds or ONE_PROCESS_SECONDS, user_args=user_args(names))
    from .verify import free_udp_port

    port = free_udp_port()
    return launch.main(
        TARGET,
        headless=True,
        seconds=seconds or ENET_SECONDS,
        instances=instances,
        user_args=user_args(names, port, instances),
    )
