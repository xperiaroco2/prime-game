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

    def test_gdignored_folder_is_skipped(self) -> None:
        write(self.root, "docs/.gdignore", "")
        write(self.root, "docs/old.gd", "extends Node\n")
        self.assertEqual(uids.lint(self.root).errors, [])


if __name__ == "__main__":
    unittest.main()
