"""A task stacked on an open PR, end to end: `start --base` on the parent's branch, `publish` onto the parent, then
the parent merged and its branch deleted (GitHub's auto-delete), and `publish` onto main; and a task on a stage's
long-lived release branch. Real temp repos with the committed pre-push hook; gh, the board, sessions and verify are
stubbed."""

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
RELEASE = "release/m3"


class Repos(unittest.TestCase):
    """The remote, the task's checkout and GitHub's side (the parent's session, the merge button, the manager)."""

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

    def own_commits(self) -> list[str]:
        return git(self.work, "log", "--format=%s", "origin/main..HEAD").splitlines()


class StackedTest(Repos):
    def start_child(self) -> None:
        self.assertEqual(start.main(33, base=PARENT, here=True), 0)  # the stack is published from this checkout
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
        self.assertIn("cannot confirm that the parent", str(caught.exception))
        self.assertEqual(git(self.work, "rev-parse", "HEAD"), head)
        self.assertEqual(self.remote(CHILD), pushed)
        self.assertEqual(publish.recorded_base(CHILD), PARENT)

    def amend_parent(self) -> None:
        """The parent's session rewrites the parent after review and pushes it with a lease."""
        git(self.github, "switch", "-q", PARENT)
        (self.github / "p.txt").write_text("parent, rewritten after review\n", encoding="utf-8", newline="\n")
        git(self.github, "commit", "-q", "--amend", "-a", "-m", "parent, reviewed")
        git(self.github, "push", "-q", "--force-with-lease", "origin", PARENT)

    def test_parent_amended_before_the_child_pr_exists(self) -> None:
        self.start_child()
        self.amend_parent()
        self.assertEqual(publish.main(), 0)  # a plain rebase would replay the old parent commit and conflict
        self.assertEqual(git(self.work, "log", "--format=%s", f"origin/{PARENT}..HEAD").splitlines(), ["child"])
        self.assertEqual(self.remote(f"{CHILD}~1"), self.remote(PARENT))

    def test_parent_amended_merged_and_deleted_unseen_needs_the_human_then_base_main(self) -> None:
        self.start_child()
        self.amend_parent()  # this checkout never fetches the rewritten parent
        self.merge_and_delete_parent()
        with self.assertRaises(Failure) as caught:
            publish.main()
        self.assertIn("run publish --base main", str(caught.exception))
        self.assertEqual(publish.main(base="main"), 0)  # the human checked: the parent's PR was merged
        self.assertEqual(self.own_commits(), ["child"])
        self.assertEqual((self.work / "p.txt").read_text(encoding="utf-8"), "parent, rewritten after review\n")
        self.assertIsNone(publish.recorded_base(CHILD))

    def test_parent_ref_pruned_by_another_session_before_this_publish(self) -> None:
        self.start_child()
        self.merge_and_delete_parent()
        git(self.work, "update-ref", "-d", f"refs/remotes/origin/{PARENT}")  # a publish in a sibling worktree
        self.pr_base = "main"
        self.assertEqual(publish.main(), 0)  # the recorded tip proves the merge
        self.assertEqual(self.own_commits(), ["child"])

    def test_parent_merged_but_its_branch_kept(self) -> None:
        self.start_child()
        git(self.github, "fetch", "-q")
        git(self.github, "switch", "-q", "main")
        git(self.github, "merge", "-q", "--no-ff", "-m", "Merge the parent", f"origin/{PARENT}")
        git(self.github, "push", "-q", "origin", "main")
        self.assertEqual(publish.main(), 0)
        self.assertEqual(self.own_commits(), ["child"])
        self.assertIsNone(publish.recorded_base(CHILD))  # the PR opens on main, not on the dead parent

    def test_base_main_by_hand_replays_only_the_own_commits(self) -> None:
        self.start_child()
        self.assertEqual(publish.main(base="main"), 0)  # the human's word that the parent is done
        self.assertEqual(self.own_commits(), ["child"])
        self.assertIsNone(publish.recorded_base(CHILD))
        warned = " ".join(str(c.args[0]) for c in publish.warn.call_args_list)  # type: ignore[attr-defined]
        self.assertIn("leaves out these commits of the parent", warned)  # the parent was not merged
        self.assertIn("parent", warned.rsplit("\n", 1)[-1])  # the dropped commit's subject

    def test_without_a_recorded_tip_the_parent_ref_marks_the_own_commits(self) -> None:
        self.start_child()
        git(self.work, "config", "--unset", publish.tip_key(CHILD))  # a record from before the tip existed
        self.merge_and_delete_parent()
        self.pr_base = "main"
        self.assertEqual(publish.main(), 0)
        self.assertEqual(self.own_commits(), ["child"])


class LongLivedBaseTest(Repos):
    """A task of a stage stacked on its release branch (docs/decisions/2026-10-01-release-branch-per-milestone.md),
    which the manager creates from main, fast-forwards and merges other task PRs into while this task runs (#113)."""

    def make_release(self, name: str = RELEASE) -> None:
        """The manager creates the stage's release branch from main: its tip is main's."""
        git(self.github, "fetch", "-q")
        git(self.github, "push", "-q", "origin", f"refs/remotes/origin/main:refs/heads/{name}")

    def land_on_release(self, name: str, message: str) -> None:
        """The manager merges another task's PR into the release branch: --no-ff, pushed by hash."""
        git(self.github, "fetch", "-q")
        git(self.github, "switch", "-q", "--detach", f"origin/{RELEASE}")
        self.commit(self.github, name, message)
        task = git(self.github, "rev-parse", "HEAD")
        git(self.github, "switch", "-q", "--detach", f"origin/{RELEASE}")
        git(self.github, "merge", "-q", "--no-ff", "-m", f"Merge {message}", task)
        git(self.github, "push", "-q", "origin", f"HEAD:refs/heads/{RELEASE}")

    def main_moves_on(self) -> None:
        git(self.github, "fetch", "-q")
        git(self.github, "switch", "-q", "--detach", "origin/main")
        self.commit(self.github, "m.txt", "main moves on")
        git(self.github, "push", "-q", "origin", "HEAD:refs/heads/main")

    def start_on(self, base: str) -> None:
        self.assertEqual(start.main(33, base=base, here=True), 0)
        self.commit(self.work, "c.txt", "child")

    def assert_kept_on(self, base: str) -> None:
        self.assertEqual(publish.recorded_base(CHILD), base)
        self.assertEqual(git(self.work, "log", "--format=%s", f"origin/{base}..HEAD").splitlines(), ["child"])
        self.assertEqual(git(self.work, "rev-parse", "HEAD~1"), self.remote(base))
        self.assertEqual(self.remote(CHILD), git(self.work, "rev-parse", "HEAD"))

    def keeps_a_base_equal_to_main(self, base: str) -> None:
        self.make_release(base)
        self.start_on(base)
        self.assertEqual(publish.main(), 0)  # no PR yet: its tip is in main, and still it is the base
        self.assert_kept_on(base)
        self.main_moves_on()  # main gets ahead of it (a hotfix): its tip is still in main
        self.assertEqual(publish.main(), 0)
        self.assert_kept_on(base)
        self.assertNotEqual(git(self.work, "rev-parse", "HEAD~1"), self.remote("main"))
        self.pr_base = base  # the PR opens on it
        self.assertEqual(publish.main(), 0)
        self.assert_kept_on(base)
        warned = " ".join(str(c.args[0]) for c in publish.warn.call_args_list)  # type: ignore[attr-defined]
        self.assertNotIn("is merged", warned)

    def test_a_release_base_equal_to_main_is_not_a_merged_parent(self) -> None:
        self.keeps_a_base_equal_to_main(RELEASE)

    def test_any_base_outside_the_task_branch_pattern_is_not_a_merged_parent(self) -> None:
        self.keeps_a_base_equal_to_main("integration")

    def test_the_release_merged_into_main_and_deleted_moves_the_task_to_main(self) -> None:
        self.make_release()
        self.start_on(RELEASE)
        self.pr_base = RELEASE
        self.assertEqual(publish.main(), 0)
        self.land_on_release("x.txt", "task A")
        # The milestone PR merges into main; auto-delete removes the release branch and GitHub retargets this PR.
        git(self.github, "fetch", "-q")
        git(self.github, "switch", "-q", "main")
        git(self.github, "merge", "-q", "--ff-only", "origin/main")
        git(self.github, "merge", "-q", "--no-ff", "-m", "Merge the milestone", f"origin/{RELEASE}")
        git(self.github, "push", "-q", "origin", "main")
        git(self.github, "push", "-q", "origin", "--delete", RELEASE)
        self.pr_base = "main"
        self.assertEqual(publish.main(), 0)
        self.assertEqual(self.own_commits(), ["child"])
        self.assertIsNone(publish.recorded_base(CHILD))


if __name__ == "__main__":
    unittest.main()
