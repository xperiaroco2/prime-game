"""The off-screen window (#1141): the start every off-screen launch uses, the OFFSCREEN line the runner checks, and
that each window script places its window before anything else."""

import re
import unittest

from runner import launch, offscreen, playcheck, shot
from runner.common import ROOT

SCREEN = "0,0,2560,1440"


def line(x: int, y: int, w: int = 1296, h: int = 759, screens: str = SCREEN) -> str:
    return f"OFFSCREEN window {x},{y} {w}x{h} screens {screens} ticks 990"


class ProblemsTest(unittest.TestCase):
    def test_a_window_moved_off_every_screen_is_proven(self) -> None:
        self.assertEqual(offscreen.problems(["SHOT renderer vulkan", line(-30008, -30031)]), [])
        self.assertEqual(offscreen.problem([line(-30008, -30031)]), "")
        # Godot colours its output: the line still counts.
        self.assertEqual(offscreen.problems([f"\x1b[0m{line(-30008, -30031)}\x1b[0m"]), [])

    def test_no_line_is_a_problem(self) -> None:
        self.assertIn("no OFFSCREEN line", offscreen.problem(["SHOT saved x.png 1280x720"]))
        self.assertIn("no OFFSCREEN line", offscreen.problem([]))

    def test_a_window_that_meets_any_screen_is_a_problem(self) -> None:
        # The clamped start of #1141 (the top-left corner), a window touching the right edge by one pixel, and one on
        # a second screen left of the primary.
        two = f"{SCREEN};-1920,0,1920,1080"
        for rect, screens, which in (
            ((-8, -31), SCREEN, "screen 0"),
            ((2559, 100), SCREEN, "screen 0"),
            ((-2000, 0), two, "screen 1"),
        ):
            with self.subTest(rect=rect):
                found = offscreen.problems([line(*rect, screens=screens)])
                self.assertEqual(len(found), 1, found)
                self.assertIn(which, found[0])
        # Touching edges do not overlap: a window ending at x=0 is off a screen starting there.
        self.assertEqual(offscreen.problems([line(-1296, 0)]), [])

    def test_every_line_counts_and_a_bad_screen_is_a_problem(self) -> None:
        self.assertEqual(len(offscreen.problems([line(-30008, -30031), line(0, 0)])), 1)
        self.assertIn("not <x>,<y>,<w>,<h>", offscreen.problem([line(-30008, -30031, screens="0,0,2560")]))

    def test_env_takes_only_a_size(self) -> None:
        self.assertEqual(offscreen.env("1280x720"), {"PRIME_WINDOW": "1280x720"})
        for bad in ("1280", "0x720", "1280x", "x720", "-1x5", "1280X720"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                offscreen.env(bad)


class LaunchesTest(unittest.TestCase):
    def test_the_start_is_one_pixel_past_the_top_right_corner(self) -> None:
        # Godot clamps the client area to the usable area's far edge minus a third of the window's size (0 for one
        # pixel): x past the right edge, y at the top, the title bar above the screen (#1141).
        self.assertEqual(offscreen.START, ["--position", "30000,-30000", "--resolution", "1x1"])

    def test_no_runner_module_places_a_window_with_its_own_position(self) -> None:
        # Only offscreen.START starts an off-screen window; hostjoin tiles the visible host and join windows.
        allowed = {"offscreen.py", "hostjoin.py"}
        for path in sorted((ROOT / "tools" / "runner").glob("*.py")):
            if path.name in allowed:
                continue
            text = path.read_text(encoding="utf-8")
            with self.subTest(module=path.name):
                self.assertNotIn('"--position"', text)
                self.assertNotIn('"--resolution"', text)
                self.assertNotIn("-30000", text)

    def test_each_window_script_places_its_window_first(self) -> None:
        # In _initialize, before the script loads, instantiates or waits for anything (only reading its arguments and
        # the headless check may come first): the window sits clamped on the screen until then.
        busy = re.compile(r"\b(load|preload|instantiate|change_scene_to_\w+|create_timer|await|add_child|_shoot)\b")
        for script in (shot.SCRIPT, playcheck.WINDOW_SCRIPT, launch.OFFSCREEN_SCENE):
            with self.subTest(script=script):
                text = (ROOT / script.removeprefix("res://")).read_text(encoding="utf-8")
                self.assertIn('const Offscreen := preload("res://tools/offscreen/offscreen.gd")', text)
                body = text[text.index("func _initialize() -> void:") :]
                body = body[: body.index("\nfunc ", 1)]
                code = [s.strip() for s in body.splitlines()[1:] if s.strip() and not s.strip().startswith("#")]
                at = next(i for i, s in enumerate(code) if "Offscreen.place()" in s)
                self.assertEqual([s for s in code[:at] if busy.search(s)], [], script)


if __name__ == "__main__":
    unittest.main()
