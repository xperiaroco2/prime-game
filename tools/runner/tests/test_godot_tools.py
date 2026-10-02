"""`normalize` and `shot`: paths they accept, the Godot command lines they build, and how they read the results.

Godot itself is stubbed here (CI's verify has no desktop for `shot`); both commands were proven for real on
tools/shot/probe.tscn (docs/AGENT_WORKFLOW.md §11).
"""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import normalize, shot
from runner.verify import starts_godot
from runner.common import ROOT, Failure, Result, godot_bin, run

PROBE = "tools/shot/probe.tscn"


class NormalizeTest(unittest.TestCase):
    def test_paths(self) -> None:
        self.assertEqual(normalize.to_res(PROBE), f"res://{PROBE}")
        self.assertEqual(normalize.to_res(f"res://{PROBE}"), f"res://{PROBE}")
        self.assertEqual(normalize.to_res(PROBE.replace("/", "\\")), f"res://{PROBE}")
        for name, text in (
            ("tools/shot/shot.gd", "only .tscn and .tres"),
            ("addons/gdUnit4/src/ui/GdUnitConsole.tscn", "never normalized"),
            ("../elsewhere/x.tscn", "inside the project"),
            ("levels/missing.tscn", "not found"),
        ):
            with self.subTest(name=name), self.assertRaises(Failure) as caught:
                normalize.to_res(name)
            self.assertIn(text, str(caught.exception))

    def test_runs_in_headless_editor_context(self) -> None:
        cmd = normalize.command([f"res://{PROBE}"])
        self.assertEqual(cmd[:3], ["--headless", "-e", "-s"])
        self.assertEqual(cmd[-2:], ["--", f"res://{PROBE}"])

    def test_parse(self) -> None:
        a, b = "res://a.tscn", "res://b.tres"
        saved, problems = normalize.parse(["NORMALIZE saved res://a.tscn", "NORMALIZE done"], [a])
        self.assertEqual((saved, problems), ([a], []))
        saved, problems = normalize.parse(["NORMALIZE saved res://a.tscn", "NORMALIZE error res://b.tres: x"], [a, b])
        self.assertEqual(saved, [a])
        self.assertIn("res://b.tres: x", problems)
        self.assertTrue(any("did not finish" in p for p in problems))

    def test_property_keys_survive_the_header_changes_of_a_save(self) -> None:
        before = '[gd_scene format=3]\n\n[node name="Room" type="Node3D"]\n\n[node name="Box" parent="."]\nmesh = x\n'
        after = before.replace("format=3]", 'format=3 uid="uid://abc"]').replace('"Node3D"]', '"Node3D" unique_id=5]')
        self.assertEqual(normalize.property_keys(before), {"[node ./Box]: mesh"})
        self.assertEqual(normalize.property_keys(before), normalize.property_keys(after))
        tres = '[gd_resource type="StandardMaterial3D" format=3]\n\n[resource]\nalbedo_colour = Color(1, 0, 0, 1)\n'
        self.assertEqual(normalize.property_keys(tres), {"[resource]: albedo_colour"})

    def test_a_dropped_property_restores_the_file(self) -> None:
        # Godot silently drops a misspelled property on load; normalize must not lose the line.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "m.tres").write_bytes(b'[gd_resource format=3]\n\n[resource]\nalbedo_colour = 1\nmetallic = 0.5\n')
            original = (root / "m.tres").read_bytes()

            def fake_godot(*_args: object, **_kwargs: object) -> Result:
                (root / "m.tres").write_bytes(b'[gd_resource format=3 uid="uid://x"]\n\n[resource]\nmetallic = 0.5\n')
                return Result(0, "NORMALIZE saved res://m.tres\nNORMALIZE done\n", False, 0.0)

            with mock.patch.object(normalize, "ROOT", root), mock.patch.object(normalize, "godot", fake_godot), \
                    mock.patch.object(normalize, "git_status", return_value=set()), \
                    mock.patch.object(normalize, "say"), mock.patch.object(normalize, "ok"), \
                    mock.patch.object(normalize, "bad") as bad:  # fmt: skip
                self.assertEqual(normalize.main(["m.tres"]), 1)
            self.assertEqual((root / "m.tres").read_bytes(), original)
            self.assertIn("albedo_colour", bad.call_args.args[0])


    def test_a_timeout_restores_a_half_written_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "m.tres").write_bytes(b"[gd_resource format=3]\n\n[resource]\nmetallic = 0.5\n")
            original = (root / "m.tres").read_bytes()

            def dies_mid_write(*_args: object, **_kwargs: object) -> Result:
                (root / "m.tres").write_bytes(b"[gd_reso")
                return Result(-9, "", True, 300.0)

            with mock.patch.object(normalize, "ROOT", root), mock.patch.object(normalize, "godot", dies_mid_write), \
                    mock.patch.object(normalize, "git_status", return_value=set()), \
                    mock.patch.object(normalize, "say"), mock.patch.object(normalize, "bad"):  # fmt: skip
                with self.assertRaises(Failure):
                    normalize.main(["m.tres"])
            self.assertEqual((root / "m.tres").read_bytes(), original)


@starts_godot
@unittest.skipUnless(godot_bin(), "needs Godot (GODOT_BIN); CI has it")
class RealNormalizeTest(unittest.TestCase):
    """normalize.gd in a real headless editor, on a throwaway project with a copy of the probe scene."""

    def test_adds_uids_then_is_idempotent_and_never_saves_a_broken_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "project.godot").write_text('config_version=5\n\n[application]\nconfig/name="n"\n', "utf-8")
            (project / "normalize.gd").write_bytes((ROOT / "tools/normalize/normalize.gd").read_bytes())
            (project / "probe.tscn").write_bytes((ROOT / PROBE).read_bytes())
            broken = b"[gd_resource type=\"Resource\" format=3]\n\n[resource]\nx = Vector3(1, 2\n"
            (project / "broken.tres").write_bytes(broken)

            def run_it(*paths: str) -> list[str]:
                cmd = [str(godot_bin()), "--no-header", "--path", str(project), "--headless", "-e", "-s",
                       "res://normalize.gd", "--", *paths]  # fmt: skip
                res = run(cmd, timeout=180, cwd=project)
                self.assertFalse(res.timed_out, res.out[-2000:])
                return [line for line in res.lines if line.startswith("NORMALIZE")]

            lines = run_it("res://probe.tscn", "res://broken.tres")
            self.assertIn("NORMALIZE saved res://probe.tscn", lines)
            self.assertTrue(any(line.startswith("NORMALIZE error res://broken.tres") for line in lines), lines)
            self.assertEqual((project / "broken.tres").read_bytes(), broken)
            first = (project / "probe.tscn").read_bytes()
            self.assertIn(b'uid="uid://', first.splitlines()[0])
            self.assertIn(b"unique_id=", first)
            run_it("res://probe.tscn")
            self.assertEqual((project / "probe.tscn").read_bytes(), first)


class ShotTest(unittest.TestCase):
    def test_command_is_windowed_and_off_screen(self) -> None:
        cmd = shot.command(f"res://{PROBE}", Path("out.png"), "640x360", 5)
        self.assertNotIn("--headless", cmd)
        self.assertEqual(cmd[cmd.index("--position") + 1], "-30000,-30000")
        self.assertEqual(cmd[cmd.index("--resolution") + 1], "640x360")
        self.assertEqual(cmd[-4:], ["--", f"res://{PROBE}", "out.png", "5"])

    def test_refuses_without_a_desktop_and_bad_arguments(self) -> None:
        with mock.patch.object(shot, "IS_CI", True), mock.patch.object(shot, "say"):
            with self.assertRaises(Failure) as caught:
                shot.main(PROBE)
        self.assertIn("desktop", str(caught.exception))
        with mock.patch.object(shot, "has_display", return_value=True), mock.patch.object(shot, "say"):
            for kwargs in ({"size": "big"}, {"frames": 0}):
                with self.subTest(kwargs=kwargs), self.assertRaises(Failure):
                    shot.main(PROBE, **kwargs)  # type: ignore[arg-type]
            with self.assertRaises(Failure):
                shot.main("tools/shot/shot.gd")

    def test_reads_the_png_back(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            png = Path(tmp) / "p.png"

            def fake_godot(args: list[str], **_kwargs: object) -> Result:
                Path(args[args.index("--") + 2]).write_bytes(shot.PNG_MAGIC + b"rest")
                return Result(0, f"SHOT saved {png} 1280x720\n", False, 0.0)

            with mock.patch.object(shot, "has_display", return_value=True), mock.patch.object(shot, "godot", fake_godot), \
                    mock.patch.object(shot, "say"), mock.patch.object(shot, "ok"):  # fmt: skip
                self.assertEqual(shot.main(PROBE, out=str(png)), 0)
            failing = Result(1, "SHOT error cannot load res://x.tscn\n", False, 0.0)
            with mock.patch.object(shot, "has_display", return_value=True), \
                    mock.patch.object(shot, "godot", return_value=failing), mock.patch.object(shot, "say"):  # fmt: skip
                with self.assertRaises(Failure) as caught:
                    shot.main(PROBE, out=str(png))
            self.assertIn("cannot load", str(caught.exception))

    def test_names_the_rendering_driver(self) -> None:
        # The runner passes --no-header, so Godot's own "Vulkan ... Forward+" line is gone: shot.gd prints the
        # driver and the runner echoes it (#124: the shot log proves which driver Windows uses).
        with tempfile.TemporaryDirectory() as tmp:
            png = Path(tmp) / "p.png"

            def fake_godot(args: list[str], **_kwargs: object) -> Result:
                Path(args[args.index("--") + 2]).write_bytes(shot.PNG_MAGIC + b"rest")
                return Result(0, f"SHOT renderer vulkan forward_plus\nSHOT saved {png} 1280x720\n", False, 0.0)

            said: list[str] = []
            with mock.patch.object(shot, "has_display", return_value=True), mock.patch.object(shot, "godot", fake_godot), \
                    mock.patch.object(shot, "say", said.append), mock.patch.object(shot, "ok"):  # fmt: skip
                shot.main(PROBE, out=str(png))
        self.assertIn("        renderer: vulkan forward_plus", said)
        # shot.gd needs a real window, so no test runs it; pin the print statement itself, not the doc comment.
        source = (ROOT / "tools/shot/shot.gd").read_text(encoding="utf-8")
        self.assertIn('print("SHOT renderer ", RenderingServer.get_current_rendering_driver_name()', source)

    def test_probe_scene_is_committed(self) -> None:
        self.assertTrue((ROOT / PROBE).is_file())


if __name__ == "__main__":
    unittest.main()
