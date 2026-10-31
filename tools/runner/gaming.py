"""`gaming`: gaming mode, the engineer's switch that holds every window run while he plays on this PC (#1505).

`gaming --on` writes a machine-local file outside every checkout (as `slots` keeps its folder: %LOCALAPPDATA%\\
prime-game\\gaming-mode.json on Windows, else $XDG_CACHE_HOME or ~/.cache), so the main checkout and every worktree's
workflow agents read the one file. While it is there, each command that opens a Godot window (`shot`, `playcheck`,
`run` without --headless, and `host`, `join` with windows) refuses with exit code 3 and the line LINE, before it
starts anything; headless commands (`verify`, `check`, `test`, `lint`, `bots`, `perf`, `run --headless`, ...) run as
before. `gaming --off` removes the file; `--status` says which. It refuses rather than waits: a night of play outlasts
any bounded wait, and an agent's call may block no longer than 180 s (docs/AGENT_WORKFLOW.md §11.17), so the agent
gets the line at once and lists the window run for later. A file it cannot read counts as on (a window would take the
game's focus). FILE_VAR replaces the path (the runner tests set it, so the engineer's own switch never reaches them).
"""

from __future__ import annotations

import json
import os
import socket
from collections.abc import Callable, Mapping
from datetime import UTC, datetime
from pathlib import Path

from .common import IS_WINDOWS, Failure

FILE_VAR = "PRIME_GAMING_FILE"
NAME = "gaming-mode.json"
EXIT = 3
LINE = "gaming mode: window runs wait; `gaming --off` when the PC is free"


class GamingMode(Failure):
    """A window run refused while gaming mode is on (the runner exits EXIT)."""


def path(env: Mapping[str, str] = os.environ) -> Path:
    """The machine-local file: FILE_VAR, else %LOCALAPPDATA%\\prime-game\\gaming-mode.json (Windows) or
    $XDG_CACHE_HOME (or ~/.cache)/prime-game/gaming-mode.json."""
    if env.get(FILE_VAR):
        return Path(env[FILE_VAR])
    if IS_WINDOWS:
        base = Path(env.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
    else:
        base = Path(env.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return base / "prime-game" / NAME


def since(env: Mapping[str, str] = os.environ) -> str | None:
    """None when gaming mode is off; else when it was turned on ('' when the file does not say)."""
    where = path(env)
    try:
        text = where.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except OSError:
        return ""
    try:
        data = json.loads(text)
    except ValueError:
        return ""
    return str(data.get("since", "")) if isinstance(data, dict) else ""


def is_on(env: Mapping[str, str] = os.environ) -> bool:
    return since(env) is not None


def refuse_windows(command: str, env: Mapping[str, str] = os.environ) -> None:
    """Raise GamingMode when gaming mode is on: `command` would open a Godot window."""
    if is_on(env):
        raise GamingMode(f"{command} opens a Godot window and gaming mode is on ({path(env)}).\n{LINE}")


def stamp(moment: datetime) -> str:
    return moment.astimezone(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def main(
    on: bool = False,
    off: bool = False,
    status: bool = False,
    env: Mapping[str, str] = os.environ,
    *,
    now: datetime | None = None,
    out: Callable[[str], None] = print,
) -> int:
    """`gaming --on | --off | --status`."""
    if on + off + status != 1:
        raise Failure("gaming: give one of --on, --off or --status")
    where = path(env)
    if on:
        moment = stamp(now or datetime.now(UTC))
        data = {"since": moment, "host": socket.gethostname()}
        try:
            where.parent.mkdir(parents=True, exist_ok=True)
            where.write_text(json.dumps(data) + "\n", encoding="utf-8")
        except OSError as exc:
            raise Failure(f"gaming: could not write {where}: {exc}") from None
        out(
            f"gaming mode: on since {moment}. shot, playcheck, run (with a window), host and join (with windows) "
            f"refuse with exit {EXIT} on this PC; headless commands run as before. `gaming --off` when the PC is free"
        )
        return 0
    if off:
        try:
            where.unlink()
        except FileNotFoundError:
            out("gaming mode: already off; window runs go ahead")
            return 0
        except OSError as exc:
            raise Failure(f"gaming: could not remove {where}: {exc}") from None
        out("gaming mode: off; window runs go ahead again")
        return 0
    when = since(env)
    if when is None:
        out(f"gaming mode: off; window runs go ahead (no {where})")
    else:
        out(f"gaming mode: on since {when or 'an unknown time (the file is unreadable)'}; window runs refuse with exit "
            f"{EXIT} ({where})")  # fmt: skip
    return 0
