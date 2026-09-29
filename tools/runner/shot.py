"""`shot <scene>`: render a scene in a real window and save a PNG the agent and the designer can look at.

Never headless and never minimized: in both cases Godot does not draw, RenderingServer.frame_post_draw never fires
and the script would hang (Phase A tests on vulkan, d3d12 and opengl3). The window opens off-screen at
--position -30000,-30000 so it does not cover the human's screen. Needs a desktop session, so CI never runs it.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

from .common import IS_CI, IS_WINDOWS, OUT, ROOT, Failure, ensure_out, godot, ok, say

SCRIPT = "res://tools/shot/shot.gd"
POSITION = "-30000,-30000"
SIZE_RE = re.compile(r"^[1-9][0-9]{1,4}x[1-9][0-9]{1,4}$")
TIMEOUT = 120
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def scene_res(name: str) -> str:
    rel = name.replace("\\", "/").removeprefix("res://").removeprefix("./")
    if not rel.endswith(".tscn") or ".." in Path(rel).parts or Path(rel).is_absolute():
        raise Failure(f"{name}: give a .tscn inside the project (repo-relative or res://)")
    if not (ROOT / rel).is_file():
        raise Failure(f"{name}: file not found")
    return f"res://{rel}"


def command(scene: str, png: Path, size: str, frames: int) -> list[str]:
    return ["--position", POSITION, "--resolution", size, "-s", SCRIPT, "--", scene, str(png), str(frames)]


def has_display() -> bool:
    if IS_CI:
        return False
    return IS_WINDOWS or bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def main(scene: str, out: str | None = None, size: str = "1280x720", frames: int = 10) -> int:
    say("shot")
    if not has_display():
        raise Failure("shot needs a desktop session with a GPU; CI and headless machines skip it")
    if not SIZE_RE.match(size):
        raise Failure(f"--size must look like 1280x720, not {size!r}")
    if not 1 <= frames <= 600:
        raise Failure("--frames must be between 1 and 600")
    res_path = scene_res(scene)
    ensure_out()
    png = Path(out).resolve() if out else OUT / "shots" / f"{Path(res_path).stem}.png"
    png.parent.mkdir(parents=True, exist_ok=True)
    if png.exists():
        png.unlink()
    res = godot(command(res_path, png, size, frames), timeout=TIMEOUT, log="shot")
    if res.timed_out:
        raise Failure(f"shot timed out after {TIMEOUT}s: the window never drew (log: tools/out/logs/shot.log)")
    errors = [line.removeprefix("SHOT error ") for line in res.lines if line.startswith("SHOT error ")]
    if errors or res.rc != 0:
        raise Failure("shot failed: " + ("; ".join(errors) or f"exit {res.rc} (log: tools/out/logs/shot.log)"))
    if not png.is_file() or not png.read_bytes().startswith(PNG_MAGIC):
        raise Failure(f"shot reported success but {png} is not a PNG (log: tools/out/logs/shot.log)")
    for line in res.lines:
        if line.startswith("SHOT framed: "):
            say(f"        {line.removeprefix('SHOT framed: ')}")
    ok(f"{res_path} -> {png} ({size}, {png.stat().st_size // 1024} KB)")
    say(f"SHOT {png}")
    say("shot: done. Read the PNG to check it, and show it to the human.")
    return 0
