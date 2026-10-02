"""Shared helpers: paths, output, running processes with a hard timeout, locating tools."""

from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
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


def run(
    cmd: list[str],
    *,
    timeout: float,
    cwd: Path = ROOT,
    log: str | None = None,
    echo: bool = False,
    env: dict[str, str] | None = None,
) -> Result:
    """Run cmd with stdout+stderr merged, a hard timeout and a process-tree kill.

    The full output is also written to tools/out/logs/<log>.log when log is given.
    """
    started = time.monotonic()
    kwargs: dict[str, object] = {}
    if IS_WINDOWS:
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env={**os.environ, **(env or {})},
            **kwargs,  # type: ignore[arg-type]
        )
    except FileNotFoundError as exc:
        raise Failure(f"cannot start {cmd[0]}: {exc}") from exc
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
    return path


def godot(args: list[str], *, timeout: float, log: str, echo: bool = False) -> Result:
    """Run the pinned Godot on this project. Never pass a bare -d: it hangs on script errors."""
    exe = require_godot()
    return run([exe, "--no-header", "--path", str(ROOT), *args], timeout=timeout, log=log, echo=echo)


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
