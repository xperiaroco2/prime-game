"""`lint [--fix] <files or folders>`: which .gd files the arguments stand for (#45: a folder crashed --fix)."""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import lint
from runner.common import Failure


class TargetsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        for name in (
            "net/a.gd",
            "net/deep/b.gd",
            "net/notes.md",
            "addons/x/c.gd",
            "tools/out/d.gd",
            "e.gd",
            ".claude/worktrees/9/net/f.gd",
            ".godot/g.gd",
            "docs/history/h.gd",
            "tests/.hidden/i.gd",
        ):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("extends Node\n", encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def names(self, files: list[str]) -> list[str]:
        return [p.relative_to(self.root).as_posix() for p in lint.targets_of(files, self.root)]

    def test_a_folder_stands_for_every_gd_file_below_it(self) -> None:
        self.assertEqual(self.names(["net"]), ["net/a.gd", "net/deep/b.gd"])
        self.assertEqual(self.names(["net/"]), ["net/a.gd", "net/deep/b.gd"])

    def test_files_and_folders_mix_without_duplicates(self) -> None:
        self.assertEqual(self.names(["e.gd", "net/deep/b.gd", "net"]), ["e.gd", "net/deep/b.gd", "net/a.gd"])

    def test_addons_and_tools_out_are_never_linted(self) -> None:
        self.assertEqual(self.names(["addons", "tools", "addons/x/c.gd"]), [])

    def test_a_folder_never_reaches_other_worktrees_or_non_project_folders(self) -> None:
        """`lint --fix .` from the main checkout must not reformat other sessions' worktrees or the archive."""
        self.assertEqual(self.names(["."]), ["net/a.gd", "net/deep/b.gd"])
        self.assertEqual(self.names([".claude", "docs", ".godot", "tests"]), [])

    def test_a_file_named_on_its_own_is_linted_wherever_it_is(self) -> None:
        self.assertEqual(self.names(["docs/history/h.gd"]), ["docs/history/h.gd"])

    def test_a_missing_path_fails_by_name(self) -> None:
        with self.assertRaises(Failure) as caught:
            lint.targets_of(["net/missing.gd"], self.root)
        self.assertIn("net/missing.gd", str(caught.exception))

    def test_a_path_outside_the_project_fails(self) -> None:
        with self.assertRaises(Failure) as caught:
            lint.targets_of(["../e.gd"], self.root / "net")
        self.assertIn("outside the project", str(caught.exception))

    def test_a_folder_outside_the_project_fails_before_it_is_walked(self) -> None:
        with mock.patch.object(Path, "rglob", side_effect=AssertionError("walked")), self.assertRaises(Failure) as caught:
            lint.targets_of([".."], self.root / "net")
        self.assertIn("..: outside the project", str(caught.exception))


class FixOnAFolderTest(unittest.TestCase):
    def test_fix_on_a_folder_hands_only_files_to_gdtoolkit(self) -> None:
        """The #40 crash: `lint --fix net tests` passed the folders on and strip_cr read a folder."""
        seen: list[Path] = []

        def fake_gdscript(targets: list[Path], fix: bool) -> bool:
            self.assertTrue(fix)
            seen.extend(targets)
            for path in targets:
                self.assertTrue(path.is_file(), path)
            return False

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("net/a.gd", "net/deep/b.gd", "tests/c.gd"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("extends Node\n", encoding="utf-8")
            with (
                mock.patch.object(lint, "ROOT", root),
                mock.patch.object(lint, "gdscript", fake_gdscript),
                mock.patch.object(lint, "say"),
            ):
                self.assertEqual(lint.main(fix=True, files=["net", "tests"]), 0)
            self.assertEqual(seen, [root / "net/a.gd", root / "net/deep/b.gd", root / "tests/c.gd"])


if __name__ == "__main__":
    unittest.main()
