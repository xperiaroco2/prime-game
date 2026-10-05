"""`export` (#369): the parts that start no Godot. The exports themselves, the release check on real templates and the
content-hash proof ran in #369's cloud session and run in the release workflow on each tag (they need the 1.3 GB
templates). The release workflow's shape is checked here too, next to ci.yml's in test_github_workflows.py."""

import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path

from runner import export, pins
from runner.common import Failure

try:
    import yaml
except ImportError:  # pragma: no cover - only without gdtoolkit's dependencies
    yaml = None

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


class ProofHelpersTest(unittest.TestCase):
    def test_a_level_change_is_judged_only_on_the_modes_that_name_the_level(self) -> None:
        other = "res://content/modes/other_mode.tres"
        probe = export.parse_probe(
            [
                *PROBE_OUT[:-1],
                f"EXPORT mode {other} 7",
                f"EXPORT text {other} level res://levels/other.tscn ab",
                "EXPORT done 2",
            ]
        )
        self.assertEqual(probe.levels_of(MODE), ["res://levels/lobby/lobby.tscn", "res://levels/greybox/greybox.tscn"])
        self.assertEqual(probe.levels_of(other), ["res://levels/other.tscn"])

    def test_the_fixture_export_keeps_tests_fixtures_and_excludes_the_other_test_folders(self) -> None:
        presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        changed = export.with_fixtures(presets, ["unit", "fixtures", "harness"])
        self.assertNotIn("tests/*", changed)
        self.assertIn('exclude_filter="tests/harness/*, tests/unit/*, tools/*', changed)
        with self.assertRaises(Failure):
            export.with_fixtures(presets.replace("tests/*", "tests/unit/*"), ["unit"])

    def test_the_walk_proof_names_the_fixtures_the_suite_names(self) -> None:
        suite_path = ROOT / "tests" / "unit" / "net" / "messages" / "content_fingerprint_test.gd"
        suite = suite_path.read_text(encoding="utf-8")
        for path in export.FIXTURE_REACHED:
            self.assertIn(f'FIXTURES + "{path.removeprefix(export.FIXTURES)}"', suite)
        for path, (old, _) in export.FIXTURE_EDITS.items():
            self.assertEqual((ROOT / path.removeprefix("res://")).read_bytes().count(old), 1, path)


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
            (folder / name).parent.mkdir(parents=True, exist_ok=True)
            (folder / name).write_bytes(data)
        archive = self.dir / "game.zip"
        export.write_zip(folder, archive, "PrimeGame")
        return archive

    def release_files(self) -> dict[str, bytes]:
        return {
            "PrimeGame.exe": b"release template",
            "PrimeGame.pck": b"pack",
            "libtwovoip.windows.template_release.x86_64.dll": b"dll",
            "libwebrtc_native.windows.template_release.x86_64.dll": b"dll",
            **{notice: b"notice" for notice in export.NOTICES},
        }

    def test_the_release_templates_exe_library_and_notices_pass(self) -> None:
        self.assertEqual(export.check_release(self.build(self.release_files()), self.templates), [])

    def test_a_zip_without_a_license_notice_or_the_credits_fails(self) -> None:
        for notice in ("CREDITS.md", "licenses/twovoip/LICENSE", "licenses/webrtc_native/LICENSE.mbedtls"):
            with self.subTest(notice=notice):
                shutil.rmtree(self.dir / "build", ignore_errors=True)
                files = self.release_files()
                del files[notice]
                problems = export.check_release(self.build(files), self.templates)
                self.assertTrue(any(notice in problem for problem in problems), problems)
                self.assertEqual(export.missing_notices(self.dir / "game.zip"), [notice])

    def test_a_notice_moved_out_of_its_folder_fails(self) -> None:
        files = self.release_files()
        files["LICENSE.mbedtls"] = files.pop("licenses/webrtc_native/LICENSE.mbedtls")
        problems = export.check_release(self.build(files), self.templates)
        self.assertTrue(any("licenses/webrtc_native/LICENSE.mbedtls" in problem for problem in problems), problems)

    def test_the_notices_are_copied_from_the_tree_under_licenses_per_addon(self) -> None:
        tree = self.dir / "tree"
        (tree / "addons" / "gdUnit4").mkdir(parents=True)
        (tree / "addons" / "gdUnit4" / "LICENSE").write_bytes(b"not shipped")
        (tree / "CREDITS.md").write_bytes(b"# Credits\n")
        for addon in export.SHIPPED_ADDONS:
            (tree / "addons" / addon).mkdir(parents=True)
        for notice in export.NOTICES:
            if notice.startswith("licenses/"):
                (tree / "addons" / notice.removeprefix("licenses/")).write_bytes(notice.encode())
        folder = self.dir / "build"
        export.add_notices(tree, folder)
        self.assertEqual(
            sorted(path.relative_to(folder).as_posix() for path in folder.rglob("*") if path.is_file()),
            sorted(export.NOTICES),
        )
        self.assertEqual((folder / "licenses" / "twovoip" / "LICENSE").read_bytes(), b"licenses/twovoip/LICENSE")
        (tree / "CREDITS.md").unlink()
        with self.assertRaises(Failure):
            export.add_notices(tree, self.dir / "again")

    def test_the_debug_template_a_console_wrapper_or_the_debug_library_fail(self) -> None:
        files = self.release_files()
        files["PrimeGame.exe"] = b"debug template"
        problems = export.check_release(self.build(files), self.templates)
        self.assertTrue(any("is the debug template" in problem for problem in problems), problems)
        for extra in (
            "PrimeGame.console.exe",
            "libtwovoip.windows.template_debug.x86_64.dll",
            "libwebrtc_native.windows.template_debug.x86_64.dll",
        ):
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
            self.assertIn("PrimeGame/licenses/twovoip/LICENSE", archive.namelist())


class NoticesTest(unittest.TestCase):
    """#419: every addon with a license file is either shipped, its notices in the zip, or kept out of the build."""

    def addon_licenses(self) -> dict[str, list[str]]:
        found: dict[str, list[str]] = {}
        for path in sorted((ROOT / "addons").glob("*/LICENSE*")):
            found.setdefault(path.parent.name, []).append(path.name)
        return found

    def test_every_addon_with_a_license_file_is_named_shipped_or_not(self) -> None:
        addons = self.addon_licenses()
        self.assertEqual(sorted(addons), sorted((*export.SHIPPED_ADDONS, *export.UNSHIPPED_ADDONS)))
        self.assertFalse(set(export.SHIPPED_ADDONS) & set(export.UNSHIPPED_ADDONS))

    def test_the_notices_are_the_credits_and_every_license_file_of_a_shipped_addon(self) -> None:
        addons = self.addon_licenses()
        expected = ["CREDITS.md"] + [
            f"licenses/{addon}/{name}" for addon in export.SHIPPED_ADDONS for name in addons.get(addon, [])
        ]
        self.assertEqual(sorted(export.NOTICES), sorted(expected))
        self.assertLessEqual(set(export.NOTICES), export.RELEASE_FILES)

    def test_an_unshipped_addon_is_excluded_from_both_presets(self) -> None:
        presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        filters = [line for line in presets.splitlines() if line.startswith("exclude_filter=")]
        self.assertEqual(len(filters), 2)
        for addon in export.UNSHIPPED_ADDONS:
            for line in filters:
                self.assertIn(f"addons/{addon}/*", line)

    def test_a_shipped_addon_is_not_excluded(self) -> None:
        presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        for addon in export.SHIPPED_ADDONS:
            self.assertNotIn(f"addons/{addon}/", presets)


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

    def test_the_probe_of_a_windows_pack_expects_webrtc_natives_errors_too(self) -> None:
        lines = [
            "ERROR: Can't open dynamic library, file not found: "
            "'addons/webrtc_native/lib/libwebrtc_native.linux.template_debug.x86_64.so'.",
            "ERROR: GDExtension dynamic library not found: 'res://addons/webrtc_native/webrtc_native.gdextension'.",
        ]
        self.assertEqual(export.unexpected_errors(lines, export.PACK_WITHOUT_LINUX), [])
        self.assertEqual(len(export.unexpected_errors(lines)), 2, "an export loads the project's Linux library")

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


@unittest.skipIf(yaml is None, "PyYAML is missing (it comes with gdtoolkit)")
class ReleaseWorkflowTest(unittest.TestCase):
    def test_it_runs_on_a_tag_only_and_publishes_only_the_release_zip(self) -> None:
        data = yaml.safe_load((ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8"))
        data["on"] = data.pop(True)  # YAML 1.1 reads a bare `on:` key as the boolean true
        self.assertEqual(data["on"], {"push": {"tags": ["v*"]}})
        self.assertEqual(data["permissions"], {"contents": "write"})
        steps = data["jobs"]["windows"]["steps"]
        uses = [step.get("uses", "") for step in steps]
        self.assertEqual(uses[:2], ["actions/checkout@v7", "./.github/actions/setup-toolchain"])
        self.assertIs(steps[0]["with"]["lfs"], True, "a release ships the real LFS assets")
        runs = [step.get("run", "") for step in steps]
        self.assertFalse(any("twovoip" in run for run in runs), "the Windows build needs the TwoVoIP extension")
        exporting = next(i for i, run in enumerate(runs) if "tools/run.sh export" in run)
        self.assertIn('--version "$GITHUB_REF_NAME"', runs[exporting])
        publish = next(i for i, run in enumerate(runs) if "gh release create" in run)
        self.assertIn('-windows-x86_64.zip"', runs[publish])
        self.assertIn("gh release upload", runs[publish])
        self.assertNotIn("debug", runs[publish])
        debug = next(step for step in steps if step.get("name") == "Keep the debug zip for the humans")
        self.assertTrue(debug["with"]["path"].endswith("-windows-x86_64-debug.zip"))
        self.assertLessEqual(debug["with"]["retention-days"], 7)
        self.assertLess(exporting, steps.index(debug))
        self.assertLess(steps.index(debug), publish)


if __name__ == "__main__":
    unittest.main()
