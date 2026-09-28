"""`start` and `worktree-done` against a real temp repo with a bare remote; gh, the board and sessions are stubbed."""

import json
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from runner import sessions, start
from runner.common import Failure
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
        self.others: list[sessions.Session] = []
        self.gh_calls: list[tuple[str, ...]] = []
        self.moves = mock.MagicMock()
        for patch in (
            mock.patch.object(start, "REPO", self.work),
            mock.patch.object(start, "_gh", side_effect=self.fake_gh),
            mock.patch.object(start.board, "move", self.moves),
            mock.patch.object(start.sessions, "active_on", side_effect=lambda _repo: self.others),
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
        self.assertEqual(start.main(42), 0)
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
            start.main(42)
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
        self.assertEqual(start.main(42), 0)
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

    def test_the_designer_never_gets_a_worktree(self) -> None:
        self.login = "designer"
        self.other_session()
        self.assertEqual(start.main(42), 0)
        self.assertEqual(self.branch(), "core/42-vote-tally")
        self.assertFalse((self.work / ".claude" / "worktrees").exists())
        with self.assertRaises(Failure):
            start.main(42, worktree=True)

    def test_here_overrides_the_detection(self) -> None:
        self.other_session()
        self.assertEqual(start.main(42, here=True), 0)
        self.assertEqual(self.branch(), "core/42-vote-tally")


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
        data = {"pid": pid, "sessionId": sid, "cwd": str(cwd), "status": status, "updatedAt": (self.now - age_s) * 1000}
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

    def test_process_alive_checks_the_program(self) -> None:
        self.assertFalse(sessions.process_alive(os.getpid()))  # alive, but Python, not Claude Code
        self.assertFalse(sessions.process_alive(2**22 + 3))  # no such process


if __name__ == "__main__":
    unittest.main()
