"""`export` (#369): the parts that start no Godot. The exports themselves, the release check on real templates and the
content-hash proof ran in #369's cloud session and run in the release workflow on each tag (they need the 1.3 GB
templates)."""

import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path

from runner import export, pins
from runner.common import Failure

ROOT = Path(__file__).resolve().parents[3]
MODE = "res://content/modes/base_mode.tres"
PROBE_OUT = [
    "Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org",
    f"EXPORT mode {MODE} -4716857346301007431",
    f"EXPORT text {MODE} mode 1790889447597077997",
    f"EXPORT text {MODE} level res://levels/lobby/lobby.tscn d1a4",
    f"EXPORT text {MODE} level res://levels/greybox/greybox.tscn dfdb",
    f"EXPORT text {MODE} file res://levels/rooms/room.tscn missing",
    f"EXPORT missing {MODE} res://levels/rooms/room.tscn",
    "EXPORT done 1",
]


class ProbeTest(unittest.TestCase):
    def test_the_probe_lines_give_each_modes_hash_levels_and_misses(self) -> None:
        probe = export.parse_probe(PROBE_OUT)
        self.assertEqual(probe.fingerprints, {MODE: -4716857346301007431})
        self.assertEqual(probe.levels(), ["res://levels/lobby/lobby.tscn", "res://levels/greybox/greybox.tscn"])
        self.assertEqual(probe.missing, [f"{MODE}: res://levels/rooms/room.tscn"])
        self.assertEqual(probe.missing_digests(), ["file res://levels/rooms/room.tscn missing"])

    def test_a_probe_that_never_finished_or_found_no_mode_fails(self) -> None:
        with self.assertRaises(Failure):
            export.parse_probe(PROBE_OUT[:-1])
        with self.assertRaises(Failure):
            export.parse_probe(["EXPORT done 0"])

    def test_a_proof_with_a_missing_file_fails_before_any_export(self) -> None:
        with self.assertRaises(Failure) as caught:
            export.prove_hash("HEAD", Path("unused"), export.parse_probe(PROBE_OUT))
        self.assertIn("misses files", str(caught.exception))
        self.assertIn("room.tscn", str(caught.exception))


class ChangedByteTest(unittest.TestCase):
    def test_one_byte_of_the_first_node_name_changes(self) -> None:
        scene = b'[gd_scene format=3]\n\n[node name="Lobby" type="Node3D"]\n\n[node name="Floor" parent="."]\n'
        changed = export.changed_byte(scene)
        self.assertEqual(len(changed), len(scene))
        self.assertEqual(sum(a != b for a, b in zip(scene, changed)), 1)
        self.assertIn(b'[node name="Aobby"', changed)
        self.assertIn(b'[node name="Bnchor"', export.changed_byte(scene.replace(b"Lobby", b"Anchor")))

    def test_a_level_without_a_node_fails(self) -> None:
        with self.assertRaises(Failure):
            export.changed_byte(b"[gd_scene format=3]\n")


class ReleaseCheckTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.templates = self.dir / "templates"
        self.templates.mkdir()
        (self.templates / "windows_release_x86_64.exe").write_bytes(b"release template")
        (self.templates / "windows_debug_x86_64.exe").write_bytes(b"debug template")

    def build(self, files: dict[str, bytes]) -> Path:
        folder = self.dir / "build"
        folder.mkdir(exist_ok=True)
        for name, data in files.items():
            (folder / name).write_bytes(data)
        archive = self.dir / "game.zip"
        export.write_zip(folder, archive, "PrimeGame")
        return archive

    def release_files(self) -> dict[str, bytes]:
        return {
            "PrimeGame.exe": b"release template",
            "PrimeGame.pck": b"pack",
            "libtwovoip.windows.template_release.x86_64.dll": b"dll",
        }

    def test_the_release_templates_exe_and_library_pass(self) -> None:
        self.assertEqual(export.check_release(self.build(self.release_files()), self.templates), [])

    def test_the_debug_template_a_console_wrapper_or_the_debug_library_fail(self) -> None:
        files = self.release_files()
        files["PrimeGame.exe"] = b"debug template"
        problems = export.check_release(self.build(files), self.templates)
        self.assertTrue(any("is the debug template" in problem for problem in problems), problems)
        for extra in ("PrimeGame.console.exe", "libtwovoip.windows.template_debug.x86_64.dll"):
            with self.subTest(extra=extra):
                (self.dir / "build").joinpath(extra).write_bytes(b"x")
                problems = export.check_release(self.build(self.release_files()), self.templates)
                self.assertTrue(any(extra in problem for problem in problems), problems)
                (self.dir / "build" / extra).unlink()

    def test_another_exe_fails(self) -> None:
        files = self.release_files()
        files["PrimeGame.exe"] = b"release template with a changed icon"
        problems = export.check_release(self.build(files), self.templates)
        self.assertEqual(problems, ["PrimeGame.exe is not the release template windows_release_x86_64.exe"])

    def test_the_same_files_give_the_same_zip_under_one_folder(self) -> None:
        first = self.build(self.release_files()).read_bytes()
        second = self.build(self.release_files()).read_bytes()
        self.assertEqual(first, second)
        with zipfile.ZipFile(self.dir / "game.zip") as archive:
            self.assertTrue(all(name.startswith("PrimeGame/") for name in archive.namelist()))


class HelpersTest(unittest.TestCase):
    def test_only_the_twovoip_errors_are_expected(self) -> None:
        lines = [
            "ERROR: Can't open dynamic library, file not found: 'addons/twovoip/libs/libtwovoip.linux.x86_64.so'.",
            "   at: open_dynamic_library (drivers/unix/os_unix.cpp:1063)",
            "ERROR: Prepare Template: The given export path doesn't exist.",
            "   at: add_message (./editor/export/editor_export_platform.h:270)",
        ]
        self.assertEqual(
            export.unexpected_errors(lines),
            [
                "ERROR: Prepare Template: The given export path doesn't exist. "
                "at: add_message (./editor/export/editor_export_platform.h:270)"
            ],
        )

    def test_a_version_is_a_plain_file_name_part(self) -> None:
        self.assertEqual(export.version_of("HEAD", "v0.6.0"), "v0.6.0")
        with self.assertRaises(Failure):
            export.version_of("HEAD", "v0.6 beta")

    def test_the_templates_are_pinned_from_the_editors_release(self) -> None:
        self.assertEqual(len(pins.GODOT_TEMPLATES_SHA512), 128)
        self.assertEqual(pins.GODOT_TEMPLATES_URL.rsplit("/", 1)[0], pins.GODOT_LINUX_URL.rsplit("/", 1)[0])
        self.assertEqual(export.templates_dir(Path("/data")).name, "4.7.2.stable")

    def test_a_lfs_pointer_in_the_tree_is_found(self) -> None:
        tree = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tree, True)
        (tree / "levels").mkdir()
        (tree / "levels" / "crate.glb").write_bytes(export.LFS_POINTER + b"\noid sha256:00\nsize 12\n")
        (tree / "levels" / "room.tscn").write_bytes(b"[gd_scene format=3]\n")
        self.assertEqual(export.lfs_pointers(tree), ["levels/crate.glb"])


if __name__ == "__main__":
    unittest.main()
