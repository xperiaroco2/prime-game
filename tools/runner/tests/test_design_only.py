"""The design-only list and check (#1123, tools/runner/design_only.py): which changes skip the Godot check."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import design_only
from runner.common import ROOT, force_rmtree


def git(where: Path, *args: str) -> str:
    res = subprocess.run(
        ["git", *args], cwd=where, capture_output=True, text=True, encoding="utf-8", timeout=120,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )  # fmt: skip
    if res.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {res.stderr}")
    return res.stdout.strip()


# Paths the list must take and paths it must refuse, with the repository's own list.
ON = (
    "docs/GDD.md",
    "docs/design/COMPASS.md",
    "docs/design/m8-match.md",
    "docs/design/ideas/README.md",
    "docs/design/ideas/2026-10-15-brainstorm-1.md",
    "docs/design/research/2026-10-15-harder-tasks.md",
    "docs/design/research/deeper/one.md",
)
OFF = (
    "docs/design/house-map.md",  # the level tests read it
    "docs/design/house-map/level-0.svg",
    "docs/design/tutorial.md",
    "docs/design/research/sketch.png",  # Markdown only
    "docs/GDD.md.bak",
    "docs/ARCHITECTURE.md",
    "content/roles/x.tres",
    "core/match/match.gd",
    ".github/design-only-paths.txt",  # the list itself
    "tools/runner/design_only.py",
)


class ListTest(unittest.TestCase):
    def test_the_repository_list_takes_only_the_design_docs(self) -> None:
        pats = design_only.patterns()
        self.assertTrue(pats)
        self.assertEqual(design_only.PATHS, ROOT / design_only.LIST)
        for name in ON:
            with self.subTest(name=name):
                self.assertTrue(design_only.on_list(name, pats), name)
        for name in OFF:
            with self.subTest(name=name):
                self.assertFalse(design_only.on_list(name, pats), name)
        self.assertEqual(design_only.off_list([*ON, *OFF], pats), list(OFF))

    def test_comments_and_blank_lines_are_no_patterns_and_a_missing_file_has_none(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "list.txt"
            path.write_bytes(b"# a comment\n\n  docs/a.md  \n   # indented\ndocs/b/*.md\n")
            self.assertEqual(design_only.patterns(path), ("docs/a.md", "docs/b/*.md"))
            self.assertEqual(design_only.patterns(Path(tmp) / "none.txt"), ())

    def test_a_star_matches_across_slashes(self) -> None:
        self.assertTrue(design_only.on_list("docs/b/c/d.md", ("docs/b/*.md",)))
        self.assertFalse(design_only.on_list("docs/b/c/d.mdx", ("docs/b/*.md",)))
        self.assertFalse(design_only.on_list("Docs/a.md", ("docs/a.md",)), "case matters, as in git")


class CheckTest(unittest.TestCase):
    """check() against origin/<base> in a scratch repository with the real list."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="design-only-"))
        self.addCleanup(force_rmtree, str(self.tmp))
        git(self.tmp, "init", "-q", "--bare", "-b", "main", "remote.git")
        git(self.tmp, "clone", "-q", str(self.tmp / "remote.git"), "work")
        self.root = self.tmp / "work"
        for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
            git(self.root, "config", key, value)
        self.write(design_only.LIST, design_only.PATHS.read_text(encoding="utf-8"))
        for name in ("docs/GDD.md", "docs/design/house-map.md", "core/a.gd", "docs/design/ideas/old.md"):
            self.write(name, "x\n")
        git(self.root, "add", ".")
        git(self.root, "commit", "-q", "-m", "base")
        git(self.root, "push", "-q", "origin", "main")
        git(self.root, "switch", "-q", "-c", "content/1-x")
        mock.patch.object(design_only.common, "IS_CI", False).start()
        self.addCleanup(mock.patch.stopall)

    def write(self, name: str, text: str) -> None:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode("utf-8"))

    def test_committed_staged_unstaged_and_untracked_design_docs_are_design_only(self) -> None:
        self.write("docs/GDD.md", "y\n")
        git(self.root, "commit", "-q", "-am", "gdd")
        self.write("docs/design/COMPASS.md", "new\n")
        git(self.root, "add", "docs/design/COMPASS.md")  # staged
        self.write("docs/design/ideas/old.md", "y\n")  # unstaged
        self.write("docs/design/research/r.md", "new\n")  # untracked
        names, _why = design_only.changed_paths(self.root)
        self.assertEqual(
            names,
            ["docs/GDD.md", "docs/design/COMPASS.md", "docs/design/ideas/old.md", "docs/design/research/r.md"],
        )
        design, why = design_only.check(self.root)
        self.assertTrue(design, why)
        self.assertIn("4 changed files against origin/main", why)

    def test_one_path_off_the_list_runs_everything(self) -> None:
        for other in ("docs/design/house-map.md", "core/a.gd", design_only.LIST):
            with self.subTest(other=other):
                git(self.root, "reset", "-q", "--hard", "origin/main")
                self.write("docs/GDD.md", "y\n")
                self.write(other, (self.root / other).read_text(encoding="utf-8") + "# changed\n")
                design, why = design_only.check(self.root)
                self.assertFalse(design)
                self.assertIn(f"{other} not on {design_only.LIST}", why)

    def test_a_deleted_or_renamed_file_counts_by_its_old_path(self) -> None:
        self.write("docs/GDD.md", "y\n")
        git(self.root, "rm", "-q", "core/a.gd")
        self.assertFalse(design_only.check(self.root)[0], "deleting code is no design change")
        git(self.root, "reset", "-q", "--hard", "origin/main")
        git(self.root, "mv", "core/a.gd", "docs/design/ideas/a.md")
        design, why = design_only.check(self.root)
        self.assertFalse(design)
        self.assertIn("core/a.gd", why)

    def test_no_change_no_base_or_no_list_is_not_design_only(self) -> None:
        design, why = design_only.check(self.root)
        self.assertEqual((design, why.startswith("no change against origin/main")), (False, True), why)
        self.write("docs/GDD.md", "y\n")
        git(self.root, "config", "branch.content/1-x.primeBase", "gone/2-parent")
        design, why = design_only.check(self.root)
        self.assertEqual((design, "no merge base with origin/gone/2-parent" in why), (False, True), why)
        git(self.root, "config", "--unset", "branch.content/1-x.primeBase")
        self.assertTrue(design_only.check(self.root)[0])
        with mock.patch.object(design_only, "patterns", return_value=()):
            self.assertEqual(design_only.check(self.root), (False, f"{design_only.LIST} has no pattern"))

    def test_never_on_ci(self) -> None:
        self.write("docs/GDD.md", "y\n")
        with mock.patch.object(design_only.common, "IS_CI", True):
            design, why = design_only.check(self.root)
        self.assertFalse(design)
        self.assertIn("changes", why)


if __name__ == "__main__":
    unittest.main()
