"""Shared helpers: paths, output, running processes with a hard timeout, locating tools."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from . import pins

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tools" / "out"
LOGS = OUT / "logs"
# The gitignored folder for temporary files that must live under res:// (a probe test). The guard lets its deletes
# pass; full lint, check and test runs skip it, a run that names a path in it covers that path.
SCRATCH = "tests/scratch"
IS_WINDOWS = os.name == "nt"
IS_LINUX = sys.platform.startswith("linux")
IS_CI = os.environ.get("CI", "").lower() in ("1", "true", "yes")
# A Claude Code cloud session (#159): a headless Linux container set up by tools/cloud/setup.sh, like CI.
IS_CLOUD = os.environ.get("CLAUDE_CODE_REMOTE", "").lower() == "true"

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
) -> Result:
    """Run cmd with stdout+stderr merged, a hard timeout and a process-tree kill.

    The full output is also written to tools/out/logs/<log>.log when log is given. `on_start` gets the process once
    it runs (a caller running several at once keeps them, to stop them all on Ctrl+C).
    """
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


def user_dir_name(root: Path | None = None) -> str:
    """A worktree's custom_user_dir_name: beside Godot's default folder, called after the project, the worktree's
    folder and a hash of its path (two clones may both have a worktree "182")."""
    root = root or ROOT
    folder = re.sub(r"[^A-Za-z0-9._-]", "-", root.name) or "worktree"
    digest = hashlib.sha1(os.path.normcase(str(root.resolve())).encode("utf-8")).hexdigest()[:6]
    # Godot's own folder name: "godot" on Linux, "Godot" elsewhere (OS::get_godot_dir_name).
    return f"{'godot' if IS_LINUX else 'Godot'}/app_userdata/{project_name(root)}-{folder}-{digest}"


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
