"""`host` and `join`: headless sessions over ENet with the pinned Godot (ARCHITECTURE §4.6, docs/AGENT_WORKFLOW.md §11).

`host [--port P] [--clients N] [--local] [--seconds S]` runs tools/run/headless_session.gd as the host (a HostSession
and its own ClientSession, the base mode from content/) and, with --clients, N more processes that join it on
127.0.0.1 once it is hosting. `join <address> [--port P] [--seconds S]` runs one client that joins a host. Each
process prints the roster, the phase and the counters as they change; the runner echoes its lines live, labelled,
and keeps one log per process in tools/out/logs/session/.

They run until Ctrl+C, until --seconds pass, or until every process ended. Stopping is clean: the runner creates a
stop file that each process polls; it closes its session (so the clients see host_lost at once, not after ENet's
timeout) and exits 0. A process still running GRACE_SECONDS later is killed and fails the run; a second Ctrl+C kills
at once. The run fails when a process exits non-zero (a refused join, a host that could not start) or prints an
engine error line, as `run` does.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from . import launch
from .common import IS_WINDOWS, LOGS, ROOT, Failure, bad, ensure_out, kill_tree, ok, rel, require_godot, say

SCRIPT = "tools/run/headless_session.gd"
LOCALHOST = "127.0.0.1"
# The host and its local clients are at most `run`'s instances.
MAX_CLIENTS = launch.MAX_INSTANCES - 1
MAX_SECONDS = 24 * 3600
# How long a process gets to close its session and exit after the stop file appears.
GRACE_SECONDS = 10
# How long the local clients wait for the host's HOSTING line before they start anyway (they then fail to join).
HOST_READY_SECONDS = 60
# The line the script prints once it hosts (headless_session.gd's HOSTING).
HOSTING = "session: hosting"
POLL_SECONDS = 0.1
LOG_DIR = LOGS / "session"


@dataclass
class Part:
    """One Godot process of the session."""

    label: str
    user_args: list[str]
    cmd: list[str] = field(default_factory=list)
    proc: subprocess.Popen[bytes] | None = None
    reader: threading.Thread | None = None
    lines: list[str] = field(default_factory=list)
    killed: bool = False
    log: Path | None = None

    @property
    def running(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    @property
    def problem(self) -> str:
        """Why this process failed, or '' when it passed."""
        if self.proc is None:
            return "never started"
        if self.killed:
            return f"did not stop within {GRACE_SECONDS}s of the stop and was killed"
        if self.proc.returncode != 0:
            last = next((line for line in reversed(self.lines) if line.startswith("session: ")), "")
            return f"exited {self.proc.returncode}" + (f" ({last.removeprefix('session: ')})" if last else "")
        count = launch.error_lines(self.lines)[0]
        if count:
            return f"exited 0 but printed {count} engine error line{'s' if count > 1 else ''}"
        return ""


def stop_file() -> Path:
    """The stop file of this runner process (two runs in one checkout, a host and a join, never share one)."""
    return LOG_DIR / f"stop-{os.getpid()}"


def host_parts(port: int | None, clients: int, *, local: bool, stop: Path) -> list[Part]:
    """The host and its `clients` local joiners."""
    tail = ([f"--port={port}"] if port is not None else []) + [f"--stop-file={stop}"]
    parts = [Part("host", ["--host", *(["--local"] if local else []), *tail])]
    parts += [Part(f"client {i}", [f"--join={LOCALHOST}", *tail]) for i in range(2, clients + 2)]
    return parts


def join_parts(address: str, port: int | None, *, stop: Path) -> list[Part]:
    tail = ([f"--port={port}"] if port is not None else []) + [f"--stop-file={stop}"]
    return [Part("join", [f"--join={address}", *tail])]


def check_options(*, port: int | None, clients: int = 0, seconds: int | None = None, address: str | None = None) -> None:
    if port is not None and not 1 <= port <= 65535:
        raise Failure("--port must be between 1 and 65535")
    if not 0 <= clients <= MAX_CLIENTS:
        raise Failure(f"--clients must be between 0 and {MAX_CLIENTS}")
    if seconds is not None and not 1 <= seconds <= MAX_SECONDS:
        raise Failure(f"--seconds must be between 1 and {MAX_SECONDS}")
    if address is not None and (not address.strip() or address.startswith("-")):
        raise Failure("join needs the host's address, such as 192.168.0.195 or 127.0.0.1")


_echo_lock = threading.Lock()


def start(part: Part, *, cwd: Path = ROOT) -> None:
    """Start the process in its own process group (Ctrl+C reaches only the runner) and echo its lines live."""
    kwargs: dict[str, object] = {}
    if IS_WINDOWS:
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    try:
        part.proc = subprocess.Popen(
            part.cmd,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            **kwargs,  # type: ignore[arg-type]
        )
    except FileNotFoundError as exc:
        raise Failure(f"cannot start {part.cmd[0]}: {exc}") from exc

    def pump() -> None:
        assert part.proc is not None and part.proc.stdout is not None
        for raw in iter(part.proc.stdout.readline, b""):
            text = launch.ANSI_RE.sub("", raw.decode("utf-8", errors="replace")).rstrip("\r\n")
            part.lines.append(text)
            with _echo_lock:
                sys.stdout.write(f"[{part.label}] {text}\n")
                sys.stdout.flush()

    part.reader = threading.Thread(target=pump, daemon=True)
    part.reader.start()


def supervise(
    parts: list[Part],
    *,
    seconds: int | None,
    stop: Path,
    cwd: Path = ROOT,
    until: Callable[[list[Part]], bool] | None = None,
) -> None:
    """Start the parts (the others once the first one hosts), wait, then stop them all cleanly.

    The wait ends on Ctrl+C, after `seconds`, when every part ended, or when `until(parts)` holds (a check's own end).
    """
    stop.parent.mkdir(parents=True, exist_ok=True)
    stop.unlink(missing_ok=True)
    started = time.monotonic()
    try:
        start(parts[0], cwd=cwd)
        if len(parts) > 1:
            while parts[0].running and not any(line.startswith(HOSTING) for line in parts[0].lines):
                if time.monotonic() - started > HOST_READY_SECONDS:
                    break
                time.sleep(POLL_SECONDS)
            if parts[0].running:
                for part in parts[1:]:
                    start(part, cwd=cwd)
        while any(part.running for part in parts):
            if seconds is not None and time.monotonic() - started >= seconds:
                say(f"session: {seconds}s passed, stopping")
                break
            if until is not None and until(parts):
                break
            time.sleep(POLL_SECONDS)
    except KeyboardInterrupt:
        say(f"session: Ctrl+C, stopping (each process gets {GRACE_SECONDS}s; Ctrl+C again kills them)")
    finally:
        _stop(parts, stop)


def _stop(parts: list[Part], stop: Path) -> None:
    stop.write_text("stop\n", encoding="ascii")
    try:
        deadline = time.monotonic() + GRACE_SECONDS
        while any(part.running for part in parts) and time.monotonic() < deadline:
            time.sleep(POLL_SECONDS)
    except KeyboardInterrupt:
        pass
    finally:
        for part in parts:
            if part.running and part.proc is not None:
                part.killed = True
                kill_tree(part.proc)
        for part in parts:
            if part.reader is not None:
                part.reader.join(timeout=5)
            if part.proc is not None and part.proc.stdout is not None and not (part.reader and part.reader.is_alive()):
                part.proc.stdout.close()
        stop.unlink(missing_ok=True)


def write_logs(parts: list[Part], log_dir: Path) -> None:
    """One log per part, `<label>.log`; a host run first removes the logs of an earlier run's extra clients."""
    log_dir.mkdir(parents=True, exist_ok=True)
    if parts[0].label == "host":
        for old in log_dir.glob("client-*.log"):
            old.unlink()
    for part in parts:
        part.log = log_dir / f"{part.label.replace(' ', '-')}.log"
        part.log.write_text("".join(f"{line}\n" for line in part.lines), encoding="utf-8")


def report(parts: list[Part]) -> int:
    failed = 0
    for part in parts:
        where = ""
        if part.log is not None:
            where = f" (log: {rel(part.log) if part.log.is_relative_to(ROOT) else part.log})"
        if part.problem:
            failed += 1
            bad(f"{part.label}: {part.problem}{where}", "\n".join(launch.error_lines(part.lines)[1]))
        else:
            ok(f"{part.label}: stopped cleanly{where}")
    say(f"session: FAILED ({failed} of {len(parts)})" if failed else "session: passed")
    return 1 if failed else 0


def set_commands(parts: list[Part], exe: str) -> None:
    """Each part's Godot command line: the script, headless, with the part's arguments after --."""
    for part in parts:
        part.cmd = launch.command(
            exe, ROOT, f"res://{SCRIPT}", headless=True, offscreen=False, audio="dummy", user_args=part.user_args
        )


def _run(name: str, parts: list[Part], seconds: int | None) -> int:
    exe = require_godot()
    ensure_out()
    launch.import_if_missing()
    set_commands(parts, exe)
    say(f"        {' '.join(parts[0].cmd[1:])}" + (f"  (+{len(parts) - 1} local clients)" if len(parts) > 1 else ""))
    if seconds is None:
        say(f"        {name} runs until Ctrl+C")
    supervise(parts, seconds=seconds, stop=stop_file())
    write_logs(parts, LOG_DIR)
    return report(parts)


def host(*, port: int | None, clients: int, local: bool, seconds: int | None) -> int:
    say("host")
    check_options(port=port, clients=clients, seconds=seconds)
    return _run("host", host_parts(port, clients, local=local, stop=stop_file()), seconds)


def join(address: str, *, port: int | None, seconds: int | None) -> int:
    say("join")
    check_options(port=port, seconds=seconds, address=address)
    return _run("join", join_parts(address, port, stop=stop_file()), seconds)
