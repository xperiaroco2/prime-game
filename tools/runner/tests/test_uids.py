"""UID lint: the mistakes Godot does not report itself must fail."""

import tempfile
import unittest
from pathlib import Path

from runner import uids

SCRIPT_UID = "uid://bscript00001"
A_UID = "uid://baaaaaaaaaaa1"
B_UID = "uid://bbbbbbbbbbbb1"


def write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class UidLintTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        write(self.root, "project.godot", "config_version=5\n")
        write(self.root, "scripts/item.gd", "extends Resource\n")
        write(self.root, "scripts/item.gd.uid", SCRIPT_UID + "\n")
        write(self.root, "content/a.tres", f'[gd_resource type="Resource" format=3 uid="{A_UID}"]\n')
        write(self.root, "content/b.tres", f'[gd_resource type="Resource" format=3 uid="{B_UID}"]\n')

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def scene(self, uid: str, path: str) -> None:
        write(
            self.root,
            "levels/room.tscn",
            f'[gd_scene format=3]\n\n[ext_resource type="Resource" uid="{uid}" path="{path}" id="1"]\n',
        )

    def test_clean_project_passes(self) -> None:
        self.scene(A_UID, "res://content/a.tres")
        self.assertEqual(uids.lint(self.root).errors, [])

    def test_task_worktrees_are_not_part_of_the_project(self) -> None:
        # `start` puts whole copies of the project in .claude/worktrees/<n>; Godot skips hidden directories too.
        self.scene(A_UID, "res://content/a.tres")
        write(self.root, ".claude/worktrees/12/content/a.tres", f'[gd_resource type="Resource" format=3 uid="{A_UID}"]\n')
        write(self.root, ".claude/worktrees/12/scripts/item.gd.uid", SCRIPT_UID + "\n")
        self.assertEqual(uids.lint(self.root).errors, [])

    def test_uid_of_another_file_fails(self) -> None:
        self.scene(B_UID, "res://content/a.tres")
        errors = uids.lint(self.root).errors
        self.assertEqual(len(errors), 1)
        self.assertIn("belongs to res://content/b.tres", errors[0])
        self.assertIn("levels/room.tscn:3", errors[0])

    def test_unknown_uid_fails(self) -> None:
        self.scene("uid://bunknown00001", "res://content/a.tres")
        self.assertIn("is unknown", uids.lint(self.root).errors[0])

    def test_path_only_reference_passes(self) -> None:
        write(self.root, "levels/room.tscn", '[gd_scene format=3]\n\n[ext_resource path="res://content/a.tres" id="1"]\n')
        self.assertEqual(uids.lint(self.root).errors, [])

    def test_duplicate_header_uid_fails(self) -> None:
        write(self.root, "content/copy.tres", f'[gd_resource type="Resource" format=3 uid="{A_UID}"]\n')
        self.assertTrue(any("duplicate" in e for e in uids.lint(self.root).errors))

    def test_copied_sidecar_fails(self) -> None:
        write(self.root, "scripts/item_copy.gd", "extends Resource\n")
        write(self.root, "scripts/item_copy.gd.uid", SCRIPT_UID + "\n")
        self.assertTrue(any("duplicate" in e for e in uids.lint(self.root).errors))

    def test_script_without_sidecar_fails(self) -> None:
        write(self.root, "scripts/new.gd", "extends Node\n")
        self.assertTrue(any("missing new.gd.uid" in e for e in uids.lint(self.root).errors))

    def test_orphan_sidecar_fails(self) -> None:
        write(self.root, "scripts/gone.gd.uid", "uid://bgone000000001\n")
        errors = uids.lint(self.root).errors
        self.assertEqual(errors, ["res://scripts/gone.gd.uid: sidecar without its file res://scripts/gone.gd"])

    def test_orphan_sidecar_in_scratch_passes(self) -> None:
        # #264: a probe deleted without its .gd.uid; `test` and `lint` leave tests/scratch/ out, so does this lint.
        write(self.root, "tests/scratch/x.gd.uid", "uid://bscratch00001\n")
        self.assertEqual(uids.lint(self.root).errors, [])

    def test_scratch_files_are_not_checked_themselves(self) -> None:
        # A half-written probe: a script whose sidecar the next import writes, a malformed sidecar, a scene with a
        # stale uid. None of it is committed, and Godot falls back to path= for an unknown uid.
        write(self.root, "tests/scratch/probe_test.gd", "extends Node\n")
        write(self.root, "tests/scratch/half.gd.uid", "not a uid\n")
        write(self.root, "tests/scratch/half.gd", "extends Node\n")
        write(
            self.root,
            "tests/scratch/probe.tscn",
            '[gd_scene format=3]\n\n'
            '[ext_resource type="Resource" uid="uid://bunknown00001" path="res://content/a.tres" id="1"]\n',
        )
        self.assertEqual(uids.lint(self.root).errors, [])

    def test_scratch_reference_does_not_own_or_resolve_uids(self) -> None:
        # A scratch scene that points a real uid at another path is the probe's own business, not a lint error.
        write(
            self.root,
            "tests/scratch/probe.tscn",
            f'[gd_scene format=3]\n\n[ext_resource type="Resource" uid="{B_UID}" path="res://content/a.tres" id="1"]\n',
        )
        self.assertEqual(uids.lint(self.root).errors, [])

    def test_uid_copied_into_scratch_still_fails(self) -> None:
        # Godot still imports tests/scratch/: whichever file it scans last owns a duplicate uid, so a real reference
        # could load the probe's copy. A copied .tres or a copied sidecar there stays a duplicate.
        write(self.root, "tests/scratch/a_copy.tres", f'[gd_resource type="Resource" format=3 uid="{A_UID}"]\n')
        write(self.root, "tests/scratch/item_copy.gd", "extends Resource\n")
        write(self.root, "tests/scratch/item_copy.gd.uid", SCRIPT_UID + "\n")
        errors = uids.lint(self.root).errors
        self.assertEqual(
            errors,
            [
                f"duplicate {A_UID}: res://content/a.tres, res://tests/scratch/a_copy.tres"
                " (never copy a uid or a .uid file)",
                f"duplicate {SCRIPT_UID}: res://scripts/item.gd, res://tests/scratch/item_copy.gd"
                " (never copy a uid or a .uid file)",
            ],
        )

    def test_real_scene_never_resolves_to_a_scratch_file(self) -> None:
        # A uid only a scratch file claims is unknown to the project: the probe goes when it is deleted.
        probe_uid = "uid://bprobe0000001"
        write(self.root, "tests/scratch/probe.tres", f'[gd_resource type="Resource" format=3 uid="{probe_uid}"]\n')
        self.scene(probe_uid, "res://tests/scratch/probe.tres")
        errors = uids.lint(self.root).errors
        self.assertEqual(len(errors), 1)
        self.assertIn("is unknown", errors[0])

    def test_scratch_name_elsewhere_is_checked(self) -> None:
        # Only the folder tests/scratch/ is left out, not every folder called scratch.
        write(self.root, "content/scratch/gone.gd.uid", "uid://bgone000000001\n")
        write(self.root, "tests/scratchy/gone.gd.uid", "uid://bgone000000002\n")
        self.assertEqual(len(uids.lint(self.root).errors), 2)

    def test_gdignored_folder_is_skipped(self) -> None:
        write(self.root, "docs/.gdignore", "")
        write(self.root, "docs/old.gd", "extends Node\n")
        self.assertEqual(uids.lint(self.root).errors, [])


if __name__ == "__main__":
    unittest.main()
