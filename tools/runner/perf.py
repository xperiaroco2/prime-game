"""`perf`: the host's cost with 10 bots: tick time, snapshot sizes, bytes per peer (docs/ARCHITECTURE.md §9.7, #187).

`perf [--bots N] [--seconds S] [--enet] [--baseline FILE]` plays one match of tests/harness/perf/ (PerfScenario: N
bots ready up, walk across the greybox and the round ends by time up after S seconds; seeded, so the same match every
run) through the host session, headless, and measures it from the harness side. Over the loopback (the default) one
process steps a simulated clock at `--fixed-fps 60`, as fast as the machine runs; `--enet` uses real sockets on
127.0.0.1 and the real clock, the host and every bot still in one process. Godot writes the raw samples to
tools/out/perf/raw/<transport>.json; this module summarises them into tools/out/perf/<date>.json (UTC; `-enet` added
over ENet, `-<N>b<S>s` for other than 10 bots and a 60 s round) and summary.md, and compares them with a baseline: a run
fails only when the match fails, never on a change. Not a `verify` step; the nightly workflow runs it (docs/AGENT_WORKFLOW.md §15).

Each metric is p50/p95/max (nearest rank) over its samples: the host step's time (Time.get_ticks_usec around
HostSession.step, the steps that ran a host tick), Performance's TIME_PHYSICS_PROCESS once a second (the engine's
longest physics frame of each second of real time, the whole process: host and bots), the events per host tick,
each Snapshot's payload bytes per remote peer per tick, and per remote peer per second of host time: frame bytes sent
(all, snapshots, voice) and what it sent (payload bytes that are not voice, voice frames). MEMORY_STATIC: at the end
and the most seen. Peer 1, the host's own client, is not counted.
"""

from __future__ import annotations

import json
import math
import re
from datetime import datetime, timezone
from pathlib import Path

from . import launch
from .common import OUT, ROOT, Failure, git, rel, say

TARGET = "tests/harness/perf/perf_main.gd"
PERF_OUT = OUT / "perf"
RAW_DIR = PERF_OUT / "raw"
BASELINE = PERF_OUT / "baseline.json"
SUMMARY = PERF_OUT / "summary.md"
DEFAULT_BOTS = 10
# The base mode's max_players; PerfScenario needs two bots to cross.
MIN_BOTS, MAX_BOTS = 2, 10
DEFAULT_SECONDS = 60
MIN_SECONDS, MAX_SECONDS = 20, 600
FIXED_FPS = "60"
# The countdown, the loading and the run's own margin on top of the round: a hard timeout, far above a normal run.
TIMEOUT_MARGIN_SECONDS = 240
# A change of a metric beyond this share of its baseline value is reported: a placeholder, not a decision.
THRESHOLD = 0.20
VERSION = 1
STATS = ("p50", "p95", "max")


def check_args(bots: int, seconds: int) -> None:
    if not MIN_BOTS <= bots <= MAX_BOTS:
        raise Failure(f"--bots must be between {MIN_BOTS} and {MAX_BOTS} (the base mode's players)")
    if not MIN_SECONDS <= seconds <= MAX_SECONDS:
        raise Failure(f"--seconds (the round) must be between {MIN_SECONDS} and {MAX_SECONDS}")


def user_args(bots: int, seconds: int, out: Path, port: int | None = None) -> list[str]:
    """The arguments after `--` that perf_main.gd reads."""
    args = [f"--bots={bots}", f"--seconds={seconds}", f"--out={out.as_posix()}"]
    return args + (["--enet", f"--port={port}"] if port is not None else [])


def percentile(values: list[float], share: float) -> float:
    """Nearest rank: the smallest sample with at least `share` of the samples at or below it; 0 without samples."""
    if not values:
        return 0
    ordered = sorted(values)
    return ordered[max(0, math.ceil(share * len(ordered)) - 1)]


def stats(values: list[float]) -> dict[str, float]:
    return {"p50": percentile(values, 0.50), "p95": percentile(values, 0.95), "max": max(values, default=0)}


def per_second(by_tick: dict[str, int], rate: int, extra: int = 0) -> list[int]:
    """One peer's totals per second of host time, from its first second with traffic to its last, gaps as 0.

    `extra` is added per entry (a frame header on payload sizes)."""
    totals: dict[int, int] = {}
    for tick, amount in by_tick.items():
        second = int(tick) // rate
        totals[second] = totals.get(second, 0) + amount + extra
    if not totals:
        return []
    return [totals.get(second, 0) for second in range(min(totals), max(totals) + 1)]


def per_peer_seconds(table: dict[str, dict[str, int]], rate: int, extra: int = 0) -> list[int]:
    return [value for by_tick in table.values() for value in per_second(by_tick, rate, extra)]


def summarize(raw: dict, *, date: str, commit: str) -> dict:
    """The report of one run from perf_main.gd's raw samples."""
    rate = raw["ticks_per_second"]
    header = raw["budgets"]["frame_header_bytes"]
    snapshot_sizes = [size for by_tick in raw["snapshots"].values() for size in by_tick.values()]
    events = raw["events_per_tick"]
    up = per_peer_seconds(raw["up"], rate)
    voice_frames = per_peer_seconds(raw["up_voice_frames"], rate)
    metrics = {
        "host_tick_usec": stats(raw["tick_usec"]),
        "physics_process_usec": stats(raw["physics_usec"]),
        "events_per_tick": {**stats(events), "mean": round(sum(events) / len(events), 2) if events else 0},
        "snapshot_payload_bytes": stats(snapshot_sizes),
        "down_bytes_per_second": stats(per_peer_seconds(raw["down"], rate)),
        "down_snapshot_bytes_per_second": stats(per_peer_seconds(raw["snapshots"], rate, header)),
        "down_voice_bytes_per_second": stats(per_peer_seconds(raw["down_voice"], rate)),
        "up_bytes_per_second": stats(up),
        "up_voice_frames_per_second": stats(voice_frames),
        "memory_static_bytes": dict(raw["memory_static"]),
    }
    budgets = raw["budgets"]
    return {
        "version": VERSION,
        "date": date,
        "commit": commit,
        "transport": raw["transport"],
        "bots": raw["bots"],
        "seconds": raw["seconds"],
        "seed": raw["seed"],
        "frames": raw["frames"],
        "host_ticks": raw["host_ticks"],
        "remote_peers": len(raw["down"]),
        "metrics": metrics,
        "budgets": {
            "snapshot_payload": headroom(metrics["snapshot_payload_bytes"]["max"], budgets["snapshot_payload_cap"]),
            "up_bytes_per_second": headroom(metrics["up_bytes_per_second"]["max"], budgets["peer_bytes_per_second"]),
            "up_voice_frames_per_second": headroom(
                metrics["up_voice_frames_per_second"]["max"], budgets["peer_voice_frames_per_second"]
            ),
            "voice_down_payload_cap": budgets["voice_down_payload_cap"],
        },
    }


def headroom(peak: float, limit: float) -> dict[str, float]:
    return {"max": peak, "limit": limit, "headroom": round(1 - peak / limit, 3) if limit else 0}


def flatten(metrics: dict) -> dict[str, float]:
    return {f"{name}.{stat}": value for name, values in metrics.items() for stat, value in values.items()}


def compare(report: dict, baseline: dict | None, threshold: float = THRESHOLD, name: str = "") -> dict:
    """The metrics that moved by more than `threshold` of their baseline value, both ways; never a failure."""
    result: dict = {"baseline": name, "threshold": threshold, "changes": []}
    if baseline is None:
        result["note"] = "no baseline: nothing compared"
        return result
    setup = ("transport", "bots", "seconds", "seed")
    differs = [key for key in setup if baseline.get(key) != report.get(key)]
    if differs or baseline.get("version") != report.get("version"):
        result["note"] = "a different run (" + ", ".join(differs or ["version"]) + "): nothing compared"
        return result
    old = flatten(baseline.get("metrics", {}))
    for key, new in flatten(report["metrics"]).items():
        if key not in old:
            continue
        before = old[key]
        if before == new:
            continue
        change = None if before == 0 else (new - before) / before
        if change is None or abs(change) > threshold:
            result["changes"].append(
                {"metric": key, "baseline": before, "now": new, "change": None if change is None else round(change, 3)}
            )
    return result


def report_name(date: str, transport: str, bots: int = DEFAULT_BOTS, seconds: int = DEFAULT_SECONDS) -> str:
    """<date>.json for the default run over the loopback; `-enet` and `-<N>b<S>s` keep other runs from replacing it."""
    name = date if transport == "loopback" else f"{date}-{transport}"
    if (bots, seconds) != (DEFAULT_BOTS, DEFAULT_SECONDS):
        name += f"-{bots}b{seconds}s"
    return f"{name}.json"


def find_baseline(
    explicit: Path | None,
    transport: str,
    folder: Path | None = None,
    bots: int = DEFAULT_BOTS,
    seconds: int = DEFAULT_SECONDS,
) -> Path | None:
    """--baseline FILE; else tools/out/perf/baseline.json; else the newest earlier report of the same run setup.

    Called before this run's report is written, so a second run on a day compares with the first."""
    if explicit is not None:
        if not explicit.is_file():
            raise Failure(f"--baseline {explicit}: no such file")
        return explicit
    folder = folder or PERF_OUT
    if (folder / BASELINE.name).is_file():
        return folder / BASELINE.name
    reports = [path for path in folder.glob("*.json") if is_report_of(path, transport, bots, seconds)]
    return max(reports, key=lambda path: path.name, default=None)


def is_report_of(path: Path, transport: str, bots: int = DEFAULT_BOTS, seconds: int = DEFAULT_SECONDS) -> bool:
    suffix = report_name("", transport, bots, seconds)
    return re.fullmatch(r"\d{4}-\d{2}-\d{2}" + re.escape(suffix), path.name) is not None


def shown(path: Path) -> str:
    return rel(path) if path.is_relative_to(ROOT) else str(path)


def read_json(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def lines(report: dict) -> list[str]:
    """The summary printed and written to summary.md."""
    m = report["metrics"]
    b = report["budgets"]

    def row(name: str, unit: str) -> str:
        values = m[name]
        return f"{name}: " + ", ".join(f"{stat} {values[stat]}" for stat in STATS) + f" {unit}"

    snap, up, voice = b["snapshot_payload"], b["up_bytes_per_second"], b["up_voice_frames_per_second"]
    out = [
        f"perf {report['date']} {report['commit'][:10]}: {report['bots']} bots over {report['transport']}, "
        f"a {report['seconds']} s round, seed {report['seed']}; {report['host_ticks']} host ticks, "
        f"{report['remote_peers']} remote peers",
        row("host_tick_usec", "us (the host step, ticks only)"),
        row("physics_process_usec", "us (TIME_PHYSICS_PROCESS: the longest physics frame of each second, host and bots)"),
        row("events_per_tick", f"(mean {m['events_per_tick']['mean']})"),
        row("snapshot_payload_bytes", f"B per peer per tick; cap {snap['limit']} B (§4.3: unreliable payloads, so "
            f"ENet never fragments; WireBudget, E16), headroom {snap['headroom']:.0%}"),  # fmt: skip
        row("down_bytes_per_second", "B/s per peer (frame bytes: payload + 3-byte header; no ENet or UDP overhead)"),
        row("down_snapshot_bytes_per_second", "B/s per peer"),
        row("down_voice_bytes_per_second", "B/s per peer (synthetic frames: one per client tick, a few bytes; "
            f"VoiceDown cap {b['voice_down_payload_cap']} B with E11's 4-byte tick)"),  # fmt: skip
        row("up_bytes_per_second", f"B/s per peer, not voice; E7 budget {up['limit']:g} B/s, headroom "
            f"{up['headroom']:.0%}"),  # fmt: skip
        row("up_voice_frames_per_second", f"per peer; E7 budget {voice['limit']:g}/s, headroom {voice['headroom']:.0%}"),
        f"memory_static_bytes: end {m['memory_static_bytes']['end']}, max {m['memory_static_bytes']['max']} (MEMORY_STATIC,"
        " the whole process: the bots' clients keep every message they decoded)",
    ]
    comparison = report.get("comparison", {})
    if comparison.get("note"):
        out.append(f"compared: {comparison['note']}")
    else:
        changes = comparison.get("changes", [])
        out.append(
            f"compared with {comparison.get('baseline')}: {len(changes)} change(s) beyond "
            f"{comparison.get('threshold', THRESHOLD):.0%} (a placeholder, not a decision; never a failure)"
        )
        for change in changes:
            moved = "from 0" if change["change"] is None else f"{change['change']:+.0%}"
            out.append(f"  {change['metric']}: {change['baseline']} -> {change['now']} ({moved})")
    return out


def run_godot(bots: int, seconds: int, enet: bool, raw: Path) -> int:
    port = None
    if enet:
        from .verify import free_udp_port

        port = free_udp_port()
    return launch.main(
        TARGET,
        headless=True,
        seconds=seconds + TIMEOUT_MARGIN_SECONDS,
        user_args=user_args(bots, seconds, raw, port),
        engine_args=None if enet else ["--fixed-fps", FIXED_FPS],
    )


def today() -> str:
    """The report's UTC date; one place, so a test can fix it."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def main(
    bots: int = DEFAULT_BOTS, seconds: int = DEFAULT_SECONDS, enet: bool = False, baseline: str | None = None
) -> int:
    say("perf")
    check_args(bots, seconds)
    transport = "enet" if enet else "loopback"
    raw_path = RAW_DIR / f"{transport}.json"
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    # An old file would pass for this run's.
    raw_path.unlink(missing_ok=True)
    code = run_godot(bots, seconds, enet, raw_path)
    raw = read_json(raw_path)
    if code != 0 or raw is None:
        say(f"perf: FAILED (the run{'' if raw is not None else ' wrote no ' + rel(raw_path)}; nothing compared)")
        return 1
    date = today()
    head = git("rev-parse", "HEAD")
    report = summarize(raw, date=date, commit=head.out.strip() if head.rc == 0 else "")
    base_path = find_baseline(Path(baseline).resolve() if baseline else None, transport, None, bots, seconds)
    base = read_json(base_path) if base_path else None
    report["comparison"] = compare(report, base, THRESHOLD, shown(base_path) if base_path else "")
    out = PERF_OUT / report_name(date, transport, bots, seconds)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    text = lines(report)
    SUMMARY.write_text("\n".join(["# perf", "", "```", *text, "```", ""]), encoding="utf-8")
    for line in text:
        say(f"  {line}")
    say(f"perf: passed, report {rel(out)}")
    return 0
