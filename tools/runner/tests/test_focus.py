"""Window runs never keep the foreground (#1505): the process tree, the Keeper on a fake desktop, which runs start
without activation, and one opt-in run of a real `shot` beside a foreground window (WindowFocusTest).

WindowFocusTest opens windows, so it runs only on Windows with PRIME_FOCUS_TEST=1 and gaming mode off; from PowerShell
in the repo: `$env:PRIME_FOCUS_TEST = '1'; Set-Location tools; & $env:PYTHON_BIN -m unittest
runner.tests.test_focus.WindowFocusTest; Set-Location ..; Remove-Item Env:PRIME_FOCUS_TEST`.
"""

import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from collections.abc import Iterable
from pathlib import Path
from unittest import mock

from runner import common, focus, gaming, hostjoin, launch, playcheck, shot
from runner.common import IS_WINDOWS, ROOT, Failure, Result
from runner.tests import REAL_GAMING_FILE

PLACED = "OFFSCREEN window -30008,-30031 1296x759 screens 0,0,2560,1440 ticks 990\n"
OPT_IN = "PRIME_FOCUS_TEST"


class FakeDesktop:
    """Windows 1 (the human's game, pid 10) and 2 (the run's window, pid 21: a child of the run's pid 20)."""

    def __init__(self, front: int = 1, give_works: bool = True) -> None:
        self.front = front
        self.give_works = give_works
        self.owners = {1: 10, 2: 21, 3: 30}
        self.given: list[int] = []
        self.snapshots = 0

    def foreground(self) -> int:
        return self.front

    def owner(self, window: int) -> int:
        return self.owners.get(window, 0)

    def descendants(self, roots: Iterable[int]) -> set[int]:
        self.snapshots += 1
        return focus.tree(roots, [(20, 5), (21, 20), (30, 4)])

    def give(self, window: int) -> bool:
        self.given.append(window)
        if self.give_works:
            self.front = window
        return self.give_works


def proc(pid: int) -> subprocess.Popen[bytes]:
    fake = mock.Mock(spec=subprocess.Popen)
    fake.pid = pid
    return fake


class TreeTest(unittest.TestCase):
    def test_the_roots_and_their_descendants(self) -> None:
        pairs = [(20, 5), (21, 20), (22, 21), (30, 4), (0, 0)]
        self.assertEqual(focus.tree([20], pairs), {20, 21, 22})
        self.assertEqual(focus.tree([99], pairs), {99})


class StartupTest(unittest.TestCase):
    def test_no_activation_on_windows_only(self) -> None:
        kwargs = focus.startup()
        if not IS_WINDOWS:
            self.assertEqual(kwargs, {})
            return
        info = kwargs["startupinfo"]
        self.assertTrue(info.dwFlags & focus.STARTF_USESHOWWINDOW)  # type: ignore[attr-defined]
        self.assertEqual(info.wShowWindow, focus.SW_SHOWNOACTIVATE)  # type: ignore[attr-defined]


class KeeperTest(unittest.TestCase):
    def keeper(self, desktop: FakeDesktop) -> tuple[focus.Keeper, list[str]]:
        said: list[str] = []
        return focus.Keeper(desktop=desktop, poll=0.001, out=said.append), said

    def test_a_window_of_the_run_gives_the_foreground_back(self) -> None:
        desktop = FakeDesktop()
        keeper, said = self.keeper(desktop)
        with keeper:
            keeper.watch(proc(20))
            desktop.front = 2  # godot.exe, started by the console exe the runner started
            deadline = time.monotonic() + 5
            while desktop.front != 1 and time.monotonic() < deadline:
                time.sleep(0.005)
        self.assertEqual(desktop.front, 1)
        self.assertEqual(desktop.given[:1], [1])
        self.assertEqual((keeper.taken, keeper.given), (1, 1))
        self.assertIn("took the foreground 1 time(s); handed back 1", said[0])

    def test_a_window_of_another_process_is_left_alone(self) -> None:
        desktop = FakeDesktop()
        keeper, said = self.keeper(desktop)
        with keeper:
            keeper.watch(proc(20))
            desktop.front = 3  # the human switched to another app himself
            time.sleep(0.05)
        self.assertEqual(desktop.front, 3)
        self.assertEqual(desktop.given, [])
        self.assertEqual(said, [])

    def test_the_last_look_at_the_end_still_gives_it_back(self) -> None:
        desktop = FakeDesktop()
        keeper, _ = self.keeper(desktop)
        keeper.poll = 3600  # the loop never looks: only __exit__'s last check
        with keeper:
            keeper.watch(proc(20))
            desktop.front = 2
        self.assertEqual(desktop.front, 1)

    def test_a_refused_hand_back_is_reported(self) -> None:
        desktop = FakeDesktop(give_works=False)
        keeper, said = self.keeper(desktop)
        keeper.poll = 3600
        with keeper:
            keeper.watch(proc(20))
            desktop.front = 2
        self.assertEqual((keeper.taken, keeper.given), (1, 0))
        self.assertIn("1 refused by Windows", said[0])

    def test_after_the_human_switched_apps_the_foreground_goes_back_to_his_new_app(self) -> None:
        desktop = FakeDesktop()
        keeper, _ = self.keeper(desktop)
        keeper.poll = 3600  # only the checks this test makes
        with keeper:
            keeper.watch(proc(20))
            desktop.front = 3  # he alt-tabbed from the game (1) to another app (3)
            keeper.check()
            desktop.front = 2  # then a window of the run took the foreground
            keeper.check()
            self.assertEqual((desktop.front, desktop.given), (3, [3]))

    def test_another_app_in_front_costs_one_process_snapshot_not_one_per_look(self) -> None:
        desktop = FakeDesktop()
        keeper, _ = self.keeper(desktop)
        keeper.poll = 3600
        with keeper:
            keeper.watch(proc(20))
            desktop.front = 3
            for _ in range(50):
                keeper.check()
            desktop.front = 2
            for _ in range(50):
                keeper.check()
        self.assertEqual(desktop.snapshots, 2)  # window 3 once, window 2 once

    def test_a_steal_that_windows_keeps_refusing_to_hand_back_counts_once(self) -> None:
        desktop = FakeDesktop(give_works=False)
        keeper, said = self.keeper(desktop)
        keeper.poll = 3600
        with keeper:
            keeper.watch(proc(20))
            desktop.front = 2
            for _ in range(50):
                keeper.check()
        self.assertEqual((keeper.taken, keeper.given), (1, 0))
        self.assertEqual(len(desktop.given), 51)  # it keeps trying: 50 looks and the last one at the end
        self.assertIn("took the foreground 1 time(s); handed back 0, 1 refused by Windows", said[0])

    def test_a_second_steal_after_a_hand_back_counts_again(self) -> None:
        desktop = FakeDesktop()
        keeper, said = self.keeper(desktop)
        keeper.poll = 3600
        with keeper:
            keeper.watch(proc(20))
            for _ in range(2):
                desktop.front = 2
                keeper.check()
        self.assertEqual((keeper.taken, keeper.given, desktop.front), (2, 2, 1))
        self.assertIn("took the foreground 2 time(s); handed back 2", said[0])

    def test_no_foreground_window_before_the_run_does_nothing(self) -> None:
        desktop = FakeDesktop(front=0)
        keeper, said = self.keeper(desktop)
        with keeper:
            keeper.watch(proc(20))
            desktop.front = 2
        self.assertIsNone(keeper._thread)
        self.assertEqual((desktop.front, desktop.given, said), (2, [], []))

    def test_off_windows_it_does_nothing(self) -> None:
        with mock.patch.object(focus, "IS_WINDOWS", False):
            keeper = focus.keep()
        self.assertIsNone(keeper.desktop)
        with keeper:
            keeper.watch(proc(20))
        self.assertEqual(keeper.taken, 0)


class Refused(Exception):
    pass


class WhichRunsStartInTheBackgroundTest(unittest.TestCase):
    """Only the off-screen windows start without activation and are watched; the rest start as before."""

    def setUp(self) -> None:
        patched = mock.patch.object(focus, "startup", return_value={"startupinfo": "no-activate"})
        patched.start()
        self.addCleanup(patched.stop)

    def popen_kwargs(self, call: object) -> dict[str, object]:
        seen: dict[str, object] = {}

        def fake_popen(*_args: object, **kwargs: object) -> None:
            seen.update(kwargs)
            raise FileNotFoundError("stub")

        with mock.patch.object(subprocess, "Popen", fake_popen), self.assertRaises(Failure):
            call()  # type: ignore[operator]
        return seen

    def test_run_passes_the_startup_info_only_for_a_background_window(self) -> None:
        once = lambda background: lambda: common._run_once(["g"], timeout=1, background=background)  # noqa: E731
        self.assertEqual(self.popen_kwargs(once(True)).get("startupinfo"), "no-activate")
        self.assertNotIn("startupinfo", self.popen_kwargs(once(False)))

    def test_a_background_part_of_a_session_starts_without_activation(self) -> None:
        part = hostjoin.Part("window 1", [], cmd=["g"], background=True)
        self.assertEqual(self.popen_kwargs(lambda: hostjoin.start(part)).get("startupinfo"), "no-activate")
        plain = hostjoin.Part("host", [], cmd=["g"])
        self.assertNotIn("startupinfo", self.popen_kwargs(lambda: hostjoin.start(plain)))

    def test_playcheck_windows_are_background_parts_and_its_bots_are_not(self) -> None:
        parts = [hostjoin.Part("window 1", []), hostjoin.Part("window 2", []), hostjoin.Part("bots", [])]
        playcheck.set_commands(parts, "godot.exe")
        self.assertEqual([p.background for p in parts], [True, True, False])

    def test_playcheck_windows_come_from_the_window_exe_and_its_bots_from_the_console_exe(self) -> None:
        # The console exe starts godot.exe without passing SW_SHOWNOACTIVATE on: the windows need the window exe.
        parts = [hostjoin.Part("window 1", []), hostjoin.Part("window 2", []), hostjoin.Part("bots", [])]
        playcheck.set_commands(parts, "console.exe", "window.exe")
        self.assertEqual([p.cmd[0] for p in parts], ["window.exe", "window.exe", "console.exe"])
        playcheck.set_commands(parts, "console.exe")
        self.assertEqual([p.cmd[0] for p in parts], ["console.exe"] * 3)

    def test_run_offscreen_instances_start_in_the_background_and_are_watched(self) -> None:
        for offscreen in (True, False):
            seen: list[dict[str, object]] = []

            def fake_run(_cmd: list[str], **kwargs: object) -> Result:
                seen.append(kwargs)
                return Result(0, PLACED, False, 0.1)

            with self.subTest(offscreen=offscreen), tempfile.TemporaryDirectory() as tmp, \
                    mock.patch.object(launch, "run", fake_run):  # fmt: skip
                launch.launch([["g"], ["g"]], seconds=5, log_dir=Path(tmp), name="x", offscreen=offscreen)
            self.assertEqual([k["background"] for k in seen], [offscreen, offscreen])
            self.assertEqual([k["on_start"] is not None for k in seen], [offscreen, offscreen])

    def test_shot_starts_in_the_background_and_is_watched(self) -> None:
        seen: dict[str, object] = {}

        def fake_godot(args: list[str], **kwargs: object) -> Result:
            seen.update(kwargs)
            Path(args[args.index("--") + 2]).write_bytes(shot.PNG_MAGIC + b"rest")
            return Result(0, f"{PLACED}SHOT saved x 1280x720\n", False, 0.0)

        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(shot, "has_display", return_value=True), \
                mock.patch.object(shot, "godot", fake_godot), mock.patch.object(shot, "ensure_import"), \
                mock.patch.object(shot, "say"), mock.patch.object(shot, "ok"), \
                mock.patch.object(launch, "gui_exe", return_value="window.exe"):  # fmt: skip
            shot.main("tools/shot/probe.tscn", out=str(Path(tmp) / "p.png"))
        self.assertIs(seen["background"], True)
        self.assertTrue(callable(seen["on_start"]))
        self.assertEqual(seen["exe"], "window.exe")  # the console exe would not pass SW_SHOWNOACTIVATE on


@unittest.skipUnless(IS_WINDOWS, "Windows focus behaviour (#1505); CI is headless")
@unittest.skipUnless(os.environ.get(OPT_IN) == "1", f"opens windows: set {OPT_IN}=1 to run it (docstring)")
class WindowFocusTest(unittest.TestCase):
    """A stand-in foreground window stays the foreground across a real `shot`: sampled every 5 ms and at the end, and
    the keeper never had to hand it back (a steal it reverts within its 20 ms look would slip between samples, and a
    brief one still throws a fullscreen game out)."""

    def test_a_foreground_window_stays_the_foreground_across_a_shot(self) -> None:
        real = {k: v for k, v in os.environ.items() if k != gaming.FILE_VAR}
        if REAL_GAMING_FILE:
            real[gaming.FILE_VAR] = REAL_GAMING_FILE
        if gaming.is_on(real):
            self.skipTest(f"gaming mode is on ({gaming.path(real)}): no window run while the engineer plays")
        import tkinter

        desktop = focus.Win32Desktop()
        root = tkinter.Tk()
        self.addCleanup(root.destroy)
        root.title("prime-game focus test (#1505): leave this window in front")
        root.geometry("480x120+200+200")
        tkinter.Label(root, text="A shot runs in the background; this window must stay in front.").pack(pady=40)
        root.update()
        root.lift()
        root.focus_force()
        root.update()
        stand_in = desktop.foreground()
        if desktop.owner(stand_in) != os.getpid():
            self.fail("the stand-in window could not take the foreground: run the test from a terminal you look at")
        cmd = [sys.executable, str(ROOT / "tools" / "run.py"), "shot", "tools/shot/probe.tscn"]
        run = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        chunks: list[bytes] = []
        stream = run.stdout
        assert stream is not None
        reader = threading.Thread(target=lambda: chunks.append(stream.read()), daemon=True)
        reader.start()  # a full pipe would stall the run
        samples: list[int] = []
        deadline = time.monotonic() + 180
        while run.poll() is None and time.monotonic() < deadline:
            root.update()
            samples.append(desktop.foreground())
            time.sleep(0.005)
        if run.poll() is None:
            run.kill()
        run.wait()
        reader.join(timeout=10)
        out = b"".join(chunks).decode("utf-8", errors="replace")
        root.update()
        samples.append(desktop.foreground())
        self.assertEqual(run.returncode, 0, out)
        self.assertGreater(len(samples), 3, out)
        others = sorted({window for window in samples if window != stand_in})
        self.assertEqual(others, [], f"{len(samples)} samples; other foreground windows {others}\n{out}")
        self.assertNotIn("focus: a window of the run took the foreground", out)


if __name__ == "__main__":
    unittest.main()
