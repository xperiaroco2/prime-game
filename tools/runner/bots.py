"""`bots`: the bot scenarios through the network layers, and the information-leak test (docs/ARCHITECTURE.md §4.6).

`bots [scenario ...]` plays every scenario in content/scenarios/ (or those named) in one headless process over the
loopback, on a simulated clock; `bots <scenario> --instances N` plays one over ENet on 127.0.0.1 on a free port, one
process per bot, on the real clock (E12); with `--transport webrtc` over WebRTC instead (M6-6: the host serves
LanSignalling on that port, free for TCP too; the fault shim is on, and the leak test adds its order check). Both run
tests/harness/bots/bots_main.gd through `run`, so a failed
scenario, a non-zero exit, a timeout or an engine error line fails the command. Each run starts with an empty
tools/out/bots/<scenario>/, where the bots write their view files (and, over ENet, their peer ids) and a failed
scenario its command log.

`bots --chaos [--seed N] [--runs K] [--long] [--enet | --transport T]` runs the chaos bots (docs/ARCHITECTURE.md §4.6
"Chaos"): tests/harness/chaos/chaos_main.gd, a hostile and a malformed peer against the host beside honest bots, one
process over the loopback on the simulated clock (with `--enet` or `--transport enet`, over ENet on 127.0.0.1 on a free
port; with `--transport webrtc`, over WebRTC there, paced to the real clock, the fault shim on). Without `--seed` the
seed is random and printed first, so a night run that fails names the seed that replays it. The runner kills a run
after 60 s per seed over the loopback, 120 s over a network (#508: above the scenario's 90 s time limit).
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
# Over ENet or WebRTC the scenarios run on the real clock: their own length plus joining and the host's wait for the
# files.
ENET_SECONDS = 180
NAME_RE = re.compile(r"[a-z0-9_]+")
# `run` writes instance i's output to tools/out/logs/run/bots_main-<i>.log.
RUN_LOGS = LOGS / "run"
CHAOS_TARGET = "tests/harness/chaos/chaos_main.gd"
# Per seed over the loopback: three runs of about 2 s each (the long match about 3 s).
CHAOS_SECONDS_PER_SEED = 60
# Per seed over ENet or WebRTC: one run, over WebRTC paced to the real clock (about 16 s). Above ChaosScenario's 90 s
# time limit (with Godot's start and the report after it), so a seed that stalls fails with the scenario's reason, not
# at the kill with none (#508).
CHAOS_NETWORK_SECONDS_PER_SEED = 120
CHAOS_MAX_RUNS = 100
# The night job's random seed (printed before the run): positive, and far from int overflow when runs add to it.
CHAOS_SEEDS = range(1, 2**31)
# The network a run over sockets takes: ENet, or WebRTC with LanSignalling (M6-6).
TRANSPORTS = ("enet", "webrtc")


def user_args(
    scenarios: list[str], port: int | None = None, instances: int = 1, transport: str = "enet"
) -> list[str]:
    """The arguments after `--` that bots_main.gd reads: over the network `--port=<p> --instances=<n>` (and
    `--transport=webrtc`), then the names."""
    network = [f"--port={port}", f"--instances={instances}"] if port is not None else []
    if port is not None and transport != "enet":
        network.append(f"--transport={transport}")
    return network + scenarios


def check_args(scenarios: list[str], instances: int, transport: str = "enet") -> None:
    """Scenario names are file names in content/scenarios/; --instances N needs exactly one; a transport is a
    network's, and needs --instances."""
    for name in scenarios:
        if not NAME_RE.fullmatch(name.removesuffix(".tres")):
            raise Failure(f"{name}: give a scenario's file name in content/scenarios/, such as refusals")
    if instances < 1 or instances > launch.MAX_INSTANCES:
        raise Failure(f"--instances must be between 1 and {launch.MAX_INSTANCES}")
    if instances > 1 and len(scenarios) != 1:
        raise Failure("--instances runs exactly one scenario over the network, one instance per bot: name it")
    if transport not in TRANSPORTS:
        raise Failure(f"--transport is one of {', '.join(TRANSPORTS)}, not {transport}")
    if transport != "enet" and instances == 1:
        raise Failure(f"--transport {transport} plays one scenario, one process per bot: give --instances N")


def clear_out(scenarios: list[str]) -> None:
    """Old view files would pass for this run's (the ENet host waits for them): start each scenario empty."""
    if not scenarios:
        shutil.rmtree(BOTS_OUT, ignore_errors=True)
        return
    for name in scenarios:
        shutil.rmtree(BOTS_OUT / name.removesuffix(".tres"), ignore_errors=True)


def main(
    scenarios: list[str] | None = None, instances: int = 1, seconds: int | None = None, transport: str = "enet"
) -> int:
    say("bots")
    names = [name.removesuffix(".tres") for name in scenarios or []]
    check_args(names, instances, transport)
    clear_out(names)
    if instances == 1:
        return launch.main(TARGET, headless=True, seconds=seconds or ONE_PROCESS_SECONDS, user_args=user_args(names))
    from .verify import free_udp_port

    port = free_udp_port(tcp=transport == "webrtc")
    code = launch.main(
        TARGET,
        headless=True,
        seconds=seconds or ENET_SECONDS,
        instances=instances,
        user_args=user_args(names, port, instances, transport),
    )
    if code != 0:
        show_failures(instances)
    return code


def chaos_args(
    seed: int, runs: int = 1, long: bool = False, port: int | None = None, transport: str = "enet"
) -> list[str]:
    """The arguments after `--` that chaos_main.gd reads."""
    args = [f"--seed={seed}", f"--runs={runs}"]
    if long:
        args.append("--long")
    if port is not None:
        args.append(f"--port={port}")
        if transport != "enet":
            args.append(f"--transport={transport}")
    return args


def chaos_seconds_per_seed(transport: str | None) -> int:
    """The runner's kill per chaos seed: 60 s over the loopback (`transport` None), 120 s over a network."""
    return CHAOS_SECONDS_PER_SEED if transport is None else CHAOS_NETWORK_SECONDS_PER_SEED


def chaos(
    seed: int | None = None,
    runs: int = 1,
    long: bool = False,
    enet: bool = False,
    seconds: int | None = None,
    pick: random.Random | None = None,
    transport: str | None = None,
) -> int:
    """`bots --chaos`: the chaos bots for `runs` seeds from `seed` (random when None, printed first); over the
    loopback, or over `transport` (`enet` is `--enet`)."""
    say("bots --chaos")
    if runs < 1 or runs > CHAOS_MAX_RUNS:
        raise Failure(f"--runs must be between 1 and {CHAOS_MAX_RUNS}")
    if transport is not None and transport not in TRANSPORTS:
        raise Failure(f"--transport is one of {', '.join(TRANSPORTS)}, not {transport}")
    if enet and transport not in (None, "enet"):
        raise Failure("--enet is --transport enet: give one of them")
    if enet:
        transport = "enet"
    if seed is None:
        seed = (pick or random.Random()).choice(CHAOS_SEEDS)
        say(f"  chaos seed {seed} (random; replay: tools/run.sh bots --chaos --seed {seed})")
    port = None
    if transport is not None:
        from .verify import free_udp_port

        port = free_udp_port(tcp=transport == "webrtc")
    return launch.main(
        CHAOS_TARGET,
        headless=True,
        seconds=seconds or chaos_seconds_per_seed(transport) * runs,
        user_args=chaos_args(seed, runs, long, port, transport or "enet"),
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
