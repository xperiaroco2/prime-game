"""publish: which branch it rebases on, and what it refuses before touching git history."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import publish
from runner.common import ROOT, Failure, Result, force_rmtree


def _result(rc: int, out: str) -> Result:
    return Result(rc, out, False, 0.0)


class PrBaseTest(unittest.TestCase):
    def base_for(self, res: Result) -> str | None:
        with mock.patch.object(publish.shutil, "which", return_value="gh"):
            with mock.patch.object(publish, "run", return_value=res):
                return publish.pr_base("tooling/6-skills")

    def test_open_pr_gives_its_base(self) -> None:
        # A stacked PR: rebase on the parent branch, not on main.
        stacked = _result(0, '{"baseRefName": "tooling/4-hooks", "state": "OPEN"}')
        self.assertEqual(self.base_for(stacked), "tooling/4-hooks")

    def test_merged_or_missing_pr_gives_none(self) -> None:
        self.assertIsNone(self.base_for(_result(0, '{"baseRefName": "main", "state": "MERGED"}')))
        self.assertIsNone(self.base_for(_result(1, "no pull requests found for branch")))
        self.assertIsNone(self.base_for(_result(0, "not json")))


class RefusalTest(unittest.TestCase):
    def setUp(self) -> None:
        quiet = mock.patch.object(publish, "say")
        quiet.start()
        self.addCleanup(quiet.stop)

    def test_only_task_branches(self) -> None:
        for branch in ("main", "feature-x", "tooling/hooks", ""):
            with self.subTest(branch=branch), mock.patch.object(publish, "_git", return_value=_result(0, branch)):
                with self.assertRaises(Failure) as caught:
                    publish.main()
                self.assertIn("is not a task branch", str(caught.exception))

    def test_uncommitted_changes_stop_it(self) -> None:
        answers = iter([_result(0, "tooling/4-hooks"), _result(0, " M tools/run.py")])
        with mock.patch.object(publish, "_git", side_effect=lambda *a, **k: next(answers)):
            with self.assertRaises(Failure) as caught:
                publish.main()
        self.assertIn("uncommitted changes", str(caught.exception))

    def test_task_branch_pattern(self) -> None:
        for branch in ("tooling/4-hooks", "core/42-vote-tally", "docs/7-wrapup", "tooling/5-land-on-main"):
            self.assertRegex(branch, publish.TASK_BRANCH_RE)
        for branch in ("main", "tooling/hooks", "Tooling/4-x", "tooling/4-", "a/b/4-x"):
            self.assertNotRegex(branch, publish.TASK_BRANCH_RE)


class RealGitTest(unittest.TestCase):
    """publish against a local bare remote, with the committed pre-push hook; verify and gh are stubbed."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="publish-"))
        self.addCleanup(force_rmtree, str(self.tmp))
        hooks = self.tmp / "hooks"
        hooks.mkdir()
        shutil.copy(ROOT / ".claude" / "githooks" / "pre-push", hooks / "pre-push")
        (hooks / "pre-push").chmod(0o755)
        self.git(self.tmp, "init", "-q", "--bare", "-b", "main", "remote.git")
        self.work, self.other = self.clone("work"), None
        self.write(self.work, "f.txt", "one\n")
        self.git(self.work, "add", "f.txt")
        self.git(self.work, "commit", "-q", "-m", "c1")
        self.git(self.work, "push", "-q", "origin", "main")
        self.git(self.work, "config", "core.hooksPath", str(hooks))
        self.other = self.clone("other")  # the other machine, or GitHub's web editor
        for patch in (
            mock.patch.object(publish, "REPO", self.work),
            mock.patch.object(publish, "say"),
            mock.patch.object(publish, "ok"),
            mock.patch.object(publish, "bad"),
            mock.patch.object(publish, "pr_base", return_value=None),
            mock.patch.object(publish.verify, "main", return_value=0),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def clone(self, name: str) -> Path:
        self.git(self.tmp, "clone", "-q", str(self.tmp / "remote.git"), name)
        where = self.tmp / name
        for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
            self.git(where, "config", key, value)
        return where

    @staticmethod
    def git(where: Path, *args: str) -> str:
        res = subprocess.run(
            ["git", *args], cwd=where, capture_output=True, text=True, encoding="utf-8", timeout=120,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        )  # fmt: skip
        if res.returncode != 0:
            raise AssertionError(f"git {' '.join(args)} failed: {res.stderr}")
        return res.stdout.strip()

    @staticmethod
    def write(where: Path, name: str, text: str) -> None:
        (where / name).write_text(text, encoding="utf-8", newline="\n")

    def commit(self, where: Path, name: str, text: str, message: str) -> None:
        self.write(where, name, text)
        self.git(where, "add", name)
        self.git(where, "commit", "-q", "-m", message)

    def remote(self, ref: str) -> str:
        return self.git(self.tmp / "remote.git", "rev-parse", ref)

    def test_rebases_on_moved_main_and_pushes_with_the_lease(self) -> None:
        self.git(self.work, "switch", "-q", "-c", "tooling/1-x")
        self.commit(self.work, "g.txt", "mine\n", "mine")
        self.assertEqual(publish.main(), 0)  # a new branch
        self.commit(self.other, "h.txt", "theirs\n", "main moves")
        self.git(self.other, "push", "-q", "origin", "main")
        self.assertEqual(publish.main(), 0)  # rebased: a non-fast-forward push, allowed by the hook
        head = self.git(self.work, "rev-parse", "HEAD")
        self.assertEqual(self.remote("tooling/1-x"), head)
        self.assertEqual(self.git(self.work, "rev-parse", "HEAD~1"), self.remote("main"))
        # An amend rewrites the pushed tip, which the reflog still knows: not a lost remote commit.
        self.git(self.work, "commit", "-q", "--amend", "-m", "mine, amended")
        self.assertEqual(publish.main(), 0)
        self.assertEqual(self.remote("tooling/1-x"), self.git(self.work, "rev-parse", "HEAD"))

    def test_refuses_when_the_remote_branch_has_commits_it_never_had(self) -> None:
        self.git(self.work, "switch", "-q", "-c", "tooling/1-x")
        self.commit(self.work, "g.txt", "mine\n", "mine")
        self.assertEqual(publish.main(), 0)
        self.git(self.other, "fetch", "-q")
        self.git(self.other, "switch", "-q", "tooling/1-x")
        self.commit(self.other, "g.txt", "mine\nsuggested\n", "a suggestion committed on GitHub")
        self.git(self.other, "push", "-q", "origin", "tooling/1-x")
        suggestion = self.remote("tooling/1-x")
        head = self.git(self.work, "rev-parse", "HEAD")
        with self.assertRaises(Failure) as caught:
            publish.main()
        self.assertIn("has commits this branch never had", str(caught.exception))
        self.assertEqual(self.remote("tooling/1-x"), suggestion)
        self.assertEqual(self.git(self.work, "rev-parse", "HEAD"), head)

    def test_a_conflict_aborts_and_leaves_the_branch_alone(self) -> None:
        self.git(self.work, "switch", "-q", "-c", "tooling/1-x")
        self.commit(self.work, "f.txt", "mine\n", "mine")
        self.commit(self.other, "f.txt", "theirs\n", "main changes the same line")
        self.git(self.other, "push", "-q", "origin", "main")
        head = self.git(self.work, "rev-parse", "HEAD")
        with self.assertRaises(Failure) as caught:
            publish.main()
        self.assertIn("rebase on origin/main stopped", str(caught.exception))
        self.assertEqual(self.git(self.work, "rev-parse", "HEAD"), head)
        self.assertEqual(self.git(self.work, "status", "--porcelain"), "")
        self.assertFalse((self.work / ".git" / "rebase-merge").exists())

    def test_stacked_child_replays_only_its_own_commits(self) -> None:
        self.git(self.work, "switch", "-q", "-c", "tooling/1-parent")
        self.commit(self.work, "p.txt", "parent\n", "parent")
        self.assertEqual(publish.main(), 0)
        self.git(self.work, "switch", "-q", "-c", "tooling/2-child")
        self.commit(self.work, "c.txt", "child\n", "child")
        self.assertEqual(publish.main(base="tooling/1-parent"), 0)
        # The parent's commit changes after review. A plain rebase of the child would replay the old parent commit
        # onto the new one and stop on a conflict in p.txt; --fork-point replays only the child's commit.
        self.git(self.work, "switch", "-q", "tooling/1-parent")
        self.write(self.work, "p.txt", "parent, after review\n")
        self.git(self.work, "commit", "-q", "--amend", "-a", "-m", "parent, reviewed")
        self.assertEqual(publish.main(), 0)
        self.git(self.work, "switch", "-q", "tooling/2-child")
        self.assertEqual(publish.main(base="tooling/1-parent"), 0)
        own = self.git(self.work, "rev-list", "--count", "origin/tooling/1-parent..HEAD")
        self.assertEqual(own, "1")
        self.assertEqual(self.remote("tooling/2-child"), self.git(self.work, "rev-parse", "HEAD"))


if __name__ == "__main__":
    unittest.main()
