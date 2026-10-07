"""`check` without LFS content (#515; the LFS ADR's amendment of 2026-10-07, option 2): in CI each file .gitattributes
routes through LFS is a pointer file, which the import must not see and whose consequences the project check drops,
in one summary line; locally nothing changes; the credits check still covers pointer files; `check --lfs-content`
fails on one. RealPointerTest proves it with the pinned Godot in a throwaway project: a texture imported on a PC with
LFS, then checked out as a pointer file as CI does."""

import io
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

from runner import check, cli, common, credits, lfs
from runner.common import Failure, Result, godot_bin
from runner.verify import starts_godot

POINTER = (
    b"version https://git-lfs.github.com/spec/v1\n"
    b"oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393\n"
    b"size 12345\n"
)
ATTRIBUTES = "*.png filter=lfs diff=lfs merge=lfs -text\n*.wav filter=lfs diff=lfs merge=lfs -text\n"
ATTRIBUTES += "addons/** !filter !diff !merge\n"

# What the project check printed with the pinned Godot over a scene that uses a pointer file's texture, a script that
# preloads it (class_name Pre) and a script that reads that constant through the class name (probed for #515).
PROBED = [
    "CHECK warning scene/resources/resource_format_text.cpp:501: res://s.tscn:3 - ext_resource, invalid UID:"
    " uid://bwafesmfooh0c - using text path instead: res://art/a.png (res://s.tscn:3 - ext_resource, invalid UID:"
    " uid://bwafesmfooh0c - using text path instead: res://art/a.png)",
    "CHECK error core/io/resource_loader.cpp:317: Failed loading resource: res://art/a.png. [_load]",
    'CHECK error res://pre.gd:4: Parse Error: Could not preload resource file "res://art/a.png". [GDScript::reload]',
    'CHECK error modules/gdscript/gdscript_resource_format.cpp:46: Failed to load script "res://pre.gd" with error'
    ' "Parse error". [load]',
    "CHECK error core/io/resource_loader.cpp:317: Failed loading resource: res://art/a.png. [_load]",
    "CHECK error scene/resources/resource_format_text.cpp:41: res://s.tscn:6 - Parse Error: [ext_resource] referenced"
    " non-existent resource at: res://art/a.png. [_printerr]",
    "CHECK error core/io/resource_loader.cpp:317: Failed loading resource: res://art/a.png. [_load]",
    'CHECK error res://user.gd:5: Parse Error: Could not resolve external class member "TEX". [GDScript::reload]',
    'CHECK error modules/gdscript/gdscript_resource_format.cpp:46: Failed to load script "res://user.gd" with error'
    ' "Parse error". [load]',
    "CHECK summary files=6 errors=10 warnings=1",
]


def png() -> bytes:
    """A 1x1 RGB PNG: real content, as on a PC with LFS."""

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00")) + \
        chunk(b"IEND", b"")  # fmt: skip


def repo(parent: Path) -> Path:
    """A git repository with the project's kind of .gitattributes (nothing committed: credits counts untracked
    files)."""
    root = parent / "repo"
    root.mkdir()
    subprocess.run(["git", "init", "-q", str(root)], check=True, capture_output=True)
    (root / ".gitattributes").write_text(ATTRIBUTES, encoding="utf-8")
    return root


def write(root: Path, name: str, data: bytes | str) -> Path:
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, str):
        data = data.encode("utf-8")
    path.write_bytes(data)
    return path


class PointerTest(unittest.TestCase):
    def test_is_pointer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertTrue(lfs.is_pointer(write(root, "a.png", POINTER)))
            self.assertFalse(lfs.is_pointer(write(root, "b.png", png())))
            # The spec keeps pointer files under 1024 bytes: a larger file is content, whatever its first line.
            self.assertFalse(lfs.is_pointer(write(root, "c.txt", POINTER + b"x" * 1024)))
            self.assertFalse(lfs.is_pointer(write(root, "d.png", POINTER[:20])))
            self.assertFalse(lfs.is_pointer(root / "missing.png"))

    def test_only_lfs_files_outside_addons_that_are_pointers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = repo(Path(tmp))
            write(root, "art/a.png", POINTER)
            write(root, "art/b.wav", POINTER)
            write(root, "art/real.png", png())
            write(root, "addons/x/icon.png", POINTER)  # outside LFS (!filter): never a pointer in a checkout
            write(root, "docs/pointer.txt", POINTER)  # not routed through LFS
            self.assertEqual(lfs.pointers(root), ["art/a.png", "art/b.wav"])

    def test_ci_mode_skips_the_fixture_and_local_mode_does_not(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = repo(Path(tmp))
            write(root, "art/a.png", POINTER)
            with mock.patch.object(common, "IS_CI", True):
                self.assertEqual(lfs.ci_pointers(root), ["art/a.png"])
            with mock.patch.object(common, "IS_CI", False):
                self.assertEqual(lfs.ci_pointers(root), [])

    def test_the_credits_check_still_covers_a_pointer_file_in_ci(self) -> None:
        # It needs only the path: an uncredited pointer file fails in CI as the real file does locally.
        with tempfile.TemporaryDirectory() as tmp:
            root = repo(Path(tmp))
            write(root, "art/a.png", POINTER)
            write(root, credits.OUTPUT, credits.render([]))
            with mock.patch.object(common, "IS_CI", True):
                report = credits.check(root)
            self.assertEqual(report.assets, 1)
            self.assertTrue(any(line.startswith("art/a.png: an LFS asset without a credits entry")
                                for line in report.errors), report.errors)  # fmt: skip


class AsideTest(unittest.TestCase):
    def test_the_files_are_out_of_sight_inside_and_back_after(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "art/a.png", POINTER)
            write(root, "art/a.png.import", "[remap]\n")
            write(root, "art/b.wav", POINTER)  # no .import yet: a new asset
            with lfs.aside(["art/a.png", "art/b.wav"], root):
                for name in ("art/a.png", "art/a.png.import", "art/b.wav"):
                    self.assertFalse((root / name).exists(), name)
                    self.assertTrue((root / lfs.ASIDE / name).is_file(), name)
                self.assertTrue((root / lfs.ASIDE / ".gdignore").is_file())
            self.assertEqual((root / "art/a.png").read_bytes(), POINTER)
            self.assertEqual((root / "art/a.png.import").read_text(encoding="utf-8"), "[remap]\n")
            self.assertEqual((root / "art/b.wav").read_bytes(), POINTER)

    def test_the_files_come_back_when_the_import_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "art/a.png", POINTER)
            with self.assertRaises(Failure), lfs.aside(["art/a.png"], root):
                raise Failure("godot --import exited 1 twice")
            self.assertEqual((root / "art/a.png").read_bytes(), POINTER)

    def test_no_pointer_files_touch_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with lfs.aside([], root):
                pass
            self.assertFalse((root / "tools").exists())


class DropLinesTest(unittest.TestCase):
    def test_the_lines_a_pointer_file_causes_are_dropped(self) -> None:
        kept, errors, warnings = lfs.drop_lines(PROBED, ["art/a.png"])
        # Dropped: the texture's three load failures, the scene's missing resource and its uid warning, the preload
        # and the failed load of the script that preloads it. Kept: a script that reads the constant through the
        # class name says nothing of the file (the limit the ADR's amendment records).
        self.assertEqual((errors, warnings), (6, 1))
        self.assertEqual(
            kept,
            [
                'CHECK error res://user.gd:5: Parse Error: Could not resolve external class member "TEX".'
                " [GDScript::reload]",
                'CHECK error modules/gdscript/gdscript_resource_format.cpp:46: Failed to load script "res://user.gd"'
                ' with error "Parse error". [load]',
                "CHECK summary files=6 errors=2 warnings=0",
            ],
        )

    def test_the_imported_file_its_committed_import_names_counts(self) -> None:
        # Seen with the pinned Godot (RealPointerTest): the committed .import remaps res://art/a.png to the imported
        # file, which the import never wrote in CI.
        imported = "res://.godot/imported/a.png-0180b64844aadf81c6b18dd2c9268d2e.ctex"
        lines = [
            f"CHECK error scene/resources/compressed_texture.cpp:45: Unable to open file: {imported}. [_load_data]",
            f"CHECK error core/io/resource_loader.cpp:317: Failed loading resource: {imported}. [_load]",
            "CHECK summary files=1 errors=2 warnings=0",
        ]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "art/a.png.import", f'[remap]\n\npath="{imported}"\n\n[deps]\n\ndest_files=["{imported}"]\n')
            self.assertEqual(lfs.res_paths(["art/a.png"], root), {"res://art/a.png", imported})
            self.assertEqual(lfs.drop_lines(lines, ["art/a.png"], root), (["CHECK summary files=1 errors=0 warnings=0"], 2, 0))
            self.assertEqual(lfs.drop_lines(lines, ["art/a.png"], Path(tmp) / "elsewhere")[1:], (0, 0))

    def test_no_pointer_files_change_nothing(self) -> None:
        self.assertEqual(lfs.drop_lines(PROBED, []), (PROBED, 0, 0))

    def test_another_file_and_a_longer_name_are_kept(self) -> None:
        lines = [
            "CHECK error core/io/resource_loader.cpp:317: Failed loading resource: res://art/a.png2. [_load]",
            "CHECK error res://core/x.gd:3: Identifier \"Foo\" not declared in the current scope. [_parse]",
            "CHECK error core/io/resource_loader.cpp:317: Failed loading resource: res://art/a.png. [_load]",
            "CHECK summary files=2 errors=3 warnings=0",
        ]
        kept, errors, warnings = lfs.drop_lines(lines, ["art/a.png"])
        self.assertEqual((errors, warnings), (1, 0))
        self.assertEqual(kept, [*lines[:2], "CHECK summary files=2 errors=2 warnings=0"])


class CheckTest(unittest.TestCase):
    """project_check and run_import over a faked Godot."""

    def run_project_check(self, rc: int, lines: list[str], pointers: list[str] | None) -> tuple[bool, str]:
        printed = io.StringIO()
        with mock.patch.object(check, "godot", return_value=Result(rc, "\n".join(lines) + "\n", False, 5.0)), \
                mock.patch("sys.stdout", printed):  # fmt: skip
            passed = check.project_check(None, pointers)
        return passed, printed.getvalue()

    def test_only_pointer_lines_pass_with_one_summary_line(self) -> None:
        lines = [line for line in PROBED if "user.gd" not in line]
        passed, said = self.run_project_check(1, lines, ["art/a.png"])
        self.assertTrue(passed, said)
        self.assertNotIn("FAIL", said)
        summary = [line for line in said.splitlines() if "LFS pointer" in line]
        self.assertEqual(
            summary,
            [
                "  skip  1 LFS pointer file skipped (CI checks out without LFS content): kept out of the import; 6 error"
                " and 1 warning lines of the project check about them dropped; credits still checked"
            ],
        )
        self.assertIn("  ok    files=6 errors=0 warnings=0", said)

    def test_locally_the_same_lines_fail(self) -> None:
        lines = [line for line in PROBED if "user.gd" not in line]
        passed, said = self.run_project_check(1, lines, None)
        self.assertFalse(passed)
        self.assertIn("  FAIL  core/io/resource_loader.cpp:317: Failed loading resource: res://art/a.png.", said)
        self.assertNotIn("LFS pointer", said)

    def test_another_error_still_fails_in_ci(self) -> None:
        passed, said = self.run_project_check(1, PROBED, ["art/a.png"])
        self.assertFalse(passed)
        self.assertIn('  FAIL  res://user.gd:5: Parse Error: Could not resolve external class member "TEX".', said)
        self.assertIn("1 LFS pointer file skipped", said)

    def test_the_import_runs_without_the_pointer_files_in_ci_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = repo(Path(tmp))
            write(root, "art/a.png", POINTER)
            write(root, "art/a.png.import", "[remap]\n")
            seen: list[bool] = []

            def fake_godot(*_args: object, **_kwargs: object) -> Result:
                seen.append((root / "art/a.png").exists() or (root / "art/a.png.import").exists())
                return Result(0, "", False, 1.0)

            for ci in (True, False):
                with mock.patch.object(common, "ROOT", root), mock.patch.object(common, "IS_CI", ci), \
                        mock.patch.object(check, "godot", fake_godot), \
                        mock.patch.object(check, "record_import"):  # fmt: skip
                    check.run_import()
                self.assertEqual((root / "art/a.png").read_bytes(), POINTER)
            self.assertEqual(seen, [False, True])

    def test_the_import_in_ci_runs_in_a_folder_that_is_not_a_git_work_tree(self) -> None:
        # Runner tests import throwaway projects in plain temp folders; in CI (CI=true) git cannot list their files,
        # and the import must still run (the review of #515).
        for attributes in (None, ATTRIBUTES):
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                if attributes:
                    write(root, ".gitattributes", attributes)
                write(root, "art/a.png", POINTER)
                calls: list[object] = []
                with mock.patch.object(common, "ROOT", root), mock.patch.object(common, "IS_CI", True), \
                        mock.patch.object(check, "godot", lambda *a, **k: calls.append(a) or Result(0, "", False, 1.0)), \
                        mock.patch.object(check, "record_import"):  # fmt: skip
                    self.assertEqual(check.run_import(), [])
                self.assertEqual(len(calls), 1)
                self.assertEqual(lfs.pointers(root), [])

    def test_lfs_content_fails_on_a_pointer_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = repo(Path(tmp))
            write(root, "art/real.png", png())
            printed = io.StringIO()
            with mock.patch.object(common, "ROOT", root), mock.patch("sys.stdout", printed):
                self.assertEqual(check.main(lfs_content=True), 0)
                write(root, "art/a.png", POINTER)
                self.assertEqual(check.main(lfs_content=True), 1)
            said = printed.getvalue()
            self.assertIn("  FAIL  art/a.png: a Git LFS pointer file, not its content", said)
            self.assertNotIn("art/real.png", said)
            self.assertIn("check --lfs-content: FAILED", said)

    def test_lfs_content_takes_no_paths(self) -> None:
        with mock.patch("sys.stderr", io.StringIO()), mock.patch("sys.stdout", io.StringIO()) as printed:
            self.assertNotEqual(cli.main(["check", "--lfs-content", "res://a.tscn"]), 0)
        self.assertIn("--lfs-content checks every LFS file", printed.getvalue())


SCENE = (
    '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Texture2D" uid="{uid}" path="res://art/a.png" id="1"]\n\n'
    '[node name="S" type="Sprite3D"]\ntexture = ExtResource("1")\n'
)
PRELOAD = 'extends Node\n\nconst TEX: Texture2D = preload("res://art/a.png")\n'
PROJECT = 'config_version=5\n\n[application]\n\nconfig/name="PrimeGame"\n'
UID = "uid://cy2bb7ynws6wi"
IMPORTED_HASH = "0180b64844aadf81c6b18dd2c9268d2e"  # Godot's for res://art/a.png
# A 1x1 PNG's .import file as Godot 4.7.2 wrote it (probed for #515), moved to art/a.png.
IMPORT = f"""[remap]

importer="texture"
type="CompressedTexture2D"
uid="{UID}"
path="res://.godot/imported/a.png-{{hash}}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://art/a.png"
dest_files=["res://.godot/imported/a.png-{{hash}}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


@starts_godot
@unittest.skipUnless(godot_bin(), "needs Godot (GODOT_BIN); CI has it")
class RealPointerTest(unittest.TestCase):
    """A texture imported on a PC with LFS (its .import file committed), then a fresh checkout without LFS content:
    in CI mode the import leaves the .import file as it was and prints no import error, and check passes with the
    summary line; in local mode the same checkout fails as it always did."""

    def test_ci_mode_skips_the_pointer_file_and_local_mode_does_not(self) -> None:
        # A killed engine may still hold files of the temp project for a moment on Windows.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            root = repo(Path(tmp))
            logs = Path(tmp) / "logs"
            logs.mkdir()
            write(root, "project.godot", PROJECT)
            check_script = root / "tools/check/check_project.gd"
            check_script.parent.mkdir(parents=True)
            shutil.copyfile(common.ROOT / "tools/check/check_project.gd", check_script)
            # What the PC with LFS committed: the texture's .import file as Godot 4.7.2 wrote it (an import less to
            # wait for), a scene that refers to it by its uid as the editor writes it, a script that preloads it.
            # A fresh checkout without LFS content: a pointer file and no .godot/.
            committed = IMPORT.replace("{hash}", IMPORTED_HASH)
            write(root, "art/a.png.import", committed)
            write(root, "s.tscn", SCENE.format(uid=UID))
            write(root, "pre.gd", PRELOAD)
            write(root, "art/a.png", POINTER)

            def run(ci: bool, step: object) -> tuple[object, str]:
                printed = io.StringIO()
                with mock.patch.object(common, "ROOT", root), mock.patch.object(common, "OUT", logs.parent), \
                        mock.patch.object(common, "LOGS", logs), mock.patch.object(common, "IS_CI", ci), \
                        mock.patch("sys.stdout", printed):  # fmt: skip
                    value = step()  # type: ignore[operator]
                return value, printed.getvalue()

            run(True, check.run_import)
            self.assertNotIn("Error importing", (logs / "import.log").read_text(encoding="utf-8"))
            self.assertEqual((root / "art/a.png.import").read_text(encoding="utf-8"), committed)
            self.assertEqual((root / "art/a.png").read_bytes(), POINTER)
            passed, said = run(True, lambda: check.project_check(None, lfs.ci_pointers()))
            self.assertTrue(passed, said)
            self.assertIn("1 LFS pointer file skipped", said)

            # The same checkout in local mode: Godot imports the pointer file, fails and rewrites its .import file.
            shutil.rmtree(root / ".godot")
            run(False, check.run_import)
            self.assertIn("Error importing 'res://art/a.png'", (logs / "import.log").read_text(encoding="utf-8"))
            self.assertNotEqual((root / "art/a.png.import").read_text(encoding="utf-8"), committed)
            passed, said = run(False, lambda: check.project_check(None, lfs.ci_pointers()))
            self.assertFalse(passed, said)
            self.assertIn("Failed loading resource: res://art/a.png", said)
            self.assertNotIn("LFS pointer", said)


if __name__ == "__main__":
    unittest.main()
