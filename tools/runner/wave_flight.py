"""`wave --in-flight` (#1355): the other sessions on this machine with work of their own still in flight.

The secretary sorts every session into "waits for you", "running" and "silent, reason unseen" (its skill). A session
that only ended its turn may be waiting on its own background work, whose notification will wake it: on 2026-10-28 the
inbox listed the art session "Анімації прибульців (art #196)" as silent while its builder, a background agent, dressed
the bodies. `--stalled` flags only runs that finished with no turn after them, and `wave --since --session` reads only
the main checkout's transcripts, so nothing told the two apart.

Read-only. It reads the same transcripts as `--stalled` (wave_stall: the track checkouts' folders and their worktrees'
written in the last RECENT_HOURS, never the caller's own, a session whose process is gone passed over) and the run
journals. In flight:
- a workflow run that wave.build_runs calls running (no notification, its journal short of its end) and no later
  launch replaced (a resume under a new run id, a fresh relaunch of its issue);
- a background agent or command: a call whose result says it was launched in the background (an Agent's
  `toolUseResult` with status `async_launched` and its `agentId`, a Bash call's with its `backgroundTaskId`) and no
  task notification of that task id or call came after it (a finished, failed or killed one sends one) and no
  TaskStop call stopped it (a stopped one sends none, only TaskStop's result: on 2026-10-27 the art session stopped
  three of its commands so).
Each session with any gets a line with what the Desktop app's `list_sessions` shows, its `local_...` id being no
transcript id: the title (the transcript's newest `custom-title`, the name in the sidebar), the cwd and the newest
record's time (close to `lastActivityAt`), then its checkout and transcript id, then each item: a run's wf id, workflow
and start, and its journal's newest write; an agent's id, description, start and its transcript's newest write; a
command's task id, command and start. A run or agent whose files have not moved for hours may have died with its
process. Exit 0 either way.
"""

from __future__ import annotations

import io
import json
import os
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from . import metrics, wave, wave_stall
from .common import say, warn

STOP_TOOLS = ("TaskStop", "KillShell")


@dataclass
class Task:
    """A background agent or command."""

    task_id: str
    tool_use_id: str
    kind: str  # "agent" or "command"
    what: str
    time: float
    last_write: float | None = None


@dataclass
class InFlight:
    session: wave.Session
    checkout: str
    runs: list[wave.Run]  # oldest launch first
    tasks: list[Task] = field(default_factory=list)  # oldest first
    alive: bool | None = True


def when(t: float | None) -> str:
    return metrics.iso(t)[:16].replace("T", " ") + "Z" if t is not None else "unknown"


def in_flight(s: wave.Session) -> list[wave.Run]:
    """The session's runs still running that no later launch replaced, oldest launch first."""
    if not s.launches:
        return []
    runs = [r for r in wave.build_runs(s) if not r.finished and not r.resumed_as and not r.relaunched_as]
    return sorted(runs, key=lambda r: r.launches[0].time)


def background(path: Path, sid: str) -> list[Task]:
    """The session's background agents and commands with no notification yet, oldest first; broken lines are passed
    over."""
    calls: dict[str, tuple[str, object, float]] = {}  # tool_use_id: (tool, input, time)
    tasks: dict[str, Task] = {}
    done: set[str] = set()  # task ids and tool_use ids a notification named
    with io.open(path, encoding="utf-8", errors="replace") as lines:
        for line in lines:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            t = metrics.stamp(d.get("timestamp"))
            kind = d.get("type")
            m = d.get("message") if isinstance(d.get("message"), dict) else {}
            if kind == "assistant" and t is not None:
                for b in m.get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("id"):
                        calls[str(b["id"])] = (str(b.get("name") or ""), b.get("input"), t)
            elif kind == "user":
                content = m.get("content")
                tur = d.get("toolUseResult")
                results = [b for b in content if isinstance(b, dict) and b.get("type") == "tool_result"] \
                    if isinstance(content, list) else []  # fmt: skip
                if isinstance(tur, dict) and len(results) == 1:
                    task = task_of(calls.get(str(results[0].get("tool_use_id"))), tur, str(results[0].get("tool_use_id")))
                    if task:
                        tasks[task.task_id] = task
                for b in results:
                    done |= stopped(calls.get(str(b.get("tool_use_id"))), b)
                for n in wave.notices_in(metrics.text_of(content), t or 0.0):
                    done |= {n.task_id, n.tool_use_id}
            elif kind == "queue-operation":
                for n in wave.notices_in(str(d.get("content") or ""), t or 0.0):
                    done |= {n.task_id, n.tool_use_id}
    left = [x for x in tasks.values() if x.task_id not in done and x.tool_use_id not in done]
    for x in left:
        if x.kind == "agent":
            x.last_write = mtime(path.parent / sid / "subagents" / f"agent-{x.task_id}.jsonl")
    return sorted(left, key=lambda x: x.time)


def task_of(call: tuple[str, object, float] | None, tur: dict, tool_use_id: str) -> Task | None:
    """The background task a call's result launched, or None (a Workflow's run is read by wave.build_runs)."""
    if call is None or call[0] == "Workflow":
        return None
    tool, inp, t = call
    given = inp if isinstance(inp, dict) else {}
    if tur.get("status") == "async_launched" and tur.get("agentId"):
        what = str(given.get("description") or tur.get("description") or tool)
        return Task(str(tur["agentId"]), tool_use_id, "agent", " ".join(what.split()), t)
    if tur.get("backgroundTaskId"):
        return Task(str(tur["backgroundTaskId"]), tool_use_id, "command", wave_stall.what_of(inp), t)
    return None


def stopped(call: tuple[str, object, float] | None, result: dict) -> set[str]:
    """The task a stop call stopped: TaskStop's (or the older KillShell's) id when its result is no error. A stopped
    task sends no notification."""
    if call is None or call[0] not in STOP_TOOLS or result.get("is_error"):
        return set()
    given = call[1] if isinstance(call[1], dict) else {}
    return {str(given[k]) for k in ("task_id", "shell_id") if given.get(k)}


def mtime(path: Path) -> float | None:
    try:
        return path.stat().st_mtime
    except OSError:
        return None


def written(started: float, last: float | None, what: str) -> str:
    if last is None:
        return f", no {what} yet"
    same_day = metrics.iso(last)[:10] == metrics.iso(started)[:10]
    return f", its {what} last written {wave_stall.hhmm(last) if same_day else when(last)}"


def run_part(r: wave.Run) -> str:
    what = r.name + (f" #{r.issue}" if r.issue is not None else "")
    started = r.launches[-1].time
    return f"{r.run_id} ({what}) started {when(started)}" + written(started, r.last_write, "journal")


def task_part(x: Task) -> str:
    if x.kind == "agent":
        return f"agent {x.task_id} '{x.what}' started {when(x.time)}" + written(x.time, x.last_write, "transcript")
    return f"command {x.task_id} `{x.what}` started {when(x.time)}"


def line_of(f: InFlight) -> str:
    s = f.session
    who = f"'{s.title}'" if s.title else "(no title)"
    where = f"checkout {f.checkout}, cwd {s.cwd or 'unknown'}, last record {when(s.last)}, transcript {s.sid}"
    line = f"in flight: {who} ({where}): " + "; ".join([*map(run_part, f.runs), *map(task_part, f.tasks)])
    if f.alive is None:
        line += "; whether its process lives is unknown"
    return line


def count(n: int, word: str) -> str:
    return f"{n} {word}{'s' if n != 1 else ''}"


def main(*, now: float | None = None, alive: Callable[[str], bool | None] | None = None) -> int:
    now = time.time() if now is None else now
    checkouts = metrics.track_checkouts(metrics.main_checkout())
    owner = {d: c["checkout"] for c in checkouts for d in c["folders"]}
    check = alive or wave_stall.liveness()
    me = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    found = wave_stall.recent_transcripts(list(owner), now)
    listed: list[InFlight] = []
    for path, sid in found:
        if sid == me:
            continue
        lives = check(sid)
        if lives is False:
            continue
        try:
            s = wave.read_session(path, sid)
            tasks = background(path, sid)
        except OSError as exc:
            warn(f"wave: {path}: cannot read it ({exc.strerror or exc})")
            continue
        runs = in_flight(s)
        if runs or tasks:
            listed.append(InFlight(s, owner.get(path.parent, path.parent.name), runs, tasks, lives))
    listed.sort(key=lambda f: f.session.last or 0.0, reverse=True)
    for f in listed:
        say(line_of(f))
    agents = sum(x.kind == "agent" for f in listed for x in f.tasks)
    kinds = (f" ({count(sum(len(f.runs) for f in listed), 'workflow run')}, {count(agents, 'agent')}, "
             f"{count(sum(len(f.tasks) for f in listed) - agents, 'command')})" if listed else "")  # fmt: skip
    say(f"wave: {count(len(listed), 'session')} with work in flight{kinds} of "
        f"{count(len(found), 'session transcript')} written in the last {wave_stall.RECENT_HOURS} h; a session with "
        "no line has none. Match a line to list_sessions by its title, else by its cwd and last record "
        "(lastActivityAt).")  # fmt: skip
    return 0
