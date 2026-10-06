"""Shared helpers: paths, output, running processes with a hard timeout, locating tools."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import signal
import site
import stat
import subprocess
import sys
import tempfile
import threading
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path

from . import pins

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tools" / "out"
LOGS = OUT / "logs"
# The gitignored folder for temporary files that must live under res:// (a probe test). The guard lets its deletes
# pass; full lint, check and test runs skip it, a run that names a path in it covers that path. Godot still imports
# it, so check's UID lint counts one thing there: a uid a file in it shares with a project file (uids.py, #264).
SCRATCH = "tests/scratch"
IS_WINDOWS = os.name == "nt"
IS_LINUX = sys.platform.startswith("linux")
IS_CI = os.environ.get("CI", "").lower() in ("1", "true", "yes")
# A Claude Code cloud session (#159): a headless Linux container set up by tools/cloud/setup.sh, like CI.
IS_CLOUD = os.environ.get("CLAUDE_CODE_REMOTE", "").lower() == "true"


def cloud_session(cloud: bool | None = None, ci: bool | None = None) -> bool:
    """A Claude Code cloud session, not a CI job that sets CLAUDE_CODE_REMOTE too: doctor's cloud steps and the
    guard's cloud checkout (#381) share this test. cloud and ci stand in for IS_CLOUD and IS_CI (doctor's tests)."""
    return (IS_CLOUD if cloud is None else cloud) and not (IS_CI if ci is None else ci)


# Directories that hold project GDScript (addons/ is third-party and never linted or checked).
GD_DIRS = ("core", "server", "net", "client", "voice", "content", "levels", "tools", "tests")


class Failure(Exception):
    """A command failed; the message is already actionable for the reader."""


def say(text: str = "") -> None:
    print(text, flush=True)


def ok(text: str) -> None:
    say(f"  ok    {text}")


def bad(text: str, fix: str = "") -> None:
    say(f"  FAIL  {text}")
    if fix:
        for line in fix.splitlines():
            say(f"        -> {line}")


def warn(text: str) -> None:
    say(f"  warn  {text}")


def skip(text: str) -> None:
    say(f"  skip  {text}")


def ensure_out() -> Path:
    """Create tools/out/ with a .gdignore so Godot never imports runner output."""
    LOGS.mkdir(parents=True, exist_ok=True)
    marker = OUT / ".gdignore"
    if not marker.exists():
        marker.write_text("", encoding="ascii")
    return OUT


@dataclass
class Result:
    rc: int
    out: str
    timed_out: bool
    seconds: float
    restarted: bool = False  # run() started it a second time, since Windows refused its first start (#441)

    @property
    def lines(self) -> list[str]:
        return self.out.splitlines()


def kill_tree(proc: subprocess.Popen[bytes]) -> None:
    # The Windows console exe of Godot spawns the real engine as a child, so kill the whole tree.
    if IS_WINDOWS:
        subprocess.run(
            ["taskkill", "/T", "/F", "/PID", str(proc.pid)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    proc.wait()


def group_kwargs() -> dict[str, object]:
    """Popen arguments that start a process in a group of its own: Ctrl+C reaches only the runner, and kill_tree can
    stop the process with all of its children."""
    if IS_WINDOWS:
        return {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP}
    return {"start_new_session": True}


def run(
    cmd: list[str],
    *,
    timeout: float,
    cwd: Path = ROOT,
    log: str | None = None,
    echo: bool = False,
    env: dict[str, str] | None = None,
    on_start: Callable[[subprocess.Popen[bytes]], None] | None = None,
    restart: bool = True,
) -> Result:
    """Run cmd with stdout+stderr merged, a hard timeout and a process-tree kill.

    The full output is also written to tools/out/logs/<log>.log when log is given. `on_start` gets the process once
    it runs (a caller running several at once keeps them, to stop them all on Ctrl+C). A process that Windows could
    not start (not_started, #441) is started once more after RESTART_PAUSE seconds, loudly; one that ran is never
    started again, whatever it returned. `restart` False only names it: an instance that runs together with others
    (one ENet game on one port), whose late second start would turn into another failure of the whole run.
    """
    first = _run_once(cmd, timeout=timeout, cwd=cwd, log=log, echo=echo, env=env, on_start=on_start)
    if first.timed_out or not not_started(first.rc, first.out, first.seconds):
        return first
    name = Path(cmd[0]).name
    what = f"{name} {exit_words(first.rc)} {first.seconds:.1f}s after its start without printing a line"
    what += ", so it never ran"
    with STARTS.lock:
        STARTS.refused += 1
        gave_up = STARTS.gave_up
        restart = restart and not gave_up
        if restart:
            STARTS.restarted += 1
    load = f" {machine_load()}".rstrip()
    if not restart:
        why = "a restart in this process failed the same way" if gave_up else "it runs together with other instances"
        warn(f"NOT STARTED: {what}; not restarted, since {why} (#441).{load}")
        return first
    warn(f"NOT STARTED, restarted once: {what}; starting it again in {RESTART_PAUSE:g}s (#441).{load}")
    _restart_sleep(RESTART_PAUSE)
    again = _run_once(cmd, timeout=timeout, cwd=cwd, log=log, echo=echo, env=env, on_start=on_start)
    with STARTS.lock:
        if not again.timed_out and not_started(again.rc, again.out, again.seconds):
            STARTS.refused += 1
            STARTS.gave_up = True
            refused = True
        else:
            STARTS.recovered += 1
            refused = False
    if refused:
        warn(f"NOT STARTED again: {name} {exit_words(again.rc)} on its restart too; this process restarts nothing more")
    else:
        warn(f"RESTARTED: {name} started on its second try (exit {again.rc} in {again.seconds:.1f}s)")
    return Result(again.rc, again.out, again.timed_out, first.seconds + RESTART_PAUSE + again.seconds, True)


# --- processes Windows could not start (#441) ------------------------------------------------------------------------
# On the engineer's PC, Godot, git, Python and PowerShell sometimes all exit with STATUS_DLL_INIT_FAILED (0xC0000142)
# a fraction of a second after their start, before they print anything: Windows failed them while it loaded their
# DLLs, so not one line of theirs ran. It happened in 11 of about 420 verify runs (10-01 to 10-05), always to every
# process that started in a window of 0.5 s to several minutes, and the same tree passed on a rerun. It is a shortage
# of a per-session resource of the machine (commit, desktop heap), not the change under test. run() starts such a
# process once more and every report names it; NOT STARTED's line carries machine_load() to find the shortage.
# The code as subprocess reports it on Windows, and as a signed 32-bit exit status.
NOT_STARTED_CODES = (0xC0000142, 0xC0000142 - (1 << 32))
# A process that printed nothing but ran longer than this was started; a refused start ends within about 2 s.
NOT_STARTED_SECONDS = 10.0
RESTART_PAUSE = 10.0
_restart_sleep = time.sleep  # a test patches this one, not time.sleep for everyone


@dataclass
class Starts:
    """This process's starts that Windows refused: each refused start, the restarts and the restarts that ran. After
    a restart that was refused too (`gave_up`) the machine is short of the resource, so nothing is restarted again."""

    refused: int = 0
    restarted: int = 0
    recovered: int = 0
    gave_up: bool = False
    lock: threading.Lock = field(default_factory=threading.Lock, repr=False, compare=False)


STARTS = Starts()


def not_started(rc: int | None, out: str, seconds: float = 0.0) -> bool:
    """Whether a process that ended with `rc` never ran: Windows' STATUS_DLL_INIT_FAILED, no output, a short life."""
    return rc in NOT_STARTED_CODES and not out.strip() and seconds < NOT_STARTED_SECONDS


def exit_words(rc: int | None) -> str:
    """`exited 3221225794 (0xC0000142, ...)` for Windows' could-not-start code, else `exited <rc>`."""
    if rc in NOT_STARTED_CODES:
        return f"exited {rc} (0xC0000142, STATUS_DLL_INIT_FAILED: Windows could not start it)"
    return f"exited {rc}"


def start_problem(rc: int | None, restarted: bool = False) -> str:
    """A report's reason for a process that never ran (not_started): what happened, whether run() restarted it
    (Result.restarted), and what to do."""
    again = ", also on its restart" if restarted else ""
    return (
        f"could not start: {exit_words(rc)} before it printed anything{again}; this PC was short of"
        " a per-session resource (too many processes at once), not the change: run verify again (#441)"
    )


def take_starts() -> dict[str, int]:
    """This process's refused starts since the last call ({} when none), and the counts start again from zero; a
    restart that was refused keeps later ones from restarting (gave_up) until the process ends."""
    with STARTS.lock:
        counts = {"refused": STARTS.refused, "restarted": STARTS.restarted, "recovered": STARTS.recovered}
        STARTS.refused = STARTS.restarted = STARTS.recovered = 0
    return counts if counts["refused"] else {}


def machine_load() -> str:
    """The machine's load at this moment on Windows, in one line: processes, threads, handles, commit and free memory
    (GetPerformanceInfo), and the USER and GDI objects of the processes it may query (GetGuiResources: the desktop
    heap holds the USER objects). '' elsewhere or when Windows does not answer. It starts no process."""
    if not IS_WINDOWS:
        return ""
    try:
        return _windows_load()
    except (OSError, AttributeError, ValueError) as exc:
        return f"machine load unknown ({exc})"


def _windows_load() -> str:
    import ctypes  # Windows only
    from ctypes import wintypes

    class PerformanceInformation(ctypes.Structure):
        _fields_ = [
            ("cb", wintypes.DWORD),
            ("CommitTotal", ctypes.c_size_t),
            ("CommitLimit", ctypes.c_size_t),
            ("CommitPeak", ctypes.c_size_t),
            ("PhysicalTotal", ctypes.c_size_t),
            ("PhysicalAvailable", ctypes.c_size_t),
            ("SystemCache", ctypes.c_size_t),
            ("KernelTotal", ctypes.c_size_t),
            ("KernelPaged", ctypes.c_size_t),
            ("KernelNonpaged", ctypes.c_size_t),
            ("PageSize", ctypes.c_size_t),
            ("HandleCount", wintypes.DWORD),
            ("ProcessCount", wintypes.DWORD),
            ("ThreadCount", wintypes.DWORD),
        ]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    info = PerformanceInformation()
    info.cb = ctypes.sizeof(info)
    if not kernel32.K32GetPerformanceInfo(ctypes.byref(info), info.cb):
        raise OSError(ctypes.get_last_error(), "GetPerformanceInfo failed")
    gib = info.PageSize / (1 << 30)
    pids = (wintypes.DWORD * 4096)()
    size = wintypes.DWORD()
    kernel32.K32EnumProcesses(pids, ctypes.sizeof(pids), ctypes.byref(size))
    kernel32.OpenProcess.restype = wintypes.HANDLE
    user = gdi = seen = 0
    for pid in pids[: size.value // ctypes.sizeof(wintypes.DWORD)]:
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            continue
        try:
            user += user32.GetGuiResources(wintypes.HANDLE(handle), 1)  # GR_USEROBJECTS
            gdi += user32.GetGuiResources(wintypes.HANDLE(handle), 0)  # GR_GDIOBJECTS
            seen += 1
        finally:
            kernel32.CloseHandle(wintypes.HANDLE(handle))
    return (
        f"Machine: {info.ProcessCount} processes, {info.ThreadCount} threads, {info.HandleCount} handles;"
        f" commit {info.CommitTotal * gib:.1f} of {info.CommitLimit * gib:.1f} GB,"
        f" {info.PhysicalAvailable * gib:.1f} of {info.PhysicalTotal * gib:.1f} GB RAM free;"
        f" {user} USER and {gdi} GDI objects in {seen} processes"
    )


def _run_once(
    cmd: list[str],
    *,
    timeout: float,
    cwd: Path = ROOT,
    log: str | None = None,
    echo: bool = False,
    env: dict[str, str] | None = None,
    on_start: Callable[[subprocess.Popen[bytes]], None] | None = None,
) -> Result:
    """One start of cmd for run(): its output, exit code, timeout and seconds."""
    started = time.monotonic()
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env={**os.environ, **(env or {})},
            **group_kwargs(),  # type: ignore[arg-type]
        )
    except FileNotFoundError as exc:
        raise Failure(f"cannot start {cmd[0]}: {exc}") from exc
    if on_start is not None:
        on_start(proc)
    chunks: list[str] = []

    def pump() -> None:
        assert proc.stdout is not None
        for raw in iter(proc.stdout.readline, b""):
            text = raw.decode("utf-8", errors="replace").replace("\r\n", "\n")
            chunks.append(text)
            if echo:
                sys.stdout.write(text)
                sys.stdout.flush()

    reader = threading.Thread(target=pump, daemon=True)
    reader.start()
    timed_out = False
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        kill_tree(proc)
    reader.join(timeout=5)
    if proc.stdout is not None and not reader.is_alive():
        proc.stdout.close()
    out = "".join(chunks)
    if log:
        ensure_out()
        (LOGS / f"{log}.log").write_text(out, encoding="utf-8")
    return Result(proc.returncode, out, timed_out, time.monotonic() - started)


def version_tuple(text: str) -> tuple[int, ...]:
    """First dotted number in text as a tuple: 'gh version 2.101.0 (x)' -> (2, 101, 0)."""
    match = re.search(r"(\d+(?:\.\d+)+)", text)
    if not match:
        return ()
    return tuple(int(part) for part in match.group(1).split("."))


# --- locating tools -------------------------------------------------------------------------------


def godot_bin() -> str | None:
    value = os.environ.get("GODOT_BIN")
    if value:
        return value if Path(value).is_file() else None
    return shutil.which("godot")


def gdtoolkit_exe(name: str) -> str | None:
    folder = os.environ.get("GDTOOLKIT_DIR")
    if folder:
        for candidate in (name, f"{name}.exe"):
            path = Path(folder) / candidate
            if path.is_file():
                return str(path)
    return shutil.which(name)


def git_bash() -> str | None:
    """Git for Windows bash (hooks need it). On other systems any bash."""
    if not IS_WINDOWS:
        return shutil.which("bash")
    git = shutil.which("git")
    candidates = []
    if git:
        # <Git>\cmd\git.exe or <Git>\bin\git.exe or <Git>\mingw64\bin\git.exe
        for parent in Path(git).resolve().parents:
            candidates.append(parent / "bin" / "bash.exe")
    candidates.append(Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git" / "bin" / "bash.exe")
    for path in candidates:
        if path.is_file():
            return str(path)
    return None


_godot_checked: set[str] = set()


def check_godot_version(path: str, var: str = "GODOT_BIN") -> None:
    """Fail unless the Godot binary at path is the pinned version; each path is asked once per run."""
    if path in _godot_checked:
        return
    res = run([path, "--version"], timeout=60)
    version = res.out.strip().splitlines()[-1] if res.out.strip() else ""
    if not version.startswith(pins.GODOT_VERSION_PREFIX):
        raise Failure(
            f"wrong Godot version: {path} ({var}) reports '{version or res.out.strip()}', "
            f"the project is pinned to {pins.GODOT_VERSION_PREFIX}. "
            f"Download Godot {pins.GODOT} from "
            f"https://github.com/godotengine/godot/releases/tag/{pins.GODOT}-stable "
            f"and point {var} at its " + ("window exe." if var == "GODOT_GUI_BIN" else "console exe.")
        )
    _godot_checked.add(path)


def require_godot() -> str:
    """Return the Godot binary after checking its exact version once; fail fast otherwise."""
    path = godot_bin()
    if not path:
        where = os.environ.get("GODOT_BIN")
        raise Failure(
            (f"GODOT_BIN points to a missing file: {where}. " if where else "Godot not found. ")
            + f"Set GODOT_BIN to the Godot {pins.GODOT} console exe (env in ~/.claude/settings.json)"
            + ("." if where else ", or put `godot` on PATH.")
        )
    check_godot_version(path)
    ensure_user_dir()
    return path


def godot(
    args: list[str],
    *,
    timeout: float,
    log: str,
    echo: bool = False,
    env: dict[str, str] | None = None,
    on_start: Callable[[subprocess.Popen[bytes]], None] | None = None,
) -> Result:
    """Run the pinned Godot on this project. Never pass a bare -d: it hangs on script errors."""
    exe = require_godot()
    cmd = [exe, "--no-header", "--path", str(ROOT), *args]
    return run(cmd, timeout=timeout, log=log, echo=echo, env=env, on_start=on_start)


# --- user:// (#182) -------------------------------------------------------------------------------
# Godot puts user:// (settings, saves, replays, GdUnit4's user://tmp) in a folder named after the project, so every
# checkout of "PrimeGame" shares one: two worktrees' test runs cleared each other's GdUnit4 files. A linked worktree
# (a task's under .claude/worktrees/, a scratch one) therefore gets a gitignored override.cfg that gives it a folder
# of its own; the main checkout (where the humans play and host) and a CI clone get none and keep Godot's default.
# Godot 4.7.2 joins custom_user_dir_name to the OS app-data folder (%APPDATA% on Windows, $XDG_DATA_HOME or
# ~/.local/share on Linux), and a name may hold "/": the folder goes next to the default one.
OVERRIDE = "override.cfg"
OVERRIDE_MARK = "; Written by the task runner (tools/runner/common.py, #182)"


def is_linked_worktree(root: Path | None = None) -> bool:
    """A worktree made by `git worktree add` has a .git file; the main checkout and a clone have a .git folder."""
    return ((root or ROOT) / ".git").is_file()


def project_name(root: Path | None = None) -> str:
    """application/config/name from project.godot (the name Godot's default user:// folder is called after)."""
    try:
        text = ((root or ROOT) / "project.godot").read_text(encoding="utf-8")
    except OSError:
        return "PrimeGame"
    match = re.search(r'^config/name="([^"]*)"', text, re.MULTILINE)
    return match.group(1) if match and match.group(1) else "PrimeGame"


def user_dir_name(root: Path | None = None, project: str | None = None) -> str:
    """A worktree's custom_user_dir_name: beside Godot's default folder, called after the project, the worktree's
    folder and a hash of its path (two clones may both have a worktree "182"). `project` names the project when the
    worktree's own project.godot is gone (worktree-done after a removal); by default it is read from `root`."""
    root = root or ROOT
    folder = re.sub(r"[^A-Za-z0-9._-]", "-", root.name) or "worktree"
    digest = hashlib.sha1(os.path.normcase(str(root.resolve())).encode("utf-8")).hexdigest()[:6]
    # Godot's own folder name: "godot" on Linux, "Godot" elsewhere (OS::get_godot_dir_name).
    return f"{'godot' if IS_LINUX else 'Godot'}/app_userdata/{project or project_name(root)}-{folder}-{digest}"


def override_text(root: Path | None = None) -> str:
    return (
        f"{OVERRIDE_MARK}: this worktree's own user://.\n"
        "; Gitignored. The main checkout has none and keeps Godot's default folder (docs/AGENT_WORKFLOW.md §11).\n"
        "[application]\n"
        "\n"
        "config/use_custom_user_dir=true\n"
        f'config/custom_user_dir_name="{user_dir_name(root)}"\n'
    )


def ensure_user_dir(root: Path | None = None) -> Path | None:
    """Write a linked worktree's override.cfg when it is missing or stale; returns its path (None in the main
    checkout or a clone, which keep the default user://). A hand-made override.cfg (without the runner's first line)
    is left alone, with a warning."""
    root = root or ROOT
    if not is_linked_worktree(root):
        return None
    path = root / OVERRIDE
    want = override_text(root)
    try:
        have = path.read_text(encoding="utf-8") if path.exists() else None
    except OSError:
        have = None
    if have == want:
        return path
    if have is not None and not have.startswith(OVERRIDE_MARK):
        warn(f"{path} was not written by the runner; this worktree may share user:// with the main checkout")
        return path
    path.write_text(want, encoding="utf-8", newline="\n")
    return path


def app_data_dir() -> Path | None:
    """The folder Godot joins custom_user_dir_name to, read as Godot reads it (OS_Windows / OS_LinuxBSD)."""
    if IS_WINDOWS:
        value = os.environ.get("APPDATA")
        return Path(value) if value else None
    if IS_LINUX:
        value = os.environ.get("XDG_DATA_HOME", "")
        if value and Path(value).is_absolute():
            return Path(value)
        home = os.environ.get("HOME")
        return Path(home) / ".local" / "share" if home else None
    return None


def worktree_user_dir(root: Path) -> Path | None:
    """Where a linked worktree's user:// lives on this machine (None for the main checkout or an unknown OS)."""
    base = app_data_dir()
    if base is None or not is_linked_worktree(root):
        return None
    return base / user_dir_name(root)


# The per-process mechanism: Godot reads the app-data folder from the environment on every start, so a process
# started with this variable set gets a user:// of its own under the given folder (whatever override.cfg names).
# Windows: APPDATA; Linux: XDG_DATA_HOME (it must be absolute). Probed on 4.7.2 (#182).
def app_data_var() -> str | None:
    if IS_WINDOWS:
        return "APPDATA"
    if IS_LINUX:
        return "XDG_DATA_HOME"
    return None


# --- the real app-data folder stays clean (#233) ----------------------------------------------------------------------
# A worktree's user:// folder outlives the worktree. Every run of `merge`, `merge-check --trial` and `mutants` (a
# scratch worktree) and every `selftest` (the throwaway projects of the runner tests that start Godot) left one in the
# real app-data folder: 62 by 2026-10-02 22:30 UTC, a new PrimeGame-182-<hash> with each verify. Now a scratch
# worktree takes its folder with it (remove_own_user_dir), and a runner test that starts Godot runs with the app-data
# variable pointed at a temporary folder (temp_app_data, through verify.starts_godot).
USER_DIR_RE = re.compile(r".+-[0-9a-f]{6}")


def user_dir_of(root: Path, project: str | None = None) -> Path | None:
    """Where the linked worktree at `root` keeps its user:// on this machine, also once git no longer lists it or its
    folder is gone (then `project` names the project). None on an OS the runner does not know."""
    base = app_data_dir()
    return None if base is None else base / user_dir_name(root, project)


def remove_folder(path: Path, attempts: int = 5, pause: float = 0.5) -> bool:
    """Delete a folder, retrying a few times: on Windows a Godot that has just exited can hold a file a moment
    longer. True when it is gone; a warning when it stays."""
    for attempt in range(attempts):
        try:
            shutil.rmtree(path)
            return True
        except FileNotFoundError:
            return True
        except OSError as exc:
            if attempt == attempts - 1:
                warn(f"kept {path} ({exc.strerror or exc}): a program may still have it open; delete it later")
                return False
            time.sleep(pause)
    return not path.exists()


def _delete_again(func, target, exc) -> None:  # type: ignore[no-untyped-def]
    """rmtree's error handler for force_rmtree. A refused delete (os.unlink, os.rmdir) is tried once more after adding
    the write bit to the path's mode. A path that vanished meanwhile counts as deleted. Every other error is raised,
    including a failed walk step (os.open, os.scandir, ...), which a retry with the path alone cannot redo."""
    error = exc[1] if isinstance(exc, tuple) else exc  # onerror (3.11) passes sys.exc_info(), onexc the exception
    try:
        if func not in (os.unlink, os.rmdir):
            raise error
        os.chmod(target, stat.S_IMODE(os.lstat(target).st_mode) | stat.S_IWRITE)  # S_IWRITE alone drops r and x
        func(target)
    except FileNotFoundError:
        if os.path.lexists(target):
            raise


def force_rmtree(path: Path | str) -> None:
    """Delete a folder that git made: git makes its object files read-only, and Windows refuses to delete those
    without a chmod. A path that vanishes meanwhile (a git process still tidying its object folders, #440) counts as
    deleted; every other error is raised. Used by mutants' scratch worktrees and the runner tests' temp repos (#453)."""
    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=_delete_again)
    else:
        shutil.rmtree(path, onerror=_delete_again)


def remove_own_user_dir(folder: Path | None) -> bool:
    """Delete a removed worktree's own user:// folder (a missing one is fine): only a `<project>-<folder>-<6 hex>`
    folder in app_userdata/ of the app-data folder, never Godot's default `<project>` folder (the main checkout's: the
    humans' settings and saves) nor this checkout's own. True when it removed one (the caller says so)."""
    if folder is None or not folder.is_dir():
        return False
    base = app_data_dir()
    own = user_dir_of(ROOT) if is_linked_worktree(ROOT) else None
    godot = "godot" if IS_LINUX else "Godot"
    if (
        base is None
        or os.path.normcase(str(folder.parent)) != os.path.normcase(str(base / godot / "app_userdata"))
        or not USER_DIR_RE.fullmatch(folder.name)
        or (own is not None and os.path.normcase(str(folder)) == os.path.normcase(str(own)))
    ):
        warn(f"kept {folder}: not a removed worktree's own user:// folder")
        return False
    return remove_folder(folder)


@contextmanager
def temp_app_data(prefix: str = "prime-app-data-") -> Iterator[Path | None]:
    """Point this process's app-data variable, and so the user:// of every Godot it starts from now on (and Godot's
    editor settings), at a fresh temporary folder; afterwards restore the variable and delete the folder. Runner tests
    that start Godot run inside one (verify.starts_godot). PYTHONUSERBASE keeps a Python child's user site-packages
    where they are (on Windows they live under APPDATA). Yields None, changing nothing, on an OS without one."""
    var = app_data_var()
    if var is None:
        yield None
        return
    folder = Path(tempfile.mkdtemp(prefix=prefix)).resolve()
    saved = {name: os.environ.get(name) for name in (var, "PYTHONUSERBASE")}
    os.environ.setdefault("PYTHONUSERBASE", site.getuserbase())
    os.environ[var] = str(folder)
    try:
        yield folder
    finally:
        for name, value in saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
        remove_folder(folder)


def git(*args: str, timeout: float = 60) -> Result:
    return run(["git", *args], timeout=timeout)


def git_status() -> set[str]:
    """Porcelain status lines (including untracked files) as a set, for before/after comparison."""
    res = git("status", "--porcelain", "--untracked-files=all")
    return {line for line in res.lines if line.strip()}


def gd_files() -> list[Path]:
    """All project .gd files outside addons/, tools/out/ and the scratch folder."""
    files: list[Path] = []
    for name in GD_DIRS:
        base = ROOT / name
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.gd")):
            rel = path.relative_to(ROOT).as_posix()
            if rel.startswith(("tools/out/", SCRATCH + "/")):
                continue
            files.append(path)
    return files


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()
