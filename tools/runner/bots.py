"""`bots`: the bot scenarios through the network layers, and the information-leak test (docs/ARCHITECTURE.md §4.6).

`bots [scenario ...]` plays every scenario in content/scenarios/ (or those named) in one headless process over the
loopback, on a simulated clock; `bots <scenario> --instances N` plays one over ENet on 127.0.0.1 on a free port, one
process per bot, on the real clock (E12). Both run tests/harness/bots/bots_main.gd through `run`, so a failed
scenario, a non-zero exit, a timeout or an engine error line fails the command. Each run starts with an empty
tools/out/bots/<scenario>/, where the bots write their view files (and, over ENet, their peer ids) and a failed
scenario its command log.

`bots --chaos [--seed N] [--runs K] [--long] [--enet]` runs the chaos bots (docs/ARCHITECTURE.md §4.6 "Chaos"):
tests/harness/chaos/chaos_main.gd, a hostile and a malformed peer against the host beside honest bots, one process
over the loopback on the simulated clock (with `--enet`, over ENet on 127.0.0.1 on a free port). Without `--seed` the
seed is random and printed first, so a night run that fails names the seed that replays it.
"""

from __future__ import annotations

import random
import re
import shutil

from pathlib import Path

from . import launch
from .common import LOGS, OUT, Failure, say

TARGET = "tests/harness/bots/bots_main.gd"
BOTS_OUT = OUT / "bots"
# Every scenario in one process: about 8 s on the engineer's machine (#102); the timeout leaves room for slow CI.
ONE_PROCESS_SECONDS = 300
# Over ENet the scenarios run on the real clock: their own length plus joining and the host's wait for the files.
ENET_SECONDS = 180
NAME_RE = re.compile(r"[a-z0-9_]+")
# `run` writes instance i's output to tools/out/logs/run/bots_main-<i>.log.
RUN_LOGS = LOGS / "run"
CHAOS_TARGET = "tests/harness/chaos/chaos_main.gd"
# Per seed: three loopback runs of about 2 s each (the long match about 3 s), or one run over ENet.
CHAOS_SECONDS_PER_SEED = 60
CHAOS_MAX_RUNS = 100
# The night job's random seed (printed before the run): positive, and far from int overflow when runs add to it.
CHAOS_SEEDS = range(1, 2**31)


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
    code = launch.main(
        TARGET,
        headless=True,
        seconds=seconds or ENET_SECONDS,
        instances=instances,
        user_args=user_args(names, port, instances),
    )
    if code != 0:
        show_failures(instances)
    return code


def chaos_args(seed: int, runs: int = 1, long: bool = False, port: int | None = None) -> list[str]:
    """The arguments after `--` that chaos_main.gd reads."""
    args = [f"--seed={seed}", f"--runs={runs}"]
    if long:
        args.append("--long")
    if port is not None:
        args.append(f"--port={port}")
    return args


def chaos(
    seed: int | None = None,
    runs: int = 1,
    long: bool = False,
    enet: bool = False,
    seconds: int | None = None,
    pick: random.Random | None = None,
) -> int:
    """`bots --chaos`: the chaos bots for `runs` seeds from `seed` (random when None, printed first)."""
    say("bots --chaos")
    if runs < 1 or runs > CHAOS_MAX_RUNS:
        raise Failure(f"--runs must be between 1 and {CHAOS_MAX_RUNS}")
    if seed is None:
        seed = (pick or random.Random()).choice(CHAOS_SEEDS)
        say(f"  chaos seed {seed} (random; replay: tools/run.sh bots --chaos --seed {seed})")
    port = None
    if enet:
        from .verify import free_udp_port

        port = free_udp_port()
    return launch.main(
        CHAOS_TARGET,
        headless=True,
        seconds=seconds or CHAOS_SECONDS_PER_SEED * runs,
        user_args=chaos_args(seed, runs, long, port),
    )


def failure_block(log: Path) -> list[str]:
    """A scenario's `BOTS ...: FAILED` line and the indented lines under it (bots_main.gd's report), or []."""
    try:
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    block: list[str] = []
    for line in lines:
        if line.startswith("BOTS ") and "FAILED" in line:
            block = [line]
        elif block and line.startswith("  "):
            block.append(line)
        elif block:
            break
    return block


def show_failures(instances: int) -> None:
    """Over ENet `run` echoes only engine error lines: print each instance's failure report from its log."""
    for number in range(1, instances + 1):
        for line in failure_block(RUN_LOGS / f"{Path(TARGET).stem}-{number}.log"):
            say(f"  #{number} {line}")
