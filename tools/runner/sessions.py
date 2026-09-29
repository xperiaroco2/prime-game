"""Other Claude Code sessions working on this checkout (docs/decisions/2026-09-28-worktrees-only-for-parallel-sessions.md).

Claude Code keeps one file per running session in ~/.claude/sessions/<pid>.json with the session's `cwd`,
`sessionId`, `status` ("busy" while it works, "idle" while it waits for its human) and `updatedAt` (ms). A session
counts as active on a checkout when its process is alive, its cwd is that checkout (not one of its worktrees), it is
not the session running this command (CLAUDE_CODE_SESSION_ID), and it is busy or was updated within the last hour.
Desktop sessions that were finished but never archived stay alive and idle; the hour keeps them from counting forever.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from pathlib import Path

from .common import IS_WINDOWS

ACTIVE_WINDOW_S = 3600


@dataclass
class Session:
    pid: int
    session_id: str
    cwd: str
    status: str
    updated: float  # seconds since the epoch
    name: str
    proc_start: str = ""  # Windows: the process creation time as a FILETIME, as Claude Code writes it

    def describe(self, now: float) -> str:
        minutes = max(0, int((now - self.updated) // 60))
        return f"'{self.name or self.session_id[:8]}' (pid {self.pid}, {self.status}, last update {minutes} min ago)"


def sessions_dir() -> Path:
    base = os.environ.get("CLAUDE_CONFIG_DIR") or str(Path.home() / ".claude")
    return Path(base) / "sessions"


def read_all(folder: Path | None = None) -> list[Session]:
    found: list[Session] = []
    folder = folder or sessions_dir()
    if not folder.is_dir():
        return found
    for path in sorted(folder.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            updated = max(float(data.get("updatedAt") or 0), float(data.get("statusUpdatedAt") or 0)) / 1000
            found.append(
                Session(
                    pid=int(data["pid"]),
                    session_id=str(data.get("sessionId", "")),
                    cwd=str(data.get("cwd", "")),
                    status=str(data.get("status", "")),
                    updated=updated,
                    name=str(data.get("name", "")),
                    proc_start=str(data.get("procStart", "")),
                )
            )
        except (OSError, ValueError, KeyError, TypeError):
            continue  # a file being rewritten, or another format: not evidence of a session
    return found


def _same_checkout(cwd: str, checkout: Path) -> bool:
    """cwd is the checkout or a folder inside it, but not inside one of its .claude/worktrees."""
    try:
        inner = Path(os.path.normcase(os.path.realpath(cwd))).relative_to(os.path.normcase(os.path.realpath(checkout)))
    except ValueError:
        return False
    return inner.parts[:2] != (".claude", "worktrees")


def process_alive(pid: int, proc_start: str = "") -> bool:
    """The session's own process is still running. A pid can be reused by another program: on Windows the process
    creation time must equal the session file's procStart (checked on 2.1.284: equal for every live session). Without
    procStart, any live process counts, which errs towards a worktree."""
    if IS_WINDOWS:
        import ctypes
        from ctypes import wintypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.restype = wintypes.HANDLE
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        try:
            code = wintypes.DWORD()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)) or code.value != 259:  # STILL_ACTIVE
                return False
            if not proc_start:
                return True
            created, exited, kernel, user = (wintypes.FILETIME() for _ in range(4))
            if not kernel32.GetProcessTimes(
                handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(kernel), ctypes.byref(user)
            ):
                return True
            return str((created.dwHighDateTime << 32) | created.dwLowDateTime) == proc_start
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def alive_in(path: Path, folder: Path | None = None) -> list[Session]:
    """Live sessions whose cwd is path or a folder in it, however long idle, the calling session included. On Windows
    such a session keeps the folder open, so it cannot be deleted: a worktree removal git began then stops half done
    (seen on #27 with sessions idle for hours)."""
    target = Path(os.path.normcase(os.path.realpath(path)))
    found = []
    for s in read_all(folder):
        cwd = Path(os.path.normcase(os.path.realpath(s.cwd))) if s.cwd else None
        if cwd and (cwd == target or target in cwd.parents) and process_alive(s.pid, s.proc_start):
            found.append(s)
    return found


def active_on(checkout: Path, now: float | None = None, folder: Path | None = None) -> list[Session]:
    """Other sessions active on checkout, as the module docstring defines them."""
    now = time.time() if now is None else now
    me = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    return [
        s
        for s in read_all(folder)
        if s.session_id != me
        and _same_checkout(s.cwd, checkout)
        and (s.status == "busy" or now - s.updated < ACTIVE_WINDOW_S)
        and process_alive(s.pid, s.proc_start)
    ]
