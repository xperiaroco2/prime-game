"""`unattended`: the "nobody is watching" sign of the guard (issue #750, docs/AGENT_WORKFLOW.md §8.2.11).

A manager sets it before a night and clears it when the engineer is back. While it is in force for the manager's
session (and its workflow agents), the guard's hook (hooks.pre_tool_use) answers `deny` with the reason where it
would answer `ask`, so the agent goes on instead of a permission card that holds every notification until someone
clicks it. The sign is one file per session in tools/out/unattended/ of the main checkout, named by the session's id
(CLAUDE_CODE_SESSION_ID), with an end time: a human's own session has no file, so it never counts, and a file that is
unreadable, malformed or expired counts for nothing (hooks.read_sign).
"""

from __future__ import annotations

import json
import os
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path

from . import hooks
from .common import Failure

SESSION_VAR = "CLAUDE_CODE_SESSION_ID"
MAX_HOURS = hooks.MAX_UNATTENDED_HOURS


def parse_until(text: str, now: datetime) -> datetime:
    """`HH:MM` (the next such local time), or an ISO 8601 time (without a zone: local)."""
    text = text.strip()
    local = now.astimezone().replace(tzinfo=None)  # wall clock: the +1 day step stays right across a DST change
    if len(text) <= 5 and ":" in text:
        try:
            hour, minute = (int(part) for part in text.split(":"))
            moment = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
        except ValueError:
            raise Failure(f"--until {text!r}: give HH:MM (local time) or an ISO time such as 2026-10-11T05:30Z") from None
        return (moment if moment > local else moment + timedelta(days=1)).astimezone()
    try:
        moment = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        raise Failure(f"--until {text!r}: give HH:MM (local time) or an ISO time such as 2026-10-11T05:30Z") from None
    return moment if moment.tzinfo is not None else moment.astimezone()


def sign_path(session: str, folder: Path) -> Path:
    return folder / f"{session.lower()}.json"


def own_session(env: dict[str, str] | os._Environ[str]) -> str:
    session = env.get(SESSION_VAR, "").strip()
    if not hooks.UUID_RE.fullmatch(session):
        raise Failure(
            f"{SESSION_VAR} is not set to a session id in this shell ({session!r}), so the sign cannot name the "
            "session it is for; run it from the manager's own Claude Code session"
        )
    return session


def set_sign(
    until: datetime, session: str, folder: Path, *, now: datetime, worktree: str = "", out: Callable[[str], None] = print
) -> None:
    """Write the session's sign (replacing its old one) and remove the signs that have ended."""
    if until <= now:
        raise Failure(f"the sign would end at {hooks.sign_stamp(until)}, which is not in the future")
    if until > now + timedelta(hours=MAX_HOURS):
        raise Failure(f"the sign would end at {hooks.sign_stamp(until)}, more than {MAX_HOURS:g} h ahead: a night at most")
    try:
        folder.mkdir(parents=True, exist_ok=True)
        prune(folder, now)
        data = {"session": session.lower(), "until": hooks.sign_stamp(until), "since": hooks.sign_stamp(now),
                "worktree": worktree}  # fmt: skip
        sign_path(session, folder).write_text(json.dumps(data), encoding="utf-8")
    except OSError as exc:
        raise Failure(f"could not write the sign in {folder}: {exc}") from None
    local = until.astimezone().strftime("%H:%M")
    out(
        f"unattended: until {hooks.sign_stamp(until)} ({local} local time) the guard denies, with its reason and "
        f"'{hooks.UNATTENDED_NOTE}', every command it would ask about, for session {session[:8]} and its workflow "
        "agents; `unattended --off` clears it when the engineer is back"
    )


def prune(folder: Path, now: datetime) -> int:
    """Remove the signs that have ended or that the guard would not read; the number removed."""
    removed = 0
    for path in folder.glob("*.json"):
        if hooks.read_sign(path.stem, str(folder), now) is None:
            path.unlink(missing_ok=True)
            removed += 1
    return removed


def clear(session: str | None, folder: Path, *, everyone: bool = False, out: Callable[[str], None] = print) -> int:
    """Remove the session's sign (or, `everyone`, all of them)."""
    paths = list(folder.glob("*.json")) if everyone else [sign_path(session or "", folder)]
    removed = 0
    for path in paths:
        try:
            path.unlink()
            removed += 1
        except FileNotFoundError:
            pass
        except OSError as exc:
            raise Failure(f"could not remove {path}: {exc}") from None
    out(f"unattended: {removed} sign(s) cleared; the guard asks again" if removed else "unattended: no sign to clear")
    return 0


def status(session: str, folder: Path, *, now: datetime, out: Callable[[str], None] = print) -> int:
    """Every sign in the folder, and whether this session's is in force."""
    signs = sorted(folder.glob("*.json"))
    for path in signs:
        until = hooks.read_sign(path.stem, str(folder), now)
        mine = " (this session)" if path.stem.lower() == session.lower() else ""
        state = f"in force until {hooks.sign_stamp(until)}" if until else "ended or unreadable: the guard ignores it"
        out(f"unattended: session {path.stem[:8]}{mine}: {state}")
    if not signs:
        out("unattended: no sign; the guard asks")
    return 0


def main(
    until: str | None,
    hours: float | None,
    off: bool,
    everyone: bool,
    show: bool,
    env: dict[str, str] | os._Environ[str] = os.environ,
    *,
    now: datetime | None = None,
    folder: Path | None = None,
    out: Callable[[str], None] = print,
) -> int:
    now = now or datetime.now(UTC)
    where = folder or Path(hooks.unattended_folder())
    if off:
        return clear(None if everyone else own_session(env), where, everyone=everyone, out=out)
    if show:
        return status(env.get(SESSION_VAR, ""), where, now=now, out=out)
    if (until is None) == (hours is None):
        raise Failure("give --until <time> or --hours <n> (one of them), or --off or --status")
    if hours is not None:
        if not 0 < hours <= MAX_HOURS:
            raise Failure(f"--hours {hours:g}: more than 0 and at most {MAX_HOURS:g}")
        end = now + timedelta(hours=hours)
    else:
        end = parse_until(until or "", now)
    set_sign(end, own_session(env), where, now=now, worktree=Path.cwd().name, out=out)
    return 0
