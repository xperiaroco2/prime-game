"""Window runs never keep the foreground on Windows (#1505; docs/AGENT_WORKFLOW.md §11.4).

The off-screen windows of `shot`, `playcheck` and `run --offscreen` (tools/runner/offscreen.py) are for nobody to look
at, yet each one took the foreground and threw the engineer out of the game he was playing on this PC. Godot 4.7.2
shows its main window in Main::setup2, before any script runs, with ShowWindow(SW_SHOW) and then
SetForegroundWindow (DisplayServerWindows::show_window; only a window with WINDOW_FLAG_NO_FOCUS from the project's
display/window/size/no_focus is shown with SW_SHOWNA, and that setting would change the game's own windows). So three
layers, each a no-op off Windows:

- startup(): the process starts with STARTUPINFO.wShowWindow = SW_SHOWNOACTIVATE (never minimized: a minimized
  window draws nothing). Windows uses it for a process's first ShowWindow; the console exe (GODOT_BIN) starts
  godot.exe without passing it on (console_wrapper_windows.cpp), so it counts only for an exe started directly: the
  off-screen windows of shot, playcheck and run --offscreen come from GODOT_GUI_BIN (launch.gui_exe()).
- tools/offscreen/offscreen.gd place() sets DisplayServer.WINDOW_FLAG_NO_FOCUS once the window is off-screen, so the
  window never activates again (Windows: WS_EX_NOACTIVATE, SWP_NOACTIVATE).
- Keeper: records the foreground window before the run and, while it runs, hands the foreground back at once
  whenever a window of the run's process tree took it (AttachThreadInput to the thread that holds it, then
  SetForegroundWindow: a background process may not take the foreground on its own). A window of any other process
  (the human switching apps himself) is left alone.

The hard guarantee while the engineer plays is gaming mode (tools/runner/gaming.py): no window run starts at all.
"""

from __future__ import annotations

import subprocess
import threading
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from typing import Protocol

from .common import IS_WINDOWS, say

SW_SHOWNOACTIVATE = 4
STARTF_USESHOWWINDOW = 0x00000001
POLL_SECONDS = 0.02


def startup() -> dict[str, object]:
    """Popen arguments that start a window process without activating its first window (Windows; else none)."""
    if not IS_WINDOWS:
        return {}
    info = subprocess.STARTUPINFO()  # type: ignore[attr-defined]
    info.dwFlags |= STARTF_USESHOWWINDOW
    info.wShowWindow = SW_SHOWNOACTIVATE
    return {"startupinfo": info}


class Desktop(Protocol):
    """What the Keeper needs of the desktop (Win32 through ctypes; a fake in the tests)."""

    def foreground(self) -> int: ...

    def owner(self, window: int) -> int: ...

    def descendants(self, roots: Iterable[int]) -> set[int]: ...

    def give(self, window: int) -> bool: ...


class Win32Desktop:
    """The Win32 calls, through ctypes: no new dependency."""

    def __init__(self) -> None:
        import ctypes
        from ctypes import wintypes

        self._ctypes = ctypes
        self._wintypes = wintypes
        user32 = ctypes.WinDLL("user32", use_last_error=True)  # type: ignore[attr-defined]
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)  # type: ignore[attr-defined]
        user32.GetForegroundWindow.restype = wintypes.HWND
        user32.GetForegroundWindow.argtypes = []
        user32.GetWindowThreadProcessId.restype = wintypes.DWORD
        user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        user32.SetForegroundWindow.restype = wintypes.BOOL
        user32.SetForegroundWindow.argtypes = [wintypes.HWND]
        user32.IsWindow.restype = wintypes.BOOL
        user32.IsWindow.argtypes = [wintypes.HWND]
        user32.AttachThreadInput.restype = wintypes.BOOL
        user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
        user32.IsGUIThread.restype = wintypes.BOOL
        user32.IsGUIThread.argtypes = [wintypes.BOOL]
        kernel32.GetCurrentThreadId.restype = wintypes.DWORD
        kernel32.GetCurrentThreadId.argtypes = []
        kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
        kernel32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
        kernel32.CloseHandle.argtypes = [wintypes.HANDLE]

        class Entry(ctypes.Structure):  # PROCESSENTRY32W
            _fields_ = [
                ("dwSize", wintypes.DWORD),
                ("cntUsage", wintypes.DWORD),
                ("th32ProcessID", wintypes.DWORD),
                ("th32DefaultHeapID", ctypes.c_size_t),
                ("th32ModuleID", wintypes.DWORD),
                ("cntThreads", wintypes.DWORD),
                ("th32ParentProcessID", wintypes.DWORD),
                ("pcPriClassBase", wintypes.LONG),
                ("dwFlags", wintypes.DWORD),
                ("szExeFile", wintypes.WCHAR * 260),
            ]

        for walk in (kernel32.Process32FirstW, kernel32.Process32NextW):
            walk.restype = wintypes.BOOL
            walk.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
        self._entry = Entry
        self._user32 = user32
        self._kernel32 = kernel32

    def foreground(self) -> int:
        return int(self._user32.GetForegroundWindow() or 0)

    def owner(self, window: int) -> int:
        pid = self._wintypes.DWORD(0)
        self._user32.GetWindowThreadProcessId(window, self._ctypes.byref(pid))
        return int(pid.value)

    def descendants(self, roots: Iterable[int]) -> set[int]:
        """The roots and every process they started, and those started (the console exe starts godot.exe)."""
        ctypes, wintypes = self._ctypes, self._wintypes
        found = set(roots)
        snapshot = self._kernel32.CreateToolhelp32Snapshot(0x00000002, 0)  # TH32CS_SNAPPROCESS
        if not snapshot or snapshot == wintypes.HANDLE(-1).value:
            return found
        pairs: list[tuple[int, int]] = []
        try:
            entry = self._entry()
            entry.dwSize = ctypes.sizeof(entry)
            more = self._kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
            while more:
                pairs.append((int(entry.th32ProcessID), int(entry.th32ParentProcessID)))
                more = self._kernel32.Process32NextW(snapshot, ctypes.byref(entry))
        finally:
            self._kernel32.CloseHandle(snapshot)
        return tree(found, pairs)

    def give(self, window: int) -> bool:
        """Make `window` the foreground again: attach this thread's input to the thread that holds the foreground
        (the run's window), which may hand it on, then SetForegroundWindow."""
        if not self._user32.IsWindow(window):
            return False
        self._user32.IsGUIThread(True)  # a message queue: AttachThreadInput needs one on both threads
        me = int(self._kernel32.GetCurrentThreadId())
        holder = int(self._user32.GetWindowThreadProcessId(self._user32.GetForegroundWindow(), None) or 0)
        attached = bool(holder and holder != me and self._user32.AttachThreadInput(me, holder, True))
        try:
            return bool(self._user32.SetForegroundWindow(window))
        finally:
            if attached:
                self._user32.AttachThreadInput(me, holder, False)


def tree(roots: Iterable[int], pairs: Iterable[tuple[int, int]]) -> set[int]:
    """`roots` and their descendants, from (pid, parent pid) pairs."""
    children: dict[int, list[int]] = {}
    for pid, parent in pairs:
        if pid != parent:
            children.setdefault(parent, []).append(pid)
    found = set(roots)
    todo = list(found)
    while todo:
        for child in children.get(todo.pop(), []):
            if child not in found:
                found.add(child)
                todo.append(child)
    return found


@dataclass
class Keeper:
    """While a window run goes on: whenever a window of its processes holds the foreground, give it back to the
    window that held it before the run. Use as a context manager; pass watch() as the run's on_start."""

    desktop: Desktop | None = None
    poll: float = POLL_SECONDS
    out: Callable[[str], None] = say
    before: int = 0
    taken: int = 0
    given: int = 0
    pids: set[int] = field(default_factory=set)
    _stop: threading.Event = field(default_factory=threading.Event)
    _thread: threading.Thread | None = None
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def __post_init__(self) -> None:
        if self.desktop is None and IS_WINDOWS:
            try:
                self.desktop = Win32Desktop()
            except (OSError, AttributeError):
                self.desktop = None

    def watch(self, proc: subprocess.Popen[bytes]) -> None:
        """An on_start callback: the process (and the processes it starts) belong to the run."""
        with self._lock:
            self.pids.add(proc.pid)

    def check(self) -> None:
        """One look: a window of the run holds the foreground -> give it back."""
        desktop = self.desktop
        if desktop is None or not self.before:
            return
        now = desktop.foreground()
        if not now or now == self.before:
            return
        with self._lock:
            roots = set(self.pids)
        if not roots or desktop.owner(now) not in desktop.descendants(roots):
            return
        self.taken += 1
        if desktop.give(self.before):
            self.given += 1

    def _loop(self) -> None:
        while not self._stop.wait(self.poll):
            try:
                self.check()
            except OSError:
                pass

    def __enter__(self) -> Keeper:
        if self.desktop is not None:
            self.before = self.desktop.foreground()
            if self.before:
                self._thread = threading.Thread(target=self._loop, name="focus-keeper", daemon=True)
                self._thread.start()
        return self

    def __exit__(self, *exc: object) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2)
            try:
                self.check()
            except OSError:
                pass
        if self.taken:
            missed = self.taken - self.given
            self.out(
                f"        focus: a window of the run took the foreground {self.taken} time(s); handed back "
                f"{self.given}" + (f", {missed} refused by Windows (#1505)" if missed else " (#1505)")
            )


def keep() -> Keeper:
    """A Keeper on this desktop (it does nothing off Windows or without a foreground window)."""
    return Keeper()

