"""`run <scene.tscn | script.gd>`: run a scene or a script with the pinned Godot (docs/AGENT_WORKFLOW.md §11).

Headless runs use GODOT_BIN (the console exe); windowed runs use GODOT_GUI_BIN, else GODOT_BIN. Every instance
gets a hard timeout that kills its process tree and a log tools/out/logs/run/<name>-<i>.log. A run fails when any
instance exits non-zero, times out, or prints an engine error line: Godot keeps running and exits 0 after a
SCRIPT ERROR or a push_error, so the exit code alone would hide them.
"""

from __future__ import annotations

import contextlib
import os
import re
import threading
from dataclasses import dataclass
from pathlib import Path

from . import focus, gaming, shot
from . import offscreen as offscreen_window
from .check import ensure_import
from .common import (
    LOGS,
    ROOT,
    Failure,
    Result,
    bad,
    check_godot_version,
    ensure_out,
    ensure_user_dir,
    not_started,
    ok,
    rel,
    require_godot,
    run,
    say,
    start_problem,
    warn,
)

EXTENSIONS = (".tscn", ".scn", ".gd")
AUDIO = ("dummy", "default")
DEFAULT_SECONDS = 60
MAX_SECONDS = 3600
MAX_INSTANCES = 8
# Each instance also gets its 1-based number here, so N copies with the same arguments can still differ.
INSTANCE_ENV = "PRIME_INSTANCE"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
ERROR_RE = re.compile(r"^(?:USER )?(?:SCRIPT |SHADER )?ERROR: ")
SHOWN_ERRORS = 3
# `run --offscreen`: a scene runs under this script, which places the window off-screen first (#1141), and its
# window gets project.godot's window_width_override and window_height_override, as a plain window would.
OFFSCREEN_SCENE = "res://tools/offscreen/offscreen_scene.gd"
OFFSCREEN_SCENE_ENV = "PRIME_OFFSCREEN_SCENE"
OFFSCREEN_SIZE = "1152x648"


def target_res(name: str) -> str:
    """A repo-relative or res:// path of a scene or script -> a checked res:// path."""
    text = name.replace("\\", "/").removeprefix("res://").removeprefix("./")
    if Path(text).is_absolute() or ".." in Path(text).parts or text.startswith(("tools/out/", ".godot/")):
        raise Failure(f"{name}: give a scene or script inside the project (repo-relative or res://)")
    if not text.endswith(EXTENSIONS):
        raise Failure(f"{name}: run takes a scene (.tscn, .scn) or a script (.gd, extends SceneTree or MainLoop)")
    if not (ROOT / text).is_file():
        raise Failure(f"{name}: file not found")
    return f"res://{text}"


def command(
    exe: str,
    project: Path,
    target: str,
    *,
    headless: bool,
    offscreen: bool,
    audio: str,
    user_args: list[str],
    window: list[str] | None = None,
    engine_args: list[str] | None = None,
) -> list[str]:
    """The Godot command line of one instance; `window` only with a window.

    `offscreen`: the window starts as offscreen.START; the window script places it off-screen (a scene target runs
    under OFFSCREEN_SCENE, which takes the scene from offscreen_env()). `engine_args` (such as `--fixed-fps 60`) go to
    the engine, before the target; `user_args` to the game, after `--`.
    """
    cmd = [exe, "--no-header", "--path", str(project)]
    if headless:
        # --headless also forces the Dummy audio driver; the display driver alone keeps real audio.
        cmd += ["--headless"] if audio == "dummy" else ["--display-driver", "headless"]
    else:
        if offscreen:
            cmd += offscreen_window.START
        cmd += window or []
        if audio == "dummy":
            cmd += ["--audio-driver", "Dummy"]
    cmd += engine_args or []
    if target.endswith(".gd"):
        cmd += ["-s", target]
    else:
        cmd += ["-s", OFFSCREEN_SCENE] if offscreen and not headless else [target]
    if user_args:
        cmd += ["--", *user_args]
    return cmd


def offscreen_env(target: str, size: str = OFFSCREEN_SIZE) -> dict[str, str]:
    """The environment of an off-screen instance: its window's size, and a scene target for OFFSCREEN_SCENE."""
    env = offscreen_window.env(size)
    if not target.endswith(".gd"):
        env[OFFSCREEN_SCENE_ENV] = target
    return env


def shown(env: dict[str, str] | None) -> str:
    """An instance's added environment as `NAME=value ` words before the command it is echoed with."""
    return "".join(f"{k}={v} " for k, v in (env or {}).items())


def error_lines(lines: list[str], limit: int = SHOWN_ERRORS) -> tuple[int, list[str]]:
    """(number of engine error lines, the first `limit` of them).

    Each shown error keeps the `at:` line and the innermost GDScript frame (`[0] …`) of the indented block
    Godot prints below it: together they name the engine function and the script line.
    """
    clean = [ANSI_RE.sub("", line) for line in lines]
    found = [i for i, line in enumerate(clean) if ERROR_RE.match(line)]
    shown = []
    for i in found[:limit]:
        shown.append(clean[i])
        for line in clean[i + 1 :]:
            if not line.startswith((" ", "\t")):
                break
            if line.lstrip().startswith(("at: ", "[0] ")):
                shown.append(line)
    return len(found), shown


@dataclass
class Instance:
    number: int
    log: Path
    result: Result
    seconds: int
    # Its window started off-screen: the run must print a placed OFFSCREEN line (offscreen.problems, #1141).
    offscreen: bool = False

    @property
    def errors(self) -> tuple[int, list[str]]:
        return error_lines(self.result.lines)

    @property
    def problem(self) -> str:
        """Why this instance failed, or '' when it passed."""
        if self.result.timed_out:
            return f"timed out after {self.seconds}s and was killed"
        # No seconds: run() judged each start's life itself, and a restart's result counts from the first start.
        if not_started(self.result.rc, self.result.out):
            return start_problem(self.result.rc, self.result.restarted)
        if self.result.rc != 0:
            return f"exited {self.result.rc}"
        count = self.errors[0]
        if count:
            return f"exited 0 but printed {count} engine error line{'s' if count > 1 else ''}"
        if self.offscreen:
            return offscreen_window.problem(self.result.lines)
        return ""


def launch(
    cmds: list[list[str]],
    *,
    seconds: int,
    log_dir: Path,
    name: str,
    cwd: Path = ROOT,
    env: dict[str, str] | None = None,
    offscreen: bool = False,
) -> list[Instance]:
    """Start every command at once, wait for all of them and write one log each. One instance echoes live.

    `env` is added to each instance's environment; `offscreen`: each must prove its window stayed off-screen, and
    each starts without activating its window and never keeps the foreground (focus, #1505)."""
    log_dir.mkdir(parents=True, exist_ok=True)
    own_log = re.compile(rf"{re.escape(name)}-\d+\.log")  # never another target's logs, such as lobby-test-1.log
    for old in log_dir.iterdir():
        if own_log.fullmatch(old.name):
            old.unlink()
    results: dict[int, Result] = {}
    failures: list[Failure] = []
    keeper = focus.keep() if offscreen else None

    def one(number: int, cmd: list[str]) -> None:
        own = {**(env or {}), INSTANCE_ENV: str(number)}
        try:
            # One of several instances (one ENet game on one port) is not restarted: its late start fails the others.
            results[number] = run(
                cmd,
                timeout=seconds,
                cwd=cwd,
                echo=len(cmds) == 1,
                env=own,
                restart=len(cmds) == 1,
                on_start=keeper.watch if keeper is not None else None,
                background=offscreen,
            )
        except Failure as exc:  # the exe could not start: report it once, after the others finished
            failures.append(exc)

    threads = [threading.Thread(target=one, args=(i, cmd)) for i, cmd in enumerate(cmds, start=1)]
    with keeper if keeper is not None else contextlib.nullcontext():
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
    if failures:
        raise failures[0]
    instances = []
    for number in range(1, len(cmds) + 1):
        log = log_dir / f"{name}-{number}.log"
        log.write_text(results[number].out, encoding="utf-8")
        instances.append(Instance(number, log, results[number], seconds, offscreen))
    return instances


def report(label: str, instances: list[Instance]) -> int:
    """Print one line per instance (plus the first error lines of a failed one); 1 when any failed."""
    failed = 0
    for inst in instances:
        where = rel(inst.log) if inst.log.is_relative_to(ROOT) else str(inst.log)
        head = f"{label} #{inst.number}"
        if inst.problem:
            failed += 1
            bad(f"{head}: {inst.problem} (log: {where})", "\n".join(inst.errors[1]))
        else:
            ok(f"{head}: exit 0 in {inst.result.seconds:.1f}s, no engine errors (log: {where})")
    say(f"run: FAILED ({failed} of {len(instances)})" if failed else "run: passed")
    return 1 if failed else 0


def gui_exe() -> str:
    """GODOT_GUI_BIN when set, else GODOT_BIN (the console exe opens windows too)."""
    gui = os.environ.get("GODOT_GUI_BIN")
    if not gui:
        warn("GODOT_GUI_BIN is not set; the window comes from GODOT_BIN")
        return require_godot()
    if not Path(gui).is_file():
        raise Failure(f"GODOT_GUI_BIN points to a missing file: {gui} (env in ~/.claude/settings.json)")
    check_godot_version(gui, "GODOT_GUI_BIN")
    ensure_user_dir()  # require_godot does it for the console exe
    return gui


def main(
    target: str,
    *,
    headless: bool = False,
    offscreen: bool = False,
    seconds: int = DEFAULT_SECONDS,
    instances: int = 1,
    audio: str = "dummy",
    user_args: list[str] | None = None,
    engine_args: list[str] | None = None,
    log_name: str | None = None,
) -> int:
    say("run")
    if not headless:
        gaming.refuse_windows("run (without --headless)")
    if headless and offscreen:
        raise Failure("--offscreen opens a real window; drop --headless, or drop --offscreen")
    if not 1 <= seconds <= MAX_SECONDS:
        raise Failure(f"--seconds must be between 1 and {MAX_SECONDS}")
    if not 1 <= instances <= MAX_INSTANCES:
        raise Failure(f"--instances must be between 1 and {MAX_INSTANCES}")
    if audio not in AUDIO:
        raise Failure(f"--audio must be one of {', '.join(AUDIO)}")
    res_path = target_res(target)
    if not headless and not shot.has_display():
        raise Failure("a window needs a desktop session; add --headless (CI and headless machines)")
    exe = require_godot() if headless else gui_exe()
    ensure_out()
    ensure_import()
    cmd = command(
        exe,
        ROOT,
        res_path,
        headless=headless,
        offscreen=offscreen,
        audio=audio,
        user_args=user_args or [],
        engine_args=engine_args,
    )
    off = offscreen and not headless
    env = offscreen_env(res_path) if off else None
    # The environment is part of the command: by hand, without PRIME_WINDOW the window script fails at once.
    say(f"        {shown(env)}{' '.join(cmd[1:])}" + (f"  x{instances}" if instances > 1 else ""))
    name = log_name or Path(res_path).stem
    results = launch(
        [cmd] * instances,
        seconds=seconds,
        log_dir=LOGS / "run",
        name=name,
        env=env,
        offscreen=off,
    )
    return report(Path(res_path).name, results)
