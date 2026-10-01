"""`host` and `join`: the game in windows, or headless sessions, over ENet with the pinned Godot.

ARCHITECTURE §4.6 and §4.7, the M4 ADR's E20, docs/AGENT_WORKFLOW.md §11.

`host [--port P] [--clients N] [--local] [--seconds S]` runs the game, client/app/game.tscn, in a window as the host
and, with --clients, N more windows that join it on 127.0.0.1 once it is hosting; on one PC the windows are tiled
over the primary screen with --position and --resolution. `join <address> [--port P] [--seconds S]` runs one window
that joins a host. The game reads the command line that the headless session reads (client/app/launch_options.gd:
--host [--local], --join=, --port=, the stop and alive files below) and skips its menu. A windowed host on every
interface gets the runner's line of what to type on another PC.

With --headless they run M3's tools/run/headless_session.gd instead (a HostSession and its own ClientSession, the
base mode from content/), which prints the roster, the phase and the counters as they change. In a shell where
CLAUDECODE is set (an agent's) that is the default too, so an unattended run never opens a window on a human's
screen; there --windows asks for windows, which agents never pass. Every process's lines are echoed live, labelled,
and kept in one log per process in tools/out/logs/session/.

They run until Ctrl+C, until --seconds pass, or until every process ended (every window closed). Stopping is clean:
the runner creates a stop file that each process polls; it closes its session (so the clients see host_lost at once,
not after ENet's timeout) and exits 0. A process still running GRACE_SECONDS later is killed and fails the run; a
second Ctrl+C kills at once. The runner also touches an alive file every second: a runner that is killed (an agent's
command timeout) leaves no session running, since each process stops once that file is gone or ten seconds old. The
run fails when a process exits non-zero (a refused join, a host that could not start) or prints an engine error
line, as `run` does.

`game_check` is verify's `game` step: the game scene headless through that same command line, a host and one client
over ENet on 127.0.0.1, both welcomed into the lobby, then both stopped through the stop file.
"""

from __future__ import annotations

import math
import os
import re
import socket
import subprocess
import sys
import threading
import time
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from pathlib import Path

from . import launch, shot
from .common import IS_WINDOWS, LOGS, ROOT, Failure, bad, ensure_out, kill_tree, ok, rel, require_godot, say

SCRIPT = "tools/run/headless_session.gd"
GAME = "client/app/game.tscn"
# Claude Code sets it in an agent's shell; a human's terminal has none (the M4 ADR's E20).
AGENT_ENV = "CLAUDECODE"
LOCALHOST = "127.0.0.1"
# The host and its local clients are at most `run`'s instances.
MAX_CLIENTS = launch.MAX_INSTANCES - 1
MAX_SECONDS = 24 * 3600
# How long a process gets to close its session and exit after the stop file appears.
GRACE_SECONDS = 10
# How long the local clients wait for the host's HOSTING line before they start anyway (they then fail to join).
HOST_READY_SECONDS = 60
# The line a host prints once it listens (LaunchOptions.HOSTING in client/app/launch_options.gd).
HOSTING = "session: hosting"
# The line a host prints when it cannot listen: the headless session then exits 1, the game shows its menu.
CANNOT_HOST = "session: cannot host"
# The line the game prints once its host welcomed it (client/app/game.gd); a fresh host welcomes in its lobby.
WELCOMED = re.compile(r"^session: welcomed as \S+ \[\d+\]$")
# The line the game prints when its session ends, with the reason (client/app/game.gd); it then shows its menu.
ENDED = "session: ended:"
# The line both the game and the headless session print when they stop for the runner.
STOPPED = "session: stopped"
NO_REPLAY = "--no-replay"
POLL_SECONDS = 0.1
# How often the runner touches its alive file (the script stops once it is ALIVE_SECONDS = 10 old).
ALIVE_BEAT_SECONDS = 1.0
LOG_DIR = LOGS / "session"
# Tiling: the primary screen's work area (x, y, width, height) when the system cannot say, and the room left above
# each window's client area for its title bar (Godot's --position places the client area). Placeholders.
FALLBACK_AREA = (0, 0, 1920, 1040)
TITLE_BAR = 48
SPI_GETWORKAREA = 0x0030
# verify's `game` step: its time limit, how long both stay in the lobby before the stop, and its logs.
GAME_CHECK_SECONDS = 60
GAME_SETTLE_SECONDS = 1.0
GAME_LOG_DIR = LOGS / "game"
# The supervision's own sleep, so a test can patch it without patching time.sleep for everyone.
_sleep = time.sleep


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
    # What a check of its own found missing in a process that ended well (a window, verify's game step).
    unmet: str = ""

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
        return self.unmet


@dataclass(frozen=True)
class Tile:
    """Where one window goes: its client area's top-left corner and size, in screen pixels."""

    x: int
    y: int
    width: int
    height: int

    def args(self) -> list[str]:
        return ["--position", f"{self.x},{self.y}", "--resolution", f"{self.width}x{self.height}"]


def stop_file() -> Path:
    """The stop file of this runner process (two runs in one checkout, a host and a join, never share one)."""
    return LOG_DIR / f"stop-{os.getpid()}"


def alive_file(stop: Path) -> Path:
    """The file the runner touches every second while it runs: a process whose runner was killed stops itself."""
    return stop.with_name(f"{stop.name}.alive")


def _tail(port: int | None, stop: Path) -> list[str]:
    port_args = [f"--port={port}"] if port is not None else []
    return [*port_args, f"--stop-file={stop}", f"--alive-file={alive_file(stop)}"]


def host_parts(port: int | None, clients: int, *, local: bool, stop: Path) -> list[Part]:
    """The host and its `clients` local joiners."""
    tail = _tail(port, stop)
    parts = [Part("host", ["--host", *(["--local"] if local else []), *tail])]
    parts += [Part(f"client {i}", [f"--join={LOCALHOST}", *tail]) for i in range(2, clients + 2)]
    return parts


def join_parts(address: str, port: int | None, *, stop: Path) -> list[Part]:
    return [Part("join", [f"--join={address}", *_tail(port, stop)])]


def check_options(*, port: int | None, clients: int = 0, seconds: int | None = None, address: str | None = None) -> None:
    if port is not None and not 1 <= port <= 65535:
        raise Failure("--port must be between 1 and 65535")
    if not 0 <= clients <= MAX_CLIENTS:
        raise Failure(f"--clients must be between 0 and {MAX_CLIENTS}")
    if seconds is not None and not 1 <= seconds <= MAX_SECONDS:
        raise Failure(f"--seconds must be between 1 and {MAX_SECONDS}")
    if address is not None and (not address.strip() or address.startswith("-")):
        raise Failure("join needs the host's address, such as 192.168.0.195 or 127.0.0.1")


def windowed(*, headless: bool, windows: bool, env: Mapping[str, str] | None = None) -> bool:
    """Whether to open windows: --headless never, --windows always, else unless CLAUDECODE is set (an agent's shell)."""
    if headless and windows:
        raise Failure("give --headless or --windows, not both")
    if headless or windows:
        return windows
    return not (os.environ if env is None else env).get(AGENT_ENV)


def choose_windows(*, headless: bool, windows: bool) -> bool:
    """windowed(), saying why an agent's shell runs headless; a window needs a desktop session."""
    shown = windowed(headless=headless, windows=windows)
    if not shown and not headless:
        say(f"        {AGENT_ENV} is set (an agent's shell): the headless session; a human's terminal opens windows")
    if shown and not shot.has_display():
        raise Failure("a window needs a desktop session; add --headless (CI and headless machines)")
    return shown


def tiles(count: int, area: tuple[int, int, int, int]) -> list[Tile]:
    """`count` 16:9 windows in a near-square grid over `area` (x, y, width, height), row by row, each below its
    title bar."""
    x0, y0, width, height = area
    columns = math.ceil(math.sqrt(count))
    rows = math.ceil(count / columns)
    cell_w, cell_h = width // columns, height // rows
    w, h = cell_w, cell_h - TITLE_BAR
    if w * 9 > h * 16:
        w = h * 16 // 9
    else:
        h = w * 9 // 16
    return [Tile(x0 + (i % columns) * cell_w, y0 + (i // columns) * cell_h + TITLE_BAR, w, h) for i in range(count)]


def screen_area() -> tuple[int, int, int, int]:
    """The primary screen's work area (no taskbar) in physical pixels, as Godot counts them; else FALLBACK_AREA.

    Asking makes the runner's own process DPI-aware, so a scaled screen is not reported in scaled pixels.
    """
    if not IS_WINDOWS:
        return FALLBACK_AREA
    try:
        import ctypes
        from ctypes import wintypes

        windll = ctypes.windll  # type: ignore[attr-defined]
        try:
            windll.shcore.SetProcessDpiAwareness(2)  # per monitor, as Godot's own windows
        except (AttributeError, OSError):
            windll.user32.SetProcessDPIAware()
        rect = wintypes.RECT()
        if windll.user32.SystemParametersInfoW(SPI_GETWORKAREA, 0, ctypes.byref(rect), 0):
            return (rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top)
    except (AttributeError, OSError):
        pass
    return FALLBACK_AREA


def lan_addresses() -> list[str]:
    """This PC's IPv4 addresses other than loopback, for the line a windowed host prints."""
    try:
        infos = socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
    except OSError:
        return []
    return sorted({str(info[4][0]) for info in infos if not str(info[4][0]).startswith("127.")})


def lan_hint(hosting_line: str) -> None:
    """What to type on another PC, once a windowed host on every interface hosts (the headless session prints
    its own)."""
    port = hosting_line.rsplit(":", 1)[-1]
    addresses = ", ".join(lan_addresses()) or "no LAN address"
    say(f"session: from another machine: tools\\run.cmd join <address> --port {port} (this one: {addresses})")


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
    on_hosting: Callable[[str], None] | None = None,
) -> None:
    """Start the parts (the others once the first one hosts), wait, then stop them all cleanly.

    The wait ends on Ctrl+C, after `seconds`, when every part ended, or when `until(parts)` holds (a check's own end).
    `on_hosting` gets the first part's HOSTING line once it printed one. A host that says it cannot host gets no
    clients: the headless session then exits, the game stays at its menu with the reason.
    """
    stop.parent.mkdir(parents=True, exist_ok=True)
    stop.unlink(missing_ok=True)
    alive = alive_file(stop)
    alive.write_text("alive\n", encoding="ascii")
    done = threading.Event()
    beat = threading.Thread(target=_keep_alive, args=(alive, done), daemon=True)
    beat.start()
    started = time.monotonic()
    try:
        start(parts[0], cwd=cwd)
        if len(parts) > 1 or on_hosting is not None:
            hosting = _wait_for_host(parts[0], started)
            if hosting and on_hosting is not None:
                on_hosting(hosting)
            if parts[0].running and not _cannot_host(parts[0]):
                for part in parts[1:]:
                    start(part, cwd=cwd)
        while any(part.running for part in parts):
            if seconds is not None and time.monotonic() - started >= seconds:
                say(f"session: {seconds}s passed, stopping")
                break
            if until is not None and until(parts):
                break
            _sleep(POLL_SECONDS)
    except KeyboardInterrupt:
        say(f"session: Ctrl+C, stopping (each process gets {GRACE_SECONDS}s; Ctrl+C again kills them)")
    finally:
        _stop(parts, stop)
        done.set()
        beat.join(timeout=5)
        alive.unlink(missing_ok=True)


def _hosting_line(host: Part) -> str:
    return next((line for line in host.lines if line.startswith(HOSTING)), "")


def _cannot_host(host: Part) -> bool:
    return any(line.startswith(CANNOT_HOST) for line in host.lines)


def _wait_for_host(host: Part, started: float) -> str:
    """The host's HOSTING line; '' when it ended or said it cannot host first, or took HOST_READY_SECONDS."""
    while host.running and not _hosting_line(host) and not _cannot_host(host):
        if time.monotonic() - started > HOST_READY_SECONDS:
            break
        _sleep(POLL_SECONDS)
    return _hosting_line(host)


def _keep_alive(alive: Path, done: threading.Event) -> None:
    """Touch the alive file every second until `done`; a killed runner stops touching it."""
    while not done.wait(ALIVE_BEAT_SECONDS):
        try:
            os.utime(alive)
        except OSError:
            pass


def _stop(parts: list[Part], stop: Path) -> None:
    stop.write_text("stop\n", encoding="ascii")
    try:
        deadline = time.monotonic() + GRACE_SECONDS
        while any(part.running for part in parts) and time.monotonic() < deadline:
            _sleep(POLL_SECONDS)
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
    """Each part's Godot command line: the headless session script, with the part's arguments after --."""
    for part in parts:
        part.cmd = launch.command(
            exe, ROOT, f"res://{SCRIPT}", headless=True, offscreen=False, audio="dummy", user_args=part.user_args
        )


def set_game_commands(
    parts: list[Part], exe: str, *, headless: bool, area: tuple[int, int, int, int] | None = None
) -> None:
    """Each part's Godot command line: the game scene with the part's arguments after --.

    Headless (verify's game step) or in a window with the real audio driver. The windows of a host and its local
    clients are tiled over `area` (the primary screen's work area when None); a lone window goes where the system
    puts it.
    """
    placed: list[list[str]] = []
    if not headless and len(parts) > 1:
        placed = [tile.args() for tile in tiles(len(parts), area or screen_area())]
    for i, part in enumerate(parts):
        part.cmd = launch.command(
            exe,
            ROOT,
            f"res://{GAME}",
            headless=headless,
            offscreen=False,
            audio="dummy" if headless else "default",
            user_args=part.user_args,
            window=placed[i] if placed else None,
        )


def _run(
    name: str,
    parts: list[Part],
    seconds: int | None,
    stop: Path,
    *,
    windows: bool,
    on_hosting: Callable[[str], None] | None = None,
) -> int:
    # The console exe in windows too: it opens the window and relays the lines the runner reads (HOSTING).
    exe = require_godot()
    ensure_out()
    launch.import_if_missing()
    if windows:
        set_game_commands(parts, exe, headless=False)
    else:
        set_commands(parts, exe)
    more = f"  (+{len(parts) - 1} local client{'s' if len(parts) > 2 else ''})" if len(parts) > 1 else ""
    say(f"        {' '.join(parts[0].cmd[1:])}{more}")
    if seconds is None:
        say(f"        {name} runs until Ctrl+C" + (" or until every window is closed" if windows else ""))
    supervise(parts, seconds=seconds, stop=stop, on_hosting=on_hosting)
    if windows:
        check_windowed_parts(parts)
    write_logs(parts, LOG_DIR)
    return report(parts)


def host(
    *,
    port: int | None,
    clients: int,
    local: bool,
    seconds: int | None,
    headless: bool = False,
    windows: bool = False,
) -> int:
    say("host")
    check_options(port=port, clients=clients, seconds=seconds)
    shown = choose_windows(headless=headless, windows=windows)
    stop = stop_file()
    hint = lan_hint if shown and not local else None
    parts = host_parts(port, clients, local=local, stop=stop)
    return _run("host", parts, seconds, stop, windows=shown, on_hosting=hint)


def join(address: str, *, port: int | None, seconds: int | None, headless: bool = False, windows: bool = False) -> int:
    say("join")
    check_options(port=port, seconds=seconds, address=address)
    shown = choose_windows(headless=headless, windows=windows)
    stop = stop_file()
    return _run("join", join_parts(address, port, stop=stop), seconds, stop, windows=shown)


def welcomed(part: Part) -> bool:
    return any(WELCOMED.match(line) for line in part.lines)


def check_windowed_parts(parts: list[Part]) -> None:
    """Marks a window that ended well but was never welcomed: the game goes back to its menu instead of exiting when
    it cannot host or its join fails, so its exit code alone would report a session that never formed as passed."""
    for part in parts:
        if part.problem or welcomed(part):
            continue
        why = next((line for line in reversed(part.lines) if line.startswith((CANNOT_HOST, ENDED))), "")
        part.unmet = "never welcomed: " + (why.removeprefix("session: ") if why else "it reached no lobby")


def check_game_parts(parts: list[Part]) -> None:
    """Marks a part that ended well but was never welcomed, or ended without stopping for the stop file."""
    for part in parts:
        if part.problem:
            continue
        if not welcomed(part):
            part.unmet = "never welcomed: it reached no lobby"
        elif STOPPED not in part.lines:
            part.unmet = f"exited without '{STOPPED}': it did not end through the stop file"


def game_check(port: int, *, seconds: int = GAME_CHECK_SECONDS) -> int:
    """verify's `game` step: the game scene headless through its command line, a host (--local, no replay) and one
    client over ENet on 127.0.0.1:`port`; both welcomed into the lobby, GAME_SETTLE_SECONDS there, then both stopped
    through the stop file with exit 0 and no engine error line."""
    say("game")
    exe = require_godot()
    ensure_out()
    launch.import_if_missing()
    stop = stop_file()
    parts = host_parts(port, 1, local=True, stop=stop)
    parts[0].user_args.append(NO_REPLAY)
    set_game_commands(parts, exe, headless=True)
    say(f"        {' '.join(parts[0].cmd[1:])}  (+1 local client)")
    supervise(parts, seconds=seconds, stop=stop, until=_settled_in_lobby())
    check_game_parts(parts)
    write_logs(parts, GAME_LOG_DIR)
    return report(parts)


def _settled_in_lobby() -> Callable[[list[Part]], bool]:
    """True once every part has been welcomed for GAME_SETTLE_SECONDS: the lobby level loaded and a few frames ran."""
    since: list[float] = []

    def check(parts: list[Part]) -> bool:
        if not all(welcomed(part) for part in parts):
            return False
        if not since:
            since.append(time.monotonic())
        return time.monotonic() - since[0] >= GAME_SETTLE_SECONDS

    return check
