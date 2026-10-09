"""publish: which branch it rebases on, what it refuses before touching git history, and when it reuses a green verify
of the same tree instead of verifying again (#471)."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path
from unittest import mock

from runner import publish, wait
from runner.common import ROOT, Failure, Result, force_rmtree


# An hour after the passed records below start (10:00): inside wait.REUSE_MAX_AGE.
NOW = datetime(2026, 10, 6, 11, 0, tzinfo=UTC)


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
        (self.work / "tools" / "runner").mkdir(parents=True)
        self.write(self.work, "tools/runner/r.py", "")  # its tree hash is the runner's version in a verify record
        self.git(self.work, "add", "f.txt", "tools")
        self.git(self.work, "commit", "-q", "-m", "c1")
        self.git(self.work, "push", "-q", "origin", "main")
        self.git(self.work, "config", "core.hooksPath", str(hooks))
        self.other = self.clone("other")  # the other machine, or GitHub's web editor
        self.history = self.tmp / "verify-history.jsonl"
        self.verify = mock.patch.object(publish.verify, "main", return_value=0).start()
        self.addCleanup(mock.patch.stopall)
        self.ok = mock.patch.object(publish, "ok").start()
        for patch in (
            mock.patch.object(publish, "REPO", self.work),
            mock.patch.object(publish, "say"),
            mock.patch.object(publish, "bad"),
            mock.patch.object(publish, "pr_base", return_value=None),
            mock.patch.object(publish.verify, "HISTORY", self.history),  # never this checkout's own history
            mock.patch.object(wait, "utc_now", return_value=NOW),
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

    def record(self, **fields: object) -> None:
        """Append a verify record of the work checkout as it is now (verify.git_facts' keys), passed at 10:00."""
        facts = {f: self.git(self.work, "rev-parse", spec) for f, spec in
                 (("head", "HEAD"), ("tree", "HEAD^{tree}"), ("runner", "HEAD:tools/runner"))}  # fmt: skip
        record = {"start": "2026-10-06T10:00:00Z", "branch": "tooling/1-x", **facts, "status": "passed", **fields}
        with self.history.open("a", encoding="utf-8", newline="\n") as out:
            out.write(json.dumps(record) + "\n")

    def skipped(self) -> bool:
        return any("verify skipped" in str(call.args[0]) for call in self.ok.call_args_list)

    def test_an_identical_tree_verified_green_is_not_verified_again(self) -> None:
        self.git(self.work, "switch", "-q", "-c", "tooling/1-x")
        self.commit(self.work, "g.txt", "mine\n", "mine")
        self.record()
        self.assertEqual(publish.main(), 0)  # the rebase is a no-op: the record stands for this tree
        self.verify.assert_not_called()
        self.assertTrue(self.skipped(), self.ok.call_args_list)
        self.assertEqual(self.remote("tooling/1-x"), self.git(self.work, "rev-parse", "HEAD"))

    def test_a_rebase_that_moves_the_tree_still_verifies(self) -> None:
        self.git(self.work, "switch", "-q", "-c", "tooling/1-x")
        self.commit(self.work, "g.txt", "mine\n", "mine")
        before = self.git(self.work, "rev-parse", "HEAD")
        self.record()
        self.commit(self.other, "h.txt", "theirs\n", "main moves")
        self.git(self.other, "push", "-q", "origin", "main")
        self.assertEqual(publish.main(), 0)
        self.assertNotEqual(self.git(self.work, "rev-parse", "HEAD"), before)
        self.verify.assert_called_once()
        self.assertFalse(self.skipped())

    def test_its_verify_is_quiet_unless_publish_is_verbose(self) -> None:
        # #572: publish --verbose passes it on; by default its verify prints its red steps' lines and its summary.
        self.git(self.work, "switch", "-q", "-c", "tooling/1-x")
        self.commit(self.work, "g.txt", "mine\n", "mine")
        self.assertEqual(publish.main(), 0)
        self.commit(self.work, "g.txt", "more\n", "more")
        self.assertEqual(publish.main(verbose=True), 0)
        self.assertEqual([c.kwargs["verbose"] for c in self.verify.call_args_list], [False, True])

    def test_each_unmet_condition_verifies(self) -> None:
        self.git(self.work, "switch", "-q", "-c", "tooling/1-x")
        self.commit(self.work, "g.txt", "mine\n", "mine")
        cases: dict[str, list[dict[str, object]]] = {
            "no record": [],
            "red": [{"status": "FAILED"}],
            "the newest is red": [{}, {"status": "FAILED"}],
            "another head": [{"head": "b" * 40}],
            "another tree": [{"tree": "c" * 40}],
            "a dirty run": [{"tree": None}],
            "another runner": [{"runner": "d" * 40}],
            "two hours old": [{"start": "2026-10-06T09:00:00Z"}],
            "dirty now": [{}],
        }
        for name, records in cases.items():
            with self.subTest(case=name):
                self.history.unlink(missing_ok=True)
                self.verify.reset_mock()
                self.ok.reset_mock()
                for fields in records:
                    self.record(**fields)
                if name == "dirty now":  # an untracked file: publish's own refusal looks at tracked files only
                    self.write(self.work, "new.txt", "stray\n")
                self.assertEqual(publish.main(), 0)
                self.verify.assert_called_once()
                self.assertFalse(self.skipped())
                (self.work / "new.txt").unlink(missing_ok=True)

    def test_a_red_verify_pushes_nothing(self) -> None:
        self.git(self.work, "switch", "-q", "-c", "tooling/1-x")
        self.commit(self.work, "g.txt", "mine\n", "mine")
        self.record(status="FAILED")
        self.verify.return_value = 1
        with self.assertRaises(Failure) as caught:
            publish.main()
        self.assertIn("verify is red after the rebase; nothing was pushed", str(caught.exception))
        self.assertEqual(self.git(self.tmp / "remote.git", "branch", "--list", "tooling/1-x"), "")

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

    def test_a_branch_that_holds_main_by_a_merge_is_not_replayed(self) -> None:
        # #694: a task branch on a release branch took main in by a merge. The base tip is in HEAD, so there is
        # nothing to replay; a rebase would drop the merge and replay main's commits as the branch's own.
        self.git(self.work, "switch", "-q", "-c", "release/m1")
        self.git(self.work, "push", "-q", "origin", "release/m1")
        self.git(self.work, "switch", "-q", "-c", "tooling/1-x")
        self.git(self.work, "config", "branch.tooling/1-x.primeBase", "release/m1")
        self.git(self.work, "config", "branch.tooling/1-x.primeBaseTip", self.git(self.work, "rev-parse", "HEAD"))
        self.commit(self.work, "g.txt", "mine\n", "mine")
        self.commit(self.other, "h.txt", "theirs\n", "main moves")
        self.git(self.other, "push", "-q", "origin", "main")
        self.git(self.work, "fetch", "-q", "origin")
        self.git(self.work, "merge", "-q", "--no-ff", "-m", "take main", "origin/main")
        before = self.git(self.work, "rev-parse", "HEAD")
        self.assertEqual(publish.main(base="release/m1"), 0)
        self.assertEqual(self.git(self.work, "rev-parse", "HEAD"), before)
        self.assertEqual(self.remote("tooling/1-x"), before)


if __name__ == "__main__":
    unittest.main()
