"""`lint [--fix] <files or folders>`: which .gd files the arguments stand for (#45: a folder crashed --fix)."""

import contextlib
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import lint
from runner.common import Failure, force_rmtree


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
                self.assertEqual(lint.main(fix=True, files=["net", "tests"], verbose=True), 0)
            self.assertEqual(seen, [root / "net/a.gd", root / "net/deep/b.gd", root / "tests/c.gd"])


class InstructionFilesTest(unittest.TestCase):
    def failures(self, errors: list[str]) -> list[str]:
        report = lint.instructions.Report()
        report.errors = errors
        bad = mock.Mock()
        with mock.patch.object(lint.instructions, "check", return_value=report), mock.patch.object(lint, "bad", bad):
            self.assertTrue(lint.instruction_files())
        return [c.args[0] for c in bad.call_args_list]

    def test_the_budget_hint_follows_only_a_budget_error(self) -> None:
        over = ".claude/rules/x.md: 61 lines, budget 60"
        self.assertEqual(self.failures([over]), [over, "instruction files over budget"])
        # #415: a broken link to orchestrate-stage's budget.md or the weekly budget ADR is no budget problem.
        link = ".claude/skills/orchestrate-stage/SKILL.md:1: link budget.md names no file"
        self.assertEqual(self.failures([link]), [link])


def git(where: Path, *args: str) -> str:
    res = subprocess.run(
        ["git", *args], cwd=where, capture_output=True, text=True, encoding="utf-8", timeout=120,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )  # fmt: skip
    if res.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {res.stderr}")
    return res.stdout.strip()


def clone(tmp: Path, name: str) -> Path:
    git(tmp, "clone", "-q", str(tmp / "remote.git"), name)
    for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
        git(tmp / name, "config", key, value)
    return tmp / name


class ChangedTest(unittest.TestCase):
    """`lint --changed` (#859): gdformat and gdlint on the .gd files changed against origin/<base> only, the
    repo-wide checks whole; every file where the base is unknown, the lint configuration changed, or on CI."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="lint-changed-"))
        self.addCleanup(force_rmtree, str(self.tmp))
        git(self.tmp, "init", "-q", "--bare", "-b", "main", "remote.git")
        self.root = clone(self.tmp, "work")
        for name in ("core/a.gd", "core/b.gd", "net/c.gd", "net/gone.gd", "gdlintrc", "docs/x.md"):
            self.write(name, "extends Node\n")
        git(self.root, "add", ".")
        git(self.root, "commit", "-q", "-m", "base")
        git(self.root, "push", "-q", "origin", "main")
        git(self.root, "switch", "-q", "-c", "tooling/1-x")
        mock.patch.object(lint.common, "IS_CI", False).start()
        self.addCleanup(mock.patch.stopall)

    def write(self, name: str, text: str, root: Path | None = None) -> None:
        path = (root or self.root) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def every(self) -> list[Path]:
        """The whole lint's targets, as gd_files finds them in the project."""
        return sorted(p for p in self.root.rglob("*.gd") if ".git" not in p.parts)

    def picked(self) -> tuple[list[str] | None, str]:
        files, why = lint.changed_targets(self.root, self.every())
        return (None if files is None else [p.relative_to(self.root).as_posix() for p in files]), why

    def test_committed_staged_unstaged_and_untracked_changes_count_and_a_deleted_file_is_left_out(self) -> None:
        self.write("core/a.gd", "extends Node2D\n")
        git(self.root, "commit", "-q", "-am", "a")
        self.write("core/b.gd", "extends Node3D\n")  # unstaged
        self.write("net/new.gd", "extends Node\n")  # untracked
        git(self.root, "rm", "-q", "net/gone.gd")
        self.write("docs/x.md", "text\n")  # no GDScript
        files, why = self.picked()
        self.assertEqual(files, ["core/a.gd", "core/b.gd", "net/new.gd"])
        self.assertIn("origin/main", why)

    def test_a_moved_main_adds_nothing_the_branch_did_not_change(self) -> None:
        self.write("core/a.gd", "extends Node2D\n")
        git(self.root, "commit", "-q", "-am", "mine")
        other = clone(self.tmp, "other")
        self.write("net/c.gd", "extends Node2D\n", other)
        git(other, "commit", "-q", "-am", "main moves")
        git(other, "push", "-q", "origin", "main")
        git(self.root, "fetch", "-q", "origin")
        self.assertEqual(self.picked()[0], ["core/a.gd"])

    def test_a_recorded_parent_is_the_base(self) -> None:
        self.write("core/a.gd", "extends Node2D\n")
        git(self.root, "commit", "-q", "-am", "the parent's")
        git(self.root, "push", "-q", "origin", "HEAD:net/2-parent")
        git(self.root, "switch", "-q", "-c", "tooling/3-child")
        git(self.root, "config", "branch.tooling/3-child.primeBase", "net/2-parent")
        self.write("core/b.gd", "extends Node3D\n")
        files, why = self.picked()
        self.assertEqual(files, ["core/b.gd"])
        self.assertIn("origin/net/2-parent", why)

    def test_a_changed_lint_configuration_or_tool_gives_the_whole_lint(self) -> None:
        for name in lint.LINT_CONFIG:
            with self.subTest(name=name):
                self.write("core/a.gd", "extends Node2D\n")
                self.write(name, "changed\n")
                files, why = self.picked()
                self.assertIsNone(files)
                self.assertIn(name, why)
                git(self.root, "reset", "-q", "--hard")
                git(self.root, "clean", "-q", "-fd")

    def test_an_unresolvable_base_gives_the_whole_lint(self) -> None:
        git(self.root, "config", "branch.tooling/1-x.primeBase", "no/such-branch")
        files, why = self.picked()
        self.assertIsNone(files)
        self.assertIn("origin/no/such-branch", why)

    def test_on_ci_the_lint_is_whole(self) -> None:
        with mock.patch.object(lint.common, "IS_CI", True):
            self.assertIsNone(self.picked()[0])

    def lint_main(self, changed: bool, red_gd: bool = False, red_refs: bool = False) -> tuple[int, list[str], str]:
        seen: list[str] = []

        def fake_gdscript(targets: list[Path], fix: bool) -> bool:
            seen.extend(p.relative_to(self.root).as_posix() for p in targets)
            return red_gd

        out = io.StringIO()
        with (
            mock.patch.object(lint, "ROOT", self.root),
            mock.patch.object(lint, "gd_files", self.every),
            mock.patch.object(lint, "gdscript", fake_gdscript),
            mock.patch.object(lint, "instruction_files", return_value=False) as budgets,
            mock.patch.object(lint, "section_refs", return_value=red_refs) as refs,
            contextlib.redirect_stdout(out),
        ):
            rc = lint.main(verbose=True, changed=changed)
        budgets.assert_called_once()  # the repo-wide checks run whole either way
        refs.assert_called_once()
        return rc, seen, out.getvalue()

    def test_lint_changed_lints_the_changed_file_only_and_says_so(self) -> None:
        self.write("core/a.gd", "extends Node2D\n")
        rc, seen, text = self.lint_main(changed=True)
        self.assertEqual((rc, seen), (0, ["core/a.gd"]))
        self.assertIn("lint: changed files only (1 of 4)", text)
        self.assertEqual(text.splitlines()[-1], "lint: passed, changed files only (1 of 4)")
        self.assertEqual(lint.take_scope(), {"changed_only": [1, 4]})
        self.assertEqual(lint.take_scope(), {})  # taken once

    def test_lint_changed_fails_on_a_bad_changed_file_and_on_a_broken_section_reference(self) -> None:
        self.write("core/a.gd", "extends Node2D\n")
        self.assertEqual(self.lint_main(changed=True, red_gd=True)[0], 1)
        rc, seen, _text = self.lint_main(changed=True, red_refs=True)
        self.assertEqual((rc, seen), (1, ["core/a.gd"]))

    def test_plain_lint_lints_every_file(self) -> None:
        self.write("core/a.gd", "extends Node2D\n")
        rc, seen, text = self.lint_main(changed=False)
        self.assertEqual((rc, seen), (0, ["core/a.gd", "core/b.gd", "net/c.gd", "net/gone.gd"]))
        self.assertNotIn("changed files only", text)
        self.assertEqual(lint.take_scope(), {})

    def test_a_fallback_lints_every_file_and_says_why(self) -> None:
        self.write("gdlintrc", "changed\n")
        rc, seen, text = self.lint_main(changed=True)
        self.assertEqual((rc, len(seen)), (0, 4))
        why = "the lint's configuration or tool changed (gdlintrc)"
        self.assertIn(f"lint: every file: {why}", text)
        self.assertEqual(lint.take_scope(), {"changed_fallback": why})

    def test_changed_with_paths_is_refused(self) -> None:
        with self.assertRaises(Failure):
            lint.main(files=["core"], changed=True, verbose=True)


if __name__ == "__main__":
    unittest.main()
