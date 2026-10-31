"""The off-screen window of `shot`, `playcheck` and `run --offscreen` (#1141; docs/AGENT_WORKFLOW.md §11.4).

Godot 4.7.2 on Windows does not keep a window at `--position -30000,-30000` off-screen: DisplayServerWindows::
_create_window takes the primary screen when the requested rect is on no screen and clamps a windowed window's
client area into that screen's usable area, up to its far edge minus a third of the window's size. Every such window
opened at the top-left corner at its full size (measured: 1282x752 for 1.5 to 3.9 s per `shot`). Only a runtime
DisplayServer.window_set_position moves a window without that clamp.

So the window starts as one pixel asked far right and up (START): a third of one pixel is 0, so its client area opens
at (screen width, 0), just past the top-right corner, and its title bar above the screen. What stays on the screen is
the 1 px left border of its frame, 2 px tall at the corner, until place() runs (a window watcher, #1141: 0.5 to 0.8 s
for `shot` and `run --offscreen`, 3.7 and 4.9 s for the two windows of a `playcheck` started together). The window
keeps its title bar: no command-line flag makes a window borderless or unfocused, and the project settings that do
(display/window/size/borderless, no_focus) would change the game's own windows. Asked far right and down instead, the
title bar stood above the taskbar: 1x31 px on the screen.

The window script calls tools/offscreen/offscreen.gd place() first: it moves the window to -30000,-30000, grows it to
the size in ENV, makes it unfocusable at runtime (DisplayServer.WINDOW_FLAG_NO_FOCUS) and prints the OFFSCREEN line,
which problems() checks before the runner accepts the run. The window never keeps the foreground: tools/runner/focus.py
(#1505).
"""

from __future__ import annotations

import re

START = ["--position", "30000,-30000", "--resolution", "1x1"]
ENV = "PRIME_WINDOW"
SCRIPT = "res://tools/offscreen/offscreen.gd"
SIZE_RE = re.compile(r"^([1-9][0-9]{0,4})x([1-9][0-9]{0,4})$")
LINE_RE = re.compile(r"OFFSCREEN window (-?\d+),(-?\d+) (\d+)x(\d+) screens (\S+)")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def env(size: str) -> dict[str, str]:
    """The environment that tells place() the window's real size (<w>x<h>)."""
    if not SIZE_RE.match(size):
        raise ValueError(f"window size {size!r}, not <w>x<h>")
    return {ENV: size}


def _overlap(a: tuple[int, ...], b: tuple[int, ...]) -> bool:
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def problems(lines: list[str]) -> list[str]:
    """Why a window run's output does not prove its window stayed off every screen: no OFFSCREEN line (the script
    never placed its window), or a line whose window rect meets one of the screens it lists. Empty: proven."""
    found = [m.groups() for m in (LINE_RE.search(ANSI_RE.sub("", line)) for line in lines) if m]
    if not found:
        return [f"no OFFSCREEN line: the window script never moved its window off-screen ({SCRIPT} place())"]
    out = []
    for x, y, w, h, screens in found:
        rect = (int(x), int(y), int(w), int(h))
        for i, screen in enumerate(screens.split(";")):
            try:
                s = tuple(int(v) for v in screen.split(","))
            except ValueError:
                s = ()
            if len(s) != 4:
                out.append(f"screen {i} of the OFFSCREEN line is not <x>,<y>,<w>,<h>: {screen!r}")
            elif _overlap(rect, s):
                out.append(f"the {w}x{h} window at {x},{y} is on screen {i} ({s[2]}x{s[3]} at {s[0]},{s[1]})")
    return out


def problem(lines: list[str]) -> str:
    """problems() as one line for a failure message, or ''."""
    found = problems(lines)
    return "" if not found else "not proven off-screen (#1141): " + "; ".join(found[:3])
