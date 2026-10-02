"""An own user:// per linked worktree (override.cfg) and per process (the app-data variable), #182."""

import contextlib
import io
import os
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import check, common
from runner.common import godot_bin
from runner.verify import starts_godot

PROJECT = 'config_version=5\n\n[application]\n\nconfig/name="PrimeGame"\n'
PROBE = (
    'extends SceneTree\n\n\nfunc _initialize() -> void:\n\tprint("user_data_dir=", OS.get_user_data_dir())\n\tquit(0)\n'
)
# What the editor's Project Settings dialog does on a change: ProjectSettings.save().
SAVE = "extends SceneTree\n\n\nfunc _initialize() -> void:\n\tquit(ProjectSettings.save())\n"


def policy_for(root: Path) -> list[str]:
    with mock.patch.object(check, "ROOT", root):
        return check.user_dir_policy()


def checkout(parent: Path, name: str, linked: bool) -> Path:
    """A project folder: a linked worktree has a .git file, the main checkout (or a clone) a .git folder."""
    root = parent / name
    root.mkdir(parents=True)
    if linked:
        (root / ".git").write_text(f"gitdir: {parent.as_posix()}/.git/worktrees/{name}\n", encoding="utf-8")
    else:
        (root / ".git").mkdir()
    (root / "project.godot").write_text(PROJECT, encoding="utf-8")
    return root


class OverrideTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.parent = Path(tmp.name)

    def test_a_linked_worktree_gets_an_override_naming_its_own_folder(self) -> None:
        root = checkout(self.parent, "182", linked=True)
        path = common.ensure_user_dir(root)
        self.assertEqual(path, root / "override.cfg")
        text = (root / "override.cfg").read_text(encoding="utf-8")
        self.assertTrue(text.startswith(common.OVERRIDE_MARK))
        self.assertIn("[application]\n\nconfig/use_custom_user_dir=true\n", text)
        name = common.user_dir_name(root)
        self.assertIn(f'config/custom_user_dir_name="{name}"\n', text)
        self.assertRegex(name, r"^[Gg]odot/app_userdata/PrimeGame-182-[0-9a-f]{6}$")

    def test_the_main_checkout_and_a_clone_get_none(self) -> None:
        root = checkout(self.parent, "prime-game", linked=False)
        self.assertIsNone(common.ensure_user_dir(root))
        self.assertFalse((root / "override.cfg").exists())
        self.assertIsNone(common.worktree_user_dir(root))

    def test_two_worktrees_with_the_same_folder_name_get_two_folders(self) -> None:
        one = checkout(self.parent / "clone-a", "182", linked=True)
        two = checkout(self.parent / "clone-b", "182", linked=True)
        self.assertNotEqual(common.user_dir_name(one), common.user_dir_name(two))
        self.assertEqual(common.user_dir_name(one), common.user_dir_name(one))

    def test_the_name_follows_the_project_and_keeps_only_safe_characters(self) -> None:
        root = checkout(self.parent, "m5 #12", linked=True)
        (root / "project.godot").write_text('[application]\nconfig/name="Other"\n', encoding="utf-8")
        self.assertRegex(common.user_dir_name(root), r"/app_userdata/Other-m5--12-[0-9a-f]{6}$")

    def test_godots_own_folder_name_per_os(self) -> None:
        root = checkout(self.parent, "182", linked=True)
        with mock.patch.object(common, "IS_LINUX", True):
            self.assertTrue(common.user_dir_name(root).startswith("godot/app_userdata/"))
        with mock.patch.object(common, "IS_LINUX", False):
            self.assertTrue(common.user_dir_name(root).startswith("Godot/app_userdata/"))

    def test_an_unchanged_override_is_not_rewritten_and_a_stale_one_is(self) -> None:
        root = checkout(self.parent, "182", linked=True)
        path = common.ensure_user_dir(root)
        assert path is not None
        os.utime(path, (1, 1))
        common.ensure_user_dir(root)
        self.assertEqual(path.stat().st_mtime, 1)
        path.write_text(common.OVERRIDE_MARK + ": an older runner's text\n", encoding="utf-8")
        common.ensure_user_dir(root)
        self.assertEqual(path.read_text(encoding="utf-8"), common.override_text(root))

    def test_a_hand_made_override_is_left_alone_with_a_warning(self) -> None:
        root = checkout(self.parent, "182", linked=True)
        (root / "override.cfg").write_text("[display]\nwindow/size/mode=2\n", encoding="utf-8")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            common.ensure_user_dir(root)
        self.assertEqual((root / "override.cfg").read_text(encoding="utf-8"), "[display]\nwindow/size/mode=2\n")
        self.assertIn("was not written by the runner", out.getvalue())

    def test_every_godot_start_through_the_runner_ensures_it(self) -> None:
        root = checkout(self.parent, "182", linked=True)
        with (
            mock.patch.object(common, "ROOT", root),
            mock.patch.object(common, "godot_bin", return_value="godot"),
            mock.patch.object(common, "check_godot_version"),
        ):
            self.assertEqual(common.require_godot(), "godot")
        self.assertTrue((root / "override.cfg").is_file())

    def test_the_worktrees_folder_on_this_machine(self) -> None:
        root = checkout(self.parent, "182", linked=True)
        data = self.parent / "appdata"
        with mock.patch.object(common, "IS_WINDOWS", True), mock.patch.dict(os.environ, {"APPDATA": str(data)}):
            self.assertEqual(common.app_data_var(), "APPDATA")
            self.assertEqual(common.worktree_user_dir(root), data / common.user_dir_name(root))
        linux = {"IS_WINDOWS": False, "IS_LINUX": True}
        xdg = {"XDG_DATA_HOME": str(data)}
        with mock.patch.multiple(common, **linux), mock.patch.dict(os.environ, xdg):  # type: ignore[arg-type]
            self.assertEqual(common.app_data_var(), "XDG_DATA_HOME")
            self.assertEqual(common.worktree_user_dir(root), data / common.user_dir_name(root))
        relative = {"XDG_DATA_HOME": "relative/path", "HOME": str(self.parent)}
        with mock.patch.multiple(common, **linux), mock.patch.dict(os.environ, relative):  # type: ignore[arg-type]
            # Godot ignores a relative XDG_DATA_HOME and falls back to ~/.local/share.
            self.assertEqual(common.app_data_dir(), self.parent / ".local" / "share")
        with mock.patch.multiple(common, IS_WINDOWS=False, IS_LINUX=False):  # type: ignore[arg-type]
            self.assertIsNone(common.app_data_var())
            self.assertIsNone(common.worktree_user_dir(root))


class ProjectKeepsTheDefaultTest(unittest.TestCase):
    def test_check_fails_on_the_override_keys_in_project_godot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = checkout(Path(tmp), "182", linked=True)
            self.assertEqual(policy_for(root), [])
            keys = common.override_text(root).split("[application]\n", 1)[1]
            (root / "project.godot").write_text(PROJECT + keys + "\n[debug]\n\nx=1\n", encoding="utf-8")
            problems = policy_for(root)
            self.assertEqual(len(problems), 2, problems)
            self.assertIn("config/use_custom_user_dir=true", problems[0])
            self.assertIn(common.user_dir_name(root), problems[1])


@starts_godot
@unittest.skipUnless(godot_bin(), "needs Godot (GODOT_BIN); CI has it")
class RealUserDirTest(unittest.TestCase):
    """Godot 4.7.2 itself, in throwaway projects: the override names a worktree's user://, the main checkout keeps
    the default, and the app-data variable gives each process a user:// of its own (what the shards rely on)."""

    def user_data_dir(self, project: Path, data: Path) -> str:
        var = common.app_data_var()
        assert var is not None, "Windows or Linux"
        exe = str(godot_bin())
        cmd = [exe, "--no-header", "--headless", "--path", str(project), "-s", "res://probe.gd"]
        res = common.run(cmd, timeout=60, cwd=project, env={var: str(data)})
        match = re.search(r"^user_data_dir=(.+)$", res.out, re.MULTILINE)
        self.assertIsNotNone(match, res.out)
        assert match is not None
        return os.path.normcase(os.path.normpath(match.group(1).strip()))

    def test_worktrees_and_processes_each_get_their_own(self) -> None:
        if common.app_data_var() is None:
            self.skipTest("no per-process user:// on this OS")
        # A killed engine may still hold files of the temp project for a moment on Windows.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            parent = Path(tmp)
            main = checkout(parent, "main", linked=False)
            worktree = checkout(parent / "main" / ".claude" / "worktrees", "182", linked=True)
            for project in (main, worktree):
                (project / "probe.gd").write_text(PROBE, encoding="utf-8")
                common.ensure_user_dir(project)
            self.assertFalse((main / "override.cfg").exists())
            godot = "godot" if common.IS_LINUX else "Godot"
            seen = {}
            for label, project, data in (
                ("main", main, parent / "data-main"),
                ("worktree, shard 1", worktree, parent / "data-1"),
                ("worktree, shard 2", worktree, parent / "data-2"),
            ):
                found = self.user_data_dir(project, data)
                name = f"{godot}/app_userdata/PrimeGame" if project is main else common.user_dir_name(worktree)
                self.assertEqual(found, os.path.normcase(os.path.normpath(data / name)), label)
                seen[label] = found
            self.assertEqual(len(set(seen.values())), 3)

    def test_saving_project_settings_in_a_worktree_copies_the_override_and_check_sees_it(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            worktree = checkout(Path(tmp), "182", linked=True)
            (worktree / "save.gd").write_text(SAVE, encoding="utf-8")
            common.ensure_user_dir(worktree)
            self.assertEqual(policy_for(worktree), [])
            cmd = [str(godot_bin()), "--no-header", "--headless", "--path", str(worktree), "-s", "res://save.gd"]
            res = common.run(cmd, timeout=60, cwd=worktree)
            self.assertEqual(res.rc, 0, res.out)
            saved = (worktree / "project.godot").read_text(encoding="utf-8")
            self.assertEqual(len(policy_for(worktree)), 2, saved)


if __name__ == "__main__":
    unittest.main()
