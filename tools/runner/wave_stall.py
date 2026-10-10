"""`wave --stalled` (#731): the sessions on this machine that stopped taking turns while their runs finished.

On 2026-10-09/10 the meta manager ran a guarded command (a branch delete outside a task branch) at 22:06Z. The
guard's `ask` became a permission card, and Claude Code held every task notification of that session in its queue
while the call waited: four finished runs and the keep-alive timer arrived together at 07:29Z, when the engineer
allowed the call. Nothing outside the session showed it. This command shows it to any other session (a manager at its
wake, the secretary) or to the engineer.

Read-only. It reads the session transcripts of the three track checkouts and their worktrees (metrics.track_checkouts)
written in the last RECENT_HOURS, never the caller's own (CLAUDE_CODE_SESSION_ID), and Claude Code's live-session
files (sessions.read_all). A session is flagged when its process is alive (or no session file exists to say) and:
- a workflow run of it finished more than STALL_MINUTES ago with no turn of its own after that (wave.build_runs: the
  run's notification, else the end of its journal), unless it was stopped or killed (NO_TURN_STATUSES); or
- a notification has waited in its queue, undelivered, for more than STALL_MINUTES, after its last turn (before it,
  only when the session waits on a permission card: the card's own turn may have been busy when the notification came).
A turn is an assistant record. A queued notification is an `enqueue` queue-operation record with a
<task-notification> that no later `remove`, `dequeue` (the queue's head) or user record carrying its task id took
out; `queued_command` attachments only repeat an enqueue and do not deliver it. Each flagged line names what the
session waits on: of its tool calls with no result made since its newest tool result, the newest one a PreToolUse hook
answered `ask` for (a permission card; the line quotes the guard's reason), else the newest one. A session that took a
turn in the last STALL_MINUTES is not read further.
Exit 0 when nothing is flagged, STALLED_EXIT when a session is.
"""

from __future__ import annotations

import io
import json
import os
import re
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from . import metrics, sessions, wave
from .common import Failure, say, warn

STALL_MINUTES = 30
RECENT_HOURS = 24
STALLED_EXIT = 3
WHAT_LIMIT = 120
TASK_ID = re.compile(r"<task-id>(.*?)</task-id>", re.S)
# A run someone stopped or killed (TaskStop, the app's stop button, a handover) ends with a notification that starts no
# turn: on 2026-10-09 two handed-over sessions got their runs' `stopped` notifications at 20:25Z and stayed idle.
NO_TURN_STATUSES = ("stopped", "killed")


@dataclass
class Waiting:
    """A tool call with no result yet."""

    tool_use_id: str
    time: float
    tool: str
    what: str
    turn: int = 0  # the number of the assistant message that made the call; parallel calls share it
    ask: str | None = None  # the guard's reason when a PreToolUse hook answered `ask`


@dataclass
class Activity:
    """One pass over a transcript: its newest turn, its calls without a result and its undelivered notifications."""

    last_turn: float | None = None
    waiting: list[Waiting] = field(default_factory=list)  # since the newest tool result, oldest first
    queued: list[wave.Notice] = field(default_factory=list)  # oldest first


@dataclass
class Stall:
    sid: str
    folder: str
    title: str | None
    last_turn: float | None
    runs: list[wave.Run]  # finished after the last turn, oldest first
    queued: list[wave.Notice]
    waiting: Waiting | None
    alive: bool | None


def what_of(inp: object) -> str:
    """A call's input in one short line: a Bash command, a file path, or the JSON."""
    if isinstance(inp, dict):
        for key in ("command", "file_path", "path", "pattern", "url", "description"):
            if isinstance(inp.get(key), str):
                text = inp[key]
                break
        else:
            text = json.dumps(inp, ensure_ascii=False)
    else:
        text = str(inp)
    text = " ".join(text.split())
    return text if len(text) <= WHAT_LIMIT else text[: WHAT_LIMIT - 3] + "..."


def ask_reason(attachment: dict) -> str | None:
    """The reason of a PreToolUse hook's `ask` answer, or None for any other hook record."""
    if attachment.get("hookEvent") != "PreToolUse":
        return None
    try:
        out = json.loads(str(attachment.get("stdout") or "").strip() or "{}")
    except ValueError:
        return None
    spec = out.get("hookSpecificOutput") if isinstance(out, dict) else None
    if not isinstance(spec, dict) or spec.get("permissionDecision") != "ask":
        return None
    return str(spec.get("permissionDecisionReason") or "no reason given")


def task_of(text: str) -> str | None:
    m = TASK_ID.search(text)
    return m.group(1).strip() if m else None


def read_activity(path: Path) -> Activity:
    """The module docstring's rules, in one pass; broken lines are passed over."""
    act = Activity()
    calls: dict[str, Waiting] = {}
    asks: dict[str, str] = {}
    queue: list[tuple[str, float]] = []  # (content, enqueue time): every item, so a dequeue takes the right head
    answered = -1  # the newest turn (message number) one of whose calls got a result
    turn, last_id = 0, None
    made: dict[str, Waiting] = {}  # every call: the turn of a result after its call left `calls`
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
                act.last_turn = t if act.last_turn is None else max(act.last_turn, t)
                mid = m.get("id")
                if mid is None or mid != last_id:
                    turn += 1
                last_id = mid
                for b in m.get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("id"):
                        tool = str(b.get("name") or "?")
                        calls[str(b["id"])] = Waiting(str(b["id"]), t, tool, what_of(b.get("input")), turn)
                        made[str(b["id"])] = calls[str(b["id"])]
            elif kind == "user":
                content = m.get("content")
                if isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            call = made.get(str(b.get("tool_use_id")))
                            calls.pop(str(b.get("tool_use_id")), None)
                            answered = max(answered, call.turn) if call else answered
                gone = task_of(metrics.text_of(content))
                if gone:
                    queue = [q for q in queue if task_of(q[0]) != gone]
            elif kind == "attachment":
                att = d.get("attachment") if isinstance(d.get("attachment"), dict) else {}
                reason = ask_reason(att) if att.get("type") == "hook_success" else None
                if reason and att.get("toolUseID"):
                    asks[str(att["toolUseID"])] = reason
            elif kind == "queue-operation":
                op, content = d.get("operation"), str(d.get("content") or "")
                if op == "enqueue":
                    queue.append((content, t or 0.0))
                elif op == "dequeue" and queue:
                    queue.pop(0)
                elif op == "remove":
                    gone = task_of(content)
                    hit = next((i for i, q in enumerate(queue) if q[0] == content), None)
                    if hit is None and gone:
                        hit = next((i for i, q in enumerate(queue) if task_of(q[0]) == gone), None)
                    if hit is not None:
                        queue.pop(hit)
    for call in calls.values():
        call.ask = asks.get(call.tool_use_id)
    # A call of a turn older than the newest answered call's (an interrupted turn's) is not what the session waits on.
    # Parallel calls of one turn stay: one may have its result while another waits on its card.
    act.waiting = sorted((c for c in calls.values() if c.turn >= answered), key=lambda c: c.time)
    act.queued = [n for content, t in queue for n in wave.notices_in(content, t)]
    return act


def stall_of(path: Path, sid: str, now: float, alive: bool | None, minutes: float = STALL_MINUTES) -> Stall | None:
    """The session's stall, or None. The runs are read only for a session with no turn in the last `minutes`."""
    act = read_activity(path)
    cut = now - minutes * 60
    if act.last_turn is not None and act.last_turn >= cut:
        return None
    after = act.last_turn if act.last_turn is not None else float("-inf")
    waiting = waited_on(act.waiting)
    # A card shows from its call on; a notification queued earlier, in the same busy turn, is behind it too.
    since = float("-inf") if waiting and waiting.ask else after
    queued = [n for n in act.queued if since < n.time <= cut]
    s = wave.read_session(path, sid)
    runs = []
    if s.launches:
        runs = [r for r in wave.build_runs(s) if r.finished and r.finished_at is not None
                and after < r.finished_at <= cut and r.status not in NO_TURN_STATUSES]  # fmt: skip
    if not runs and not queued:
        return None
    runs.sort(key=lambda r: r.finished_at or 0.0)
    return Stall(sid=sid, folder=path.parent.name, title=s.title, last_turn=act.last_turn, runs=runs, queued=queued,
                 waiting=waiting, alive=alive)  # fmt: skip


def waited_on(waiting: list[Waiting]) -> Waiting | None:
    """The call a stalled session waits on: the newest one the guard asked about, else the newest one."""
    asked = [w for w in waiting if w.ask]
    return (asked or waiting)[-1] if waiting else None


def hhmm(t: float | None) -> str:
    return metrics.iso(t)[11:16] + "Z" if t is not None else "never"


def span(seconds: float) -> str:
    m = max(0, int(seconds // 60))
    return f"{m // 60} h {m % 60} min" if m >= 60 else f"{m} min"


def run_label(r: wave.Run) -> str:
    return (f"#{r.issue} " if r.issue is not None else "") + r.run_id


def line_of(st: Stall, now: float) -> str:
    """One flagged session in one line: who, since when, what finished or waits, what it waits on, what to do."""
    who = f"'{st.title}' ({st.sid[:8]}, {st.folder})" if st.title else f"{st.sid[:8]} ({st.folder})"
    since = st.last_turn if st.last_turn is not None else min([n.time for n in st.queued] + [now])
    parts = [f"no turn since {hhmm(st.last_turn)}" + (f" ({span(now - since)})" if st.last_turn is not None else "")]
    if st.runs:
        n = len(st.runs)
        names = ", ".join(f"{run_label(r)} at {hhmm(r.finished_at)}" for r in st.runs[:4])
        parts.append(f"{n} run{'s' if n != 1 else ''} finished after it ({names}{', ...' if n > 4 else ''})")
    if st.queued:
        n = len(st.queued)
        parts.append(f"{n} notification{'s' if n != 1 else ''} queued, the oldest since {hhmm(st.queued[0].time)}")
    w = st.waiting
    if w and w.ask:
        parts.append(f"waits on a permission card since {hhmm(w.time)}: {w.tool} `{w.what}` (the guard asked: {w.ask})")
    elif w:
        parts.append(f"waits on a {w.tool} call since {hhmm(w.time)} (a permission card or a long call): `{w.what}`")
    if st.alive is None:
        parts.append("whether its process lives is unknown")
    todo = "answer its card" if w and w.ask else "open it and see what it waits on"
    return f"stalled: {who}: " + "; ".join(parts) + f". The engineer: {todo}."


def recent_transcripts(dirs: list[Path], now: float, hours: float = RECENT_HOURS) -> list[tuple[Path, str]]:
    found = []
    for d in dirs:
        for p in sorted(d.glob("*.jsonl")):
            try:
                if now - p.stat().st_mtime <= hours * 3600:
                    found.append((p, p.stem))
            except OSError:
                continue
    return found


def liveness(read: Callable[[], list[sessions.Session]] = sessions.read_all,
             alive: Callable[[int, str], bool] = sessions.process_alive) -> Callable[[str], bool | None]:  # fmt: skip
    """Whether a session id's process lives: True or False from Claude Code's session files; None when no file names
    the session and no file exists at all (an older Claude Code, or the files unreadable). Claude Code removes a
    session's file when it exits, so with other files present, a session no file names is closed (False)."""
    try:
        known = read()
    except OSError:
        known = []
    by_id: dict[str, list[sessions.Session]] = {}
    for s in known:
        by_id.setdefault(s.session_id, []).append(s)

    def check(sid: str) -> bool | None:
        if sid not in by_id:
            return False if known else None
        return any(alive(s.pid, s.proc_start) for s in by_id[sid])

    return check


def main(*, dirs: list[Path] | None = None, now: float | None = None, minutes: float = STALL_MINUTES,
         alive: Callable[[str], bool | None] | None = None) -> int:  # fmt: skip
    if not minutes > 0:
        raise Failure(f"wave: --minutes must be more than 0, not {minutes:g}")
    now = time.time() if now is None else now
    if dirs is None:
        dirs = [d for c in metrics.track_checkouts(metrics.main_checkout()) for d in c["folders"]]
    check = alive or liveness()
    me = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    found = recent_transcripts(dirs, now)
    flagged = []
    for path, sid in found:
        if sid == me:
            continue
        lives = check(sid)
        if lives is False:
            continue
        try:
            st = stall_of(path, sid, now, lives, minutes)
        except OSError as exc:
            warn(f"wave: {path}: cannot read it ({exc.strerror or exc})")
            continue
        if st:
            flagged.append(st)
    for st in flagged:
        say(line_of(st, now))
    read = f"{len(found)} session transcript{'s' if len(found) != 1 else ''}"
    say(f"wave: {len(flagged)} stalled of {read} written in the last {RECENT_HOURS} h (a run finished or a "
        f"notification queued over {minutes:g} min ago with no turn after it)")  # fmt: skip
    return STALLED_EXIT if flagged else 0
