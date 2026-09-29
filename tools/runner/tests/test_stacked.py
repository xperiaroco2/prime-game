"""A task stacked on an open PR, end to end: `start --base` on the parent's branch, `publish` onto the parent, then
the parent merged and its branch deleted (GitHub's auto-delete), and `publish` onto main. Real temp repos with the
committed pre-push hook; gh, the board, sessions and verify are stubbed."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import publish, start
from runner.common import ROOT, Failure
from runner.tests.test_githooks import _rmtree
from runner.tests.test_start import git

PARENT = "core/32-parent"
CHILD = "tooling/33-child"


class StackedTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="stacked-"))
        self.addCleanup(_rmtree, str(self.tmp))
        hooks = self.tmp / "hooks"
        hooks.mkdir()
        shutil.copy(ROOT / ".claude" / "githooks" / "pre-push", hooks / "pre-push")
        (hooks / "pre-push").chmod(0o755)
        git(self.tmp, "init", "-q", "--bare", "-b", "main", "remote.git")
        self.work = self.clone("work")  # the child's session
        self.commit(self.work, "f.txt", "c1")
        git(self.work, "push", "-q", "origin", "main")
        git(self.work, "config", "core.hooksPath", str(hooks))
        self.github = self.clone("github")  # the parent's session and the human's merge button
        git(self.github, "switch", "-q", "-c", PARENT)
        self.commit(self.github, "p.txt", "parent")
        git(self.github, "push", "-q", "origin", PARENT)

        self.pr_base: str | None = None  # the child's open PR's base, as gh would report it
        issue = {"number": 33, "title": "Child", "state": "OPEN", "labels": [{"name": "area:tooling"}]}
        issue |= {"assignees": [], "url": "https://github.com/o/r/issues/33"}
        answers = {("issue", "view"): json.dumps(issue), ("api", "user"): "xperiaroco2"}
        for patch in (
            mock.patch.object(start, "REPO", self.work),
            mock.patch.object(start, "_gh", side_effect=lambda *a: answers.get(a[:2], "")),
            mock.patch.object(start.board, "move"),
            mock.patch.object(start.sessions, "active_on", return_value=[]),
            mock.patch.object(publish, "REPO", self.work),
            mock.patch.object(publish, "pr_base", side_effect=lambda branch: self.pr_base),
            mock.patch.object(publish.verify, "main", return_value=0),
        ):
            patch.start()
            self.addCleanup(patch.stop)
        for module in (start, publish):
            for name in ("say", "ok", "warn", "bad"):
                if hasattr(module, name):
                    patch = mock.patch.object(module, name)
                    patch.start()
                    self.addCleanup(patch.stop)

    def clone(self, name: str) -> Path:
        git(self.tmp, "clone", "-q", str(self.tmp / "remote.git"), name)
        where = self.tmp / name
        for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
            git(where, "config", key, value)
        return where

    @staticmethod
    def commit(where: Path, name: str, message: str) -> None:
        (where / name).write_text(f"{message}\n", encoding="utf-8", newline="\n")
        git(where, "add", name)
        git(where, "commit", "-q", "-m", message)

    def remote(self, ref: str) -> str:
        return git(self.tmp / "remote.git", "rev-parse", ref)

    def start_child(self) -> None:
        self.assertEqual(start.main(33, base=PARENT), 0)
        self.commit(self.work, "c.txt", "child")
        self.assertEqual(publish.main(), 0)  # no PR yet: the recorded parent is the base
        self.assertEqual(self.remote(f"{CHILD}~1"), self.remote(PARENT))

    def merge_and_delete_parent(self) -> None:
        """A human merges the parent's PR with a merge commit; auto-delete removes its branch; main moves on."""
        git(self.github, "fetch", "-q")
        git(self.github, "switch", "-q", "main")
        git(self.github, "merge", "-q", "--no-ff", "-m", "Merge the parent", f"origin/{PARENT}")
        self.commit(self.github, "m.txt", "main moves on")
        git(self.github, "push", "-q", "origin", "main")
        git(self.github, "push", "-q", "origin", "--delete", PARENT)

    def own_commits(self) -> list[str]:
        return git(self.work, "log", "--format=%s", "origin/main..HEAD").splitlines()

    def test_parent_reviewed_then_merged_and_deleted_with_the_child_pr_retargeted(self) -> None:
        self.start_child()
        self.pr_base = PARENT  # the child's PR opens on the parent
        self.commit(self.github, "p.txt", "parent, after review")
        git(self.github, "push", "-q", "origin", PARENT)
        self.assertEqual(publish.main(), 0)
        self.assertEqual(self.remote(f"{CHILD}~1"), self.remote(PARENT))

        self.merge_and_delete_parent()
        self.pr_base = "main"  # GitHub retargeted the child's PR
        self.assertEqual(publish.main(), 0)
        self.assertEqual(self.own_commits(), ["child"])
        self.assertEqual(git(self.work, "rev-parse", "HEAD~1"), self.remote("main"))
        self.assertEqual(self.remote(CHILD), git(self.work, "rev-parse", "HEAD"))
        self.assertEqual(git(self.work, "branch", "-r", "--list", f"origin/{PARENT}"), "")  # pruned

    def test_parent_merged_and_deleted_before_the_child_pr_exists(self) -> None:
        self.start_child()
        self.merge_and_delete_parent()
        self.assertEqual(publish.main(), 0)  # the recorded parent is gone but merged: main
        self.assertEqual(self.own_commits(), ["child"])
        self.assertEqual(self.remote(CHILD), git(self.work, "rev-parse", "HEAD"))
        self.assertEqual(publish.recorded_base(CHILD), None)  # forgotten: the PR opens on main

    def test_parent_deleted_unmerged_stops_publish(self) -> None:
        self.start_child()
        git(self.github, "push", "-q", "origin", "--delete", PARENT)  # closed without a merge
        head = git(self.work, "rev-parse", "HEAD")
        pushed = self.remote(CHILD)
        with self.assertRaises(Failure) as caught:
            publish.main()
        self.assertIn("was not merged", str(caught.exception))
        self.assertEqual(git(self.work, "rev-parse", "HEAD"), head)
        self.assertEqual(self.remote(CHILD), pushed)
        self.assertEqual(publish.recorded_base(CHILD), PARENT)

    def test_an_explicit_base_wins_over_the_record(self) -> None:
        self.start_child()
        self.assertEqual(publish.main(base="main"), 0)
        self.assertEqual(self.own_commits(), ["child", "parent"])  # the parent's commit rides along, as asked
        self.assertEqual(publish.recorded_base(CHILD), PARENT)


if __name__ == "__main__":
    unittest.main()
