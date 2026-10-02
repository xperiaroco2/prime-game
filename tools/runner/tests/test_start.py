"""`start` and `worktree-done` against a real temp repo with a bare remote; gh, the board and sessions are stubbed."""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from runner import common, sessions, start
from runner.common import Failure, Result
from runner.tests.test_githooks import _rmtree


def git(where: Path, *args: str) -> str:
    res = subprocess.run(
        ["git", *args], cwd=where, capture_output=True, text=True, encoding="utf-8", timeout=120,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )  # fmt: skip
    if res.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {res.stderr}")
    return res.stdout.strip()


class SlugAndAreaTest(unittest.TestCase):
    def test_slug(self) -> None:
        self.assertEqual(start.slug("M0: Vote tally (host)"), "m0-vote-tally-host")
        self.assertEqual(start.slug("Голосування"), "task")
        long = start.slug("a very long title that keeps going well past the forty character limit")
        self.assertLessEqual(len(long), start.SLUG_MAX)
        self.assertFalse(long.endswith("-"))

    def test_area(self) -> None:
        self.assertEqual(start.area_of(["bug", "area:level"], None, 5), "level")
        self.assertEqual(start.area_of(["area:core", "area:net"], "net", 5), "net")
        for labels, text in ((["bug"], "no area label"), (["area:core", "area:net"], "several area labels")):
            with self.subTest(labels=labels), self.assertRaises(Failure) as caught:
                start.area_of(labels, None, 5)
            self.assertIn(text, str(caught.exception))
        with self.assertRaises(Failure):
            start.area_of([], "docs", 5)


class StartTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="start-"))
        self.addCleanup(_rmtree, str(self.tmp))
        git(self.tmp, "init", "-q", "--bare", "-b", "main", "remote.git")
        git(self.tmp, "clone", "-q", str(self.tmp / "remote.git"), "work")
        self.work = self.tmp / "work"
        for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
            git(self.work, "config", key, value)
        self.write("f.txt", "one\n")
        self.write(".gitignore", ".claude/worktrees/\n")
        git(self.work, "add", ".")
        git(self.work, "commit", "-q", "-m", "c1")
        git(self.work, "push", "-q", "origin", "main")
        self.issue = {
            "number": 42,
            "title": "Vote tally",
            "state": "OPEN",
            "labels": [{"name": "area:core"}],
            "assignees": [],
            "url": "https://github.com/o/r/issues/42",
        }
        self.login = "xperiaroco2"
        self.others: list[sessions.Session] = []  # sessions on the main checkout
        self.inside: list[sessions.Session] = []  # sessions whose cwd is a worktree
        self.gh_calls: list[tuple[str, ...]] = []
        self.moves = mock.MagicMock()
        self.appdata = self.tmp / "appdata"  # a fake %APPDATA%: worktree-done deletes a worktree's user:// there
        for patch in (
            mock.patch.object(start, "app_data_dir", return_value=self.appdata),
            mock.patch.object(common, "app_data_dir", return_value=self.appdata),  # common.worktree_user_dir
            mock.patch.object(start, "REPO", self.work),
            mock.patch.object(start, "_gh", side_effect=self.fake_gh),
            mock.patch.object(start.board, "move", self.moves),
            mock.patch.object(
                start.sessions, "active_on", side_effect=lambda repo: self.others if repo == self.work else self.inside
            ),
            mock.patch.object(start.sessions, "alive_in", side_effect=lambda path: self.inside),
            mock.patch.object(start, "say"),
            mock.patch.object(start, "ok"),
            mock.patch.object(start, "warn"),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def fake_gh(self, *args: str) -> str:
        self.gh_calls.append(args)
        if args[:2] == ("issue", "view"):
            return json.dumps(self.issue)
        if args[:2] == ("api", "user"):
            return self.login
        return ""

    def write(self, name: str, text: str) -> None:
        (self.work / name).write_text(text, encoding="utf-8", newline="\n")

    def branch(self, where: Path | None = None) -> str:
        return git(where or self.work, "symbolic-ref", "--short", "HEAD")

    def other_session(self) -> None:
        self.others = [sessions.Session(1, "other", str(self.work), "busy", time.time(), "task 41")]

    def test_creates_the_branch_from_origin_main_assigns_and_moves(self) -> None:
        self.assertEqual(start.main(42, here=True), 0)
        self.assertEqual(self.branch(), "core/42-vote-tally")
        self.assertEqual(git(self.work, "rev-parse", "HEAD"), git(self.work, "rev-parse", "origin/main"))
        # No upstream yet: the first publish sets origin/core/42-vote-tally, never origin/main.
        self.assertEqual(subprocess.run(["git", "config", "branch.core/42-vote-tally.merge"], cwd=self.work).returncode, 1)
        self.assertIn(("issue", "edit", "42", "--add-assignee", "@me"), self.gh_calls)
        self.moves.assert_called_once_with(42, "in-progress")

    def test_dirty_tree_stops_it_and_changes_nothing(self) -> None:
        self.write("f.txt", "edited\n")
        self.write("new.txt", "untracked\n")
        with self.assertRaises(Failure) as caught:
            start.main(42, here=True)
        self.assertIn("--include", str(caught.exception))
        self.assertIn("--stash", str(caught.exception))
        self.assertEqual(self.branch(), "main")
        self.assertEqual((self.work / "f.txt").read_text(encoding="utf-8"), "edited\n")
        self.assertTrue((self.work / "new.txt").is_file())
        self.moves.assert_not_called()

    def test_stash_keeps_the_changes_in_the_stash(self) -> None:
        self.write("f.txt", "edited\n")
        self.write("new.txt", "untracked\n")
        self.assertEqual(start.main(42, stash=True), 0)
        self.assertEqual(self.branch(), "core/42-vote-tally")
        self.assertEqual(git(self.work, "status", "--porcelain"), "")
        self.assertIn("start #42: left on main", git(self.work, "stash", "list"))

    def test_include_carries_the_changes(self) -> None:
        self.write("f.txt", "edited\n")
        self.assertEqual(start.main(42, include=True), 0)
        self.assertEqual(self.branch(), "core/42-vote-tally")
        self.assertEqual((self.work / "f.txt").read_text(encoding="utf-8"), "edited\n")

    def test_resumes_an_existing_remote_branch_whatever_its_slug(self) -> None:
        git(self.work, "switch", "-q", "-c", "core/42-first-name")
        self.write("g.txt", "work\n")
        git(self.work, "add", "g.txt")
        git(self.work, "commit", "-q", "-m", "work")
        git(self.work, "push", "-q", "-u", "origin", "core/42-first-name")
        git(self.work, "switch", "-q", "main")
        git(self.work, "branch", "-q", "-D", "core/42-first-name")
        self.issue["title"] = "Renamed later"
        self.assertEqual(start.main(42, here=True), 0)
        self.assertEqual(self.branch(), "core/42-first-name")
        self.assertTrue((self.work / "g.txt").is_file())

    def test_refuses_closed_issues_and_assigns_nobody_else(self) -> None:
        self.issue["assignees"] = [{"login": "designer"}]
        self.assertEqual(start.main(42), 0)
        self.assertFalse(any(c[:2] == ("issue", "edit") for c in self.gh_calls))
        self.issue["state"] = "CLOSED"
        with self.assertRaises(Failure):
            start.main(42)

    def test_dry_run_changes_nothing(self) -> None:
        self.write("f.txt", "edited\n")
        self.assertEqual(start.main(42, stash=True, dry_run=True), 0)
        self.assertEqual(self.branch(), "main")
        self.assertEqual(git(self.work, "stash", "list"), "")
        self.moves.assert_not_called()
        self.assertFalse(any(c[:2] == ("issue", "edit") for c in self.gh_calls))

    def test_worktree_when_another_session_is_active_and_done_after_merge(self) -> None:
        self.other_session()
        self.write("f.txt", "the other session's edit\n")  # the main checkout is left alone
        self.assertEqual(start.main(42), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.assertEqual(self.branch(), "main")
        self.assertEqual((self.work / "f.txt").read_text(encoding="utf-8"), "the other session's edit\n")
        self.assertEqual(self.branch(tree), "core/42-vote-tally")
        self.assertEqual(subprocess.run(["git", "config", "branch.core/42-vote-tally.merge"], cwd=self.work).returncode, 1)
        self.assertEqual(start.main(42), 0)  # running it again reuses the worktree

        (tree / "g.txt").write_text("work\n", encoding="utf-8", newline="\n")
        git(tree, "add", "g.txt")
        git(tree, "commit", "-q", "-m", "work")
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42)
        self.assertIn("not merged", str(caught.exception))
        self.assertTrue(tree.is_dir())

        git(tree, "push", "-q", "origin", "core/42-vote-tally:main")  # a human merged the PR
        self.assertEqual(start.worktree_done(42), 0)
        self.assertFalse(tree.exists())
        self.assertEqual(git(self.work, "branch", "--list", "core/42-vote-tally"), "")

    def test_worktree_done_refuses_uncommitted_work(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        (tree / "f.txt").write_text("unsaved\n", encoding="utf-8", newline="\n")
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42)
        self.assertIn("uncommitted", str(caught.exception))
        self.assertTrue(tree.is_dir())

    def test_worktree_done_refuses_unmerged_detached_commits_and_live_sessions(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        git(tree, "switch", "-q", "--detach")
        (tree / "fix.txt").write_text("fix\n", encoding="utf-8", newline="\n")
        git(tree, "add", "fix.txt")
        git(tree, "commit", "-q", "-m", "a fix on a detached HEAD")
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42)
        self.assertIn("detached HEAD", str(caught.exception))
        self.assertTrue(tree.is_dir())
        git(tree, "switch", "-q", "core/42-vote-tally")
        self.inside = [sessions.Session(2, "wt", str(tree), "busy", time.time(), "in the worktree")]
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42)
        self.assertIn("still open in the worktree", str(caught.exception))
        self.assertTrue(tree.is_dir())

    def commit_in(self, tree: Path, name: str) -> None:
        (tree / name).write_text(f"{name}\n", encoding="utf-8", newline="\n")
        git(tree, "add", name)
        git(tree, "commit", "-q", "-m", name)

    def test_worktree_done_pushed_removes_a_spike_worktree_once_origin_has_it(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.commit_in(tree, "spike.txt")
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42)
        self.assertIn("--pushed", str(caught.exception))
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42, pushed=True)
        self.assertIn("has no branch", str(caught.exception))
        # A stale tracking ref (the branch was deleted on origin) does not count as pushed.
        git(self.work, "update-ref", "refs/remotes/origin/core/42-vote-tally", git(tree, "rev-parse", "HEAD"))
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42, pushed=True)
        self.assertIn("has no branch", str(caught.exception))
        self.assertTrue(tree.is_dir())
        git(tree, "push", "-q", "origin", "core/42-vote-tally")
        self.commit_in(tree, "later.txt")  # a commit origin does not have yet
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42, pushed=True)
        self.assertIn("has commits", str(caught.exception))
        git(tree, "push", "-q", "origin", "core/42-vote-tally")
        (tree / "stray.txt").write_text("untracked\n", encoding="utf-8", newline="\n")
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42, pushed=True)
        self.assertIn("uncommitted", str(caught.exception))
        (tree / "stray.txt").unlink()
        # An ignored folder (like .godot/) does not block the removal.
        exclude = Path(git(self.work, "rev-parse", "--path-format=absolute", "--git-common-dir")) / "info" / "exclude"
        exclude.parent.mkdir(exist_ok=True)
        exclude.write_text("cache/\n", encoding="utf-8")
        (tree / "cache").mkdir()
        (tree / "cache" / "import.bin").write_text("ignored\n", encoding="utf-8")

        self.assertEqual(start.worktree_done(42, pushed=True), 0)
        self.assertFalse(tree.exists())
        self.assertEqual(git(self.work, "branch", "--list", "core/42-vote-tally"), "core/42-vote-tally")  # kept
        self.assertIn("refs/heads/core/42-vote-tally", git(self.work, "ls-remote", "--heads", "origin"))

    def test_worktree_done_pushed_refuses_a_detached_head(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        git(tree, "switch", "-q", "--detach")
        self.commit_in(tree, "fix.txt")
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42, pushed=True)
        self.assertIn("detached HEAD", str(caught.exception))
        self.assertTrue(tree.is_dir())

    def test_worktree_done_pushed_still_deletes_a_merged_branch(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.commit_in(tree, "g.txt")
        git(tree, "push", "-q", "origin", "core/42-vote-tally:main")
        self.assertEqual(start.worktree_done(42, pushed=True), 0)
        self.assertFalse(tree.exists())
        self.assertEqual(git(self.work, "branch", "--list", "core/42-vote-tally"), "")

    def test_worktree_done_refuses_up_front_from_inside_the_worktree(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        git(tree, "push", "-q", "origin", "core/42-vote-tally")
        (tree / "sub").mkdir()
        self.addCleanup(os.chdir, os.getcwd())
        for where in (tree, tree / "sub"):
            os.chdir(where)
            with self.subTest(cwd=where), self.assertRaises(Failure) as caught:
                start.worktree_done(42, pushed=True)
            self.assertIn("run worktree-done from the main checkout: cd", str(caught.exception))
        os.chdir(self.work)
        with mock.patch.object(start, "REPO", tree), self.assertRaises(Failure) as caught:
            start.worktree_done(42, pushed=True)  # the worktree's own tools\run.cmd
        self.assertIn("the worktree's own runner", str(caught.exception))
        self.inside = [sessions.Session(2, "me", str(tree), "busy", time.time(), "this session")]
        with mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": "me"}), self.assertRaises(Failure) as caught:
            start.worktree_done(42, pushed=True)  # the calling session itself sits in the worktree
        self.assertIn("this Claude session's own folder is the worktree", str(caught.exception))
        self.assertIn(str(tree.resolve()).lower(), start.listed_worktrees())  # still registered, nothing touched

    def test_worktree_done_finishes_a_removal_windows_left_half_done(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.commit_in(tree, "g.txt")
        git(tree, "push", "-q", "origin", "core/42-vote-tally:main")  # merged
        git(self.work, "worktree", "remove", str(tree))  # git unregistered it...
        (tree / "addons" / "empty").mkdir(parents=True)  # ...but the folder stayed, emptied
        self.assertEqual(start.worktree_done(42), 0)
        self.assertFalse(tree.exists())
        self.assertEqual(git(self.work, "branch", "--list", "core/42-vote-tally"), "")
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42)
        self.assertIn("nothing left over", str(caught.exception))

    def user_dirs(self, tree: Path) -> tuple[Path, Path, Path]:
        """The worktree's own user:// folder, the main checkout's default one and another worktree's, each with a file."""
        own = start.own_user_dir(tree)
        assert own is not None
        folders = (own, own.parent / "PrimeGame", own.parent / "PrimeGame-43-0a1b2c")
        for folder in folders:
            (folder / "tmp").mkdir(parents=True)
            (folder / "tmp" / "f.txt").write_text("x\n", encoding="utf-8")
        return folders

    def test_worktree_done_deletes_the_worktrees_own_user_dir_and_nothing_else(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.commit_in(tree, "g.txt")
        git(tree, "push", "-q", "origin", "core/42-vote-tally:main")  # merged
        own, default, other = self.user_dirs(tree)
        # The folder Godot uses: the custom_user_dir_name the runner writes into the worktree's override.cfg (#182).
        self.assertIn(f'config/custom_user_dir_name="{own.relative_to(self.appdata).as_posix()}"', common.override_text(tree))
        with mock.patch.object(start, "ok") as said:
            self.assertEqual(start.worktree_done(42), 0)
        self.assertFalse(tree.exists())
        self.assertFalse(own.exists())
        self.assertTrue((default / "tmp" / "f.txt").is_file())  # the main checkout's user:// survives
        self.assertTrue((other / "tmp" / "f.txt").is_file())  # and so does another worktree's
        lines = [c.args[0] for c in said.call_args_list if "user://" in c.args[0]]
        self.assertEqual(lines, [f"removed the worktree's user:// folder {own}"])

    def test_worktree_done_without_a_user_dir_is_fine(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.commit_in(tree, "g.txt")
        git(tree, "push", "-q", "origin", "core/42-vote-tally:main")  # merged
        with mock.patch.object(start, "ok") as said:
            self.assertEqual(start.worktree_done(42), 0)
        self.assertFalse(tree.exists())
        self.assertFalse(self.appdata.exists())
        self.assertFalse([c for c in said.call_args_list if "user://" in c.args[0]])
        with mock.patch.object(start, "app_data_dir", return_value=None):  # an OS the runner does not know
            self.assertIsNone(start.own_user_dir(tree))

    def test_worktree_done_leftovers_include_the_user_dir(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.commit_in(tree, "g.txt")
        git(tree, "push", "-q", "origin", "core/42-vote-tally:main")  # merged
        own, default, other = self.user_dirs(tree)
        git(self.work, "worktree", "remove", str(tree))  # removed by hand: the user:// folder stayed
        git(self.work, "branch", "-D", "core/42-vote-tally")
        self.assertEqual(start.worktree_done(42), 0)  # the user:// folder was the only leftover
        self.assertFalse(own.exists())
        self.assertTrue(default.is_dir())
        self.assertTrue(other.is_dir())
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42)
        self.assertIn("nothing left over", str(caught.exception))

    def test_worktree_done_leftovers_name_the_user_dir_after_the_live_project(self) -> None:
        # A renamed project: once the worktree (and its project.godot) is gone, the folder's name still follows
        # application/config/name, read from the main checkout, not a hardcoded "PrimeGame".
        self.write("project.godot", '[application]\n\nconfig/name="Renamed"\n')
        git(self.work, "add", "project.godot")
        git(self.work, "commit", "-q", "-m", "rename")
        git(self.work, "push", "-q", "origin", "main")
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.commit_in(tree, "g.txt")
        git(tree, "push", "-q", "origin", "core/42-vote-tally:main")  # merged
        own = start.own_user_dir(tree)
        assert own is not None
        self.assertTrue(own.name.startswith("Renamed-42-"), own.name)
        (own / "tmp").mkdir(parents=True)
        git(self.work, "worktree", "remove", str(tree))  # removed by hand: the user:// folder stayed
        git(self.work, "branch", "-D", "core/42-vote-tally")
        self.assertEqual(start.worktree_done(42), 0)
        self.assertFalse(own.exists())

    def test_worktree_done_leftovers_keep_files_and_unmerged_branches(self) -> None:
        git(self.work, "branch", "core/43-merged")  # at origin/main: merged
        self.assertEqual(start.worktree_done(43), 0)  # only the merged branch was left
        self.assertEqual(git(self.work, "branch", "--list", "core/43-merged"), "")

        git(self.work, "switch", "-q", "-c", "core/44-unmerged")
        self.write("u.txt", "unmerged\n")
        git(self.work, "add", "u.txt")
        git(self.work, "commit", "-q", "-m", "unmerged")
        git(self.work, "switch", "-q", "main")
        with self.assertRaises(Failure) as caught:
            start.worktree_done(44)
        self.assertIn("kept", str(caught.exception))
        self.assertEqual(git(self.work, "branch", "--list", "core/44-unmerged"), "core/44-unmerged")

        stray = self.work / ".claude" / "worktrees" / "45" / "notes.txt"
        stray.parent.mkdir(parents=True)
        stray.write_text("someone's notes\n", encoding="utf-8")
        with self.assertRaises(Failure) as caught:
            start.worktree_done(45)
        self.assertIn("still holds files", str(caught.exception))
        self.assertTrue(stray.is_file())

    def test_worktree_done_refuses_any_live_session_left_in_an_empty_folder(self) -> None:
        tree = self.work / ".claude" / "worktrees" / "46"
        tree.mkdir(parents=True)
        self.inside = [sessions.Session(3, "old", str(tree), "idle", time.time() - 7 * 3600, "task 46, idle for hours")]
        with self.assertRaises(Failure) as caught:
            start.worktree_done(46)
        self.assertIn("Archive or close that session", str(caught.exception))
        self.assertTrue(tree.is_dir())
        self.inside = []
        with mock.patch.object(start.shutil, "rmtree", side_effect=PermissionError(13, "Access is denied")):
            with self.assertRaises(Failure) as caught:
                start.worktree_done(46)
        self.assertIn("could not delete the empty leftover folder", str(caught.exception))
        self.assertEqual(start.worktree_done(46), 0)
        self.assertFalse(tree.exists())

    def test_a_half_done_removal_says_a_rerun_finishes_it_on_any_os(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.commit_in(tree, "spike.txt")
        git(tree, "push", "-q", "origin", "core/42-vote-tally")
        real = start._git

        def windows_like(*args: str, **kwargs: object) -> Result:
            if args[:2] != ("worktree", "remove"):
                return real(*args, **kwargs)
            real(*args, **kwargs)
            Path(args[2]).mkdir(parents=True)  # git unregistered it, but the folder stayed
            return Result(255, f"error: failed to delete '{args[2]}': Permission denied", False, 0.0)

        with mock.patch.object(start, "_git", side_effect=windows_like), self.assertRaises(Failure) as caught:
            start.worktree_done(42, pushed=True)
        self.assertIn("git already unregistered the worktree", str(caught.exception))
        self.assertTrue(tree.is_dir())
        self.assertEqual(start.worktree_done(42), 0)
        self.assertFalse(tree.exists())
        self.assertEqual(git(self.work, "branch", "--list", "core/42-vote-tally"), "core/42-vote-tally")  # not merged

    @unittest.skipUnless(os.name == "nt", "only Windows refuses to delete a folder that is a process's current folder")
    def test_a_process_sitting_in_the_worktree_leaves_a_removal_that_a_rerun_finishes(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.commit_in(tree, "spike.txt")
        git(tree, "push", "-q", "origin", "core/42-vote-tally")
        holder = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"], cwd=tree)
        self.addCleanup(holder.wait)
        self.addCleanup(holder.kill)
        with self.assertRaises(Failure) as caught:
            start.worktree_done(42, pushed=True)
        self.assertIn("removes the folder once it is empty", str(caught.exception))
        self.assertNotIn(str(tree.resolve()).lower(), start.listed_worktrees())  # git unregistered it...
        self.assertTrue(tree.is_dir())  # ...but the folder stayed
        holder.kill()
        holder.wait()
        self.assertEqual(start.worktree_done(42), 0)  # the rerun finishes it
        self.assertFalse(tree.exists())
        self.assertEqual(git(self.work, "branch", "--list", "core/42-vote-tally"), "core/42-vote-tally")  # not merged

    def test_a_branch_in_a_worktree_is_never_stashed_for(self) -> None:
        self.assertEqual(start.main(42, worktree=True), 0)
        self.write("f.txt", "edited\n")
        with self.assertRaises(Failure) as caught:
            start.main(42, stash=True)
        self.assertIn("checked out in the worktree", str(caught.exception))
        self.assertEqual(git(self.work, "stash", "list"), "")
        self.assertEqual(self.branch(), "main")

    def test_the_engineer_gets_a_worktree_by_default(self) -> None:
        # Issue #51: every engineer task gets its own worktree, where the agent works without prompts, and the
        # main checkout (the Godot editor, the humans' files) is left alone even with no other session active.
        self.write("f.txt", "the human's edit\n")
        self.assertEqual(start.main(42), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.assertEqual(self.branch(), "main")
        self.assertEqual((self.work / "f.txt").read_text(encoding="utf-8"), "the human's edit\n")
        self.assertEqual(self.branch(tree), "core/42-vote-tally")
        self.moves.assert_called_once_with(42, "in-progress")

    def test_include_keeps_the_engineer_here(self) -> None:
        self.write("f.txt", "edited\n")
        self.assertEqual(start.main(42, include=True), 0)  # the changes belong to this task, in this checkout
        self.assertEqual(self.branch(), "core/42-vote-tally")
        self.assertFalse((self.work / ".claude" / "worktrees").exists())

    def test_the_designer_still_works_in_the_main_checkout(self) -> None:
        self.login = "designer"
        self.assertEqual(start.main(42), 0)
        self.assertEqual(self.branch(), "core/42-vote-tally")
        self.assertFalse((self.work / ".claude" / "worktrees").exists())

    def test_the_designer_never_gets_a_worktree_nor_switches_under_a_session(self) -> None:
        self.login = "designer"
        self.other_session()
        with self.assertRaises(Failure) as caught:
            start.main(42)
        self.assertIn("another Claude session is working on this checkout", str(caught.exception))
        self.assertEqual(self.branch(), "main")
        with self.assertRaises(Failure):
            start.main(42, worktree=True)
        self.assertEqual(start.main(42, here=True), 0)  # the human said the other session is idle
        self.assertEqual(self.branch(), "core/42-vote-tally")
        self.assertFalse((self.work / ".claude" / "worktrees").exists())

    def test_no_worktree_for_the_branch_checked_out_here(self) -> None:
        self.assertEqual(start.main(42, here=True), 0)
        with self.assertRaises(Failure) as caught:
            start.main(42, worktree=True)
        self.assertIn("checked out here", str(caught.exception))
        self.other_session()
        self.assertEqual(start.main(42), 0)  # already on it: stays here, no worktree
        self.assertFalse((self.work / ".claude" / "worktrees").exists())

    def test_here_overrides_the_detection(self) -> None:
        self.other_session()
        self.assertEqual(start.main(42, here=True), 0)
        self.assertEqual(self.branch(), "core/42-vote-tally")

    def push_parent(self) -> str:
        """An open parent PR's branch on origin, one commit ahead of main; the checkout goes back to main."""
        git(self.work, "switch", "-q", "-c", "core/41-parent")
        self.write("p.txt", "parent\n")
        git(self.work, "add", "p.txt")
        git(self.work, "commit", "-q", "-m", "parent")
        git(self.work, "push", "-q", "origin", "core/41-parent")
        git(self.work, "switch", "-q", "main")
        git(self.work, "branch", "-q", "-D", "core/41-parent")
        return git(self.work, "rev-parse", "origin/core/41-parent")

    def recorded(self, branch: str = "core/42-vote-tally") -> str:
        res = subprocess.run(["git", "config", "--get", f"branch.{branch}.primeBase"], cwd=self.work, capture_output=True)
        return res.stdout.decode().strip()

    def test_base_branches_from_the_parent_and_records_it(self) -> None:
        tip = self.push_parent()
        self.assertEqual(start.main(42, base="core/41-parent", here=True), 0)
        self.assertEqual(self.branch(), "core/42-vote-tally")
        self.assertEqual(git(self.work, "rev-parse", "HEAD"), tip)
        self.assertEqual(self.recorded(), "core/41-parent")
        self.assertEqual(git(self.work, "config", "--get", "branch.core/42-vote-tally.primeBaseTip"), tip)
        self.assertEqual(subprocess.run(["git", "config", "branch.core/42-vote-tally.merge"], cwd=self.work).returncode, 1)
        self.moves.assert_called_once_with(42, "in-progress")

    def test_base_in_a_worktree(self) -> None:
        tip = self.push_parent()
        self.other_session()
        self.assertEqual(start.main(42, base="core/41-parent"), 0)
        tree = self.work / ".claude" / "worktrees" / "42"
        self.assertEqual(self.branch(), "main")
        self.assertEqual(git(tree, "rev-parse", "HEAD"), tip)
        self.assertEqual(self.recorded(), "core/41-parent")
        with mock.patch.object(start.publish, "REPO", tree):  # publish, run in the worktree, finds the record
            self.assertEqual(start.publish.recorded_base("core/42-vote-tally"), "core/41-parent")

    def test_base_that_origin_lacks_is_refused_and_changes_nothing(self) -> None:
        with self.assertRaises(Failure) as caught:
            start.main(42, base="core/41-typo")
        self.assertIn("origin has no branch core/41-typo", str(caught.exception))
        self.assertEqual(self.branch(), "main")
        self.assertEqual(git(self.work, "branch", "--list", "core/42-*"), "")
        self.moves.assert_not_called()

    def test_base_dry_run_says_it_and_changes_nothing(self) -> None:
        self.push_parent()
        said = mock.MagicMock()
        with mock.patch.object(start, "say", said):
            self.assertEqual(start.main(42, base="core/41-parent", dry_run=True, here=True), 0)
        lines = " ".join(str(c.args[0]) for c in said.call_args_list if c.args)
        self.assertIn("would create core/42-vote-tally from origin/core/41-parent", lines)
        self.assertIn("would record core/41-parent", lines)
        self.assertEqual(self.branch(), "main")
        self.assertEqual(self.recorded(), "")
        self.moves.assert_not_called()

    def test_base_is_ignored_when_resuming_and_says_so(self) -> None:
        self.push_parent()
        self.assertEqual(start.main(42, here=True), 0)  # created from main earlier
        git(self.work, "switch", "-q", "main")
        self.assertEqual(start.main(42, base="core/41-parent", here=True), 0)
        self.assertEqual(self.branch(), "core/42-vote-tally")
        self.assertEqual(git(self.work, "rev-parse", "HEAD"), git(self.work, "rev-parse", "origin/main"))
        self.assertEqual(self.recorded(), "")
        warned = " ".join(str(c.args[0]) for c in start.warn.call_args_list)  # type: ignore[attr-defined]
        self.assertIn("--base core/41-parent is ignored", warned)


class SessionsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="sessions-"))
        self.addCleanup(_rmtree, str(self.tmp))
        self.checkout = self.tmp / "prime-game"
        (self.checkout / ".claude" / "worktrees" / "7").mkdir(parents=True)
        self.now = 1_800_000_000.0
        patch = mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": "me"})
        patch.start()
        self.addCleanup(patch.stop)

    def add(self, pid: int, sid: str, cwd: Path, status: str, age_s: float) -> None:
        data = {"pid": pid, "sessionId": sid, "cwd": str(cwd), "status": status, "updatedAt": (self.now - age_s) * 1000, "procStart": f"{pid}0"}
        (self.tmp / f"{pid}.json").write_text(json.dumps(data), encoding="utf-8")

    def active(self, alive: bool = True) -> list[str]:
        with mock.patch.object(sessions, "process_alive", return_value=alive):
            return [s.session_id for s in sessions.active_on(self.checkout, self.now, self.tmp)]

    def test_which_sessions_count(self) -> None:
        self.add(1, "me", self.checkout, "busy", 0)  # this session
        self.add(2, "busy-old", self.checkout, "busy", 5 * 3600)  # working for hours: counts
        self.add(3, "idle-recent", self.checkout / "core", "idle", 600)  # in a subfolder: counts
        self.add(4, "idle-old", self.checkout, "idle", 2 * 3600)  # finished, never archived
        self.add(5, "worktree", self.checkout / ".claude" / "worktrees" / "7", "busy", 0)
        self.add(6, "elsewhere", self.tmp / "other-project", "busy", 0)
        (self.tmp / "7.json").write_text("{not json", encoding="utf-8")
        self.assertEqual(sorted(self.active()), ["busy-old", "idle-recent"])
        self.assertEqual(self.active(alive=False), [])

    def test_alive_in_counts_every_live_session_in_the_folder_however_idle(self) -> None:
        tree = self.checkout / ".claude" / "worktrees" / "7"
        self.add(1, "me", tree, "busy", 0)  # this session too: its own process holds the folder
        self.add(2, "idle-for-days", tree, "idle", 3 * 86400)
        self.add(3, "in-a-subfolder", tree / "core", "idle", 5 * 3600)
        self.add(4, "main-checkout", self.checkout, "busy", 0)  # the parent folder does not hold the worktree
        self.add(5, "sibling", self.checkout / ".claude" / "worktrees" / "70", "busy", 0)
        with mock.patch.object(sessions, "process_alive", return_value=True):
            found = sorted(s.session_id for s in sessions.alive_in(tree, self.tmp))
        self.assertEqual(found, ["idle-for-days", "in-a-subfolder", "me"])
        with mock.patch.object(sessions, "process_alive", return_value=False):
            self.assertEqual(sessions.alive_in(tree, self.tmp), [])

    def test_process_alive_checks_the_creation_time(self) -> None:
        self.assertTrue(sessions.process_alive(os.getpid()))  # no procStart: any live process counts
        if sessions.IS_WINDOWS:
            # A reused pid: the live process was created at another time than the session file says.
            self.assertFalse(sessions.process_alive(os.getpid(), "1"))
        self.assertFalse(sessions.process_alive(2**22 + 3))  # no such process
        self.add(8, "real", self.checkout, "busy", 0)  # the procStart is kept for the check
        self.assertEqual([s.proc_start for s in sessions.read_all(self.tmp)], ["80"])


if __name__ == "__main__":
    unittest.main()
