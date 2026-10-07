"""merge-train (#387): a list of PRs merged into main one by one against a local remote, with gh, publish and verify
stood in for. Nothing reaches GitHub: the remote is a bare repository in a temporary folder, and GitHub's merge is
FakeGitHub's commit on it."""

import os
import subprocess
import time
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, guard, merge, permissions, sessions, slots, train
from runner.common import Failure, Result
from runner.tests.test_merge import MAIN, RULES, FakeGitHub, MergeCase, _gh_result, _git

PASS = {"name": "verify", "state": "SUCCESS", "bucket": "pass"}
PENDING = {"name": "verify", "state": "PENDING", "bucket": "pending"}
MIN_PYTHON_RED = {"name": "runner on the minimum Python", "state": "FAILURE", "bucket": "fail"}
RED = "  FAIL  verify is red after the rebase; nothing was pushed\n"
CONFLICT = "  FAIL  the rebase on origin/main stopped, usually on a conflict. Publish aborted it\n"


class TrainGitHub(FakeGitHub):
    """FakeGitHub whose PRs follow their branch on the remote (a push moves the head, as on GitHub) and whose checks
    come from a script per PR: each call takes the next list (the last one repeats), or a gh error string."""

    def __init__(self, repo) -> None:  # type: ignore[no-untyped-def]
        super().__init__(repo)
        self.ci: dict[int, list[list[dict] | str]] = {}
        self.ci_calls: dict[int, int] = {}

    def view(self, number: int) -> dict:
        data = self.prs[number]
        remote = self.repo.tmp / "remote.git"
        if data["state"] == "OPEN":
            oid = _git(remote, "for-each-ref", "--format=%(objectname)", f"refs/heads/{data['headRefName']}")
            data["headRefOid"] = oid or data["headRefOid"]
        return super().view(number)

    def __call__(self, *args: str) -> Result:
        if args[:2] == ("pr", "checks"):
            number = int(args[2])
            script = self.ci.get(number, [[PASS]])
            calls = self.ci_calls[number] = self.ci_calls.get(number, 0) + 1
            step = script[min(calls, len(script)) - 1]
            if isinstance(step, str):
                return _gh_result(step, 1)
            return _gh_result(step, 0 if step else 1) if step else _gh_result("no checks reported", 1)
        return super().__call__(*args)


class TrainCase(MergeCase):
    FILES = {**MergeCase.FILES, "tools/runner/guard.py": "X = 1\n"}

    def setUp(self) -> None:
        super().setUp()
        self.gh = TrainGitHub(self.repo)
        self.wts: dict[int, Path] = {}
        self.publish_script: dict[int, list[str]] = {}
        self.published: list[int] = []
        self.verify_script: dict[int, list[int]] = {}
        self.verified_in: list[int] = []
        self.holders: list[slots.Holder] = []
        self.live: list[sessions.Session] = []
        self.clock = [0.0]
        self.sleeps: list[float] = []
        for patch in (
            mock.patch.object(merge, "gh", self.gh),
            mock.patch.object(train, "publish_in", self.fake_publish),
            mock.patch.object(train, "verify_in", self.fake_verify_in),
            mock.patch.object(train, "slot_holders", lambda: self.holders),
            mock.patch.object(sessions, "alive_in", lambda path, folder=None: self.live),
            mock.patch.object(train, "_now", lambda: self.clock[0]),
            mock.patch.object(train, "_sleep", self.sleep),
            mock.patch.object(train, "say", lambda text="": self.printed.append(text)),
            mock.patch.object(train, "ok", lambda text: self.printed.append(text)),
            mock.patch.object(train, "bad", lambda text, fix="": self.printed.append(text)),
            mock.patch.object(train, "warn", lambda text: self.printed.append(text)),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.clock[0] += seconds

    def pr(self, number: int, files: dict[str, str | None], **extra: object) -> Path:
        """An open PR into main from a task branch checked out in its own worktree and pushed."""
        branch = f"core/{number}-task"
        wt = self.repo.tmp / f"wt-{number}"
        _git(self.repo.work, "fetch", "-q", "origin")
        _git(self.repo.work, "worktree", "add", "-q", "-b", branch, wt.as_posix(), "origin/main")
        self.repo.commit_in(wt, files, f"feat: task {number}")
        self.repo.push(branch)
        self.gh.add(number, branch, "main")
        self.gh.prs[number].update(extra)
        self.wts[number] = wt
        return wt

    def number_of(self, wt: Path) -> int:
        return next(n for n, path in self.wts.items() if path == wt)

    def fake_publish(self, wt: Path, log: str) -> Result:
        """publish as the worktree's runner would: rebase on origin/main and push, or stop as scripted."""
        number = self.number_of(wt)
        self.published.append(number)
        step = (self.publish_script.get(number) or ["green"]).pop(0)
        if step == "rebased-red":  # as publish does: the rebase stays when its verify is red
            _git(wt, "fetch", "-q", "origin")
            _git(wt, "rebase", "-q", "origin/main")
            step = "red"
        if step == "red":
            return Result(1, "verify summary\n  failed  test 900.0s\n" + RED, False, 0.0)
        if step == "conflict":
            return Result(1, CONFLICT, False, 0.0)
        if step == "stale":
            return Result(1, "  FAIL  the push was rejected. 'stale info' means the remote branch moved\n", False, 0.0)
        branch = _git(wt, "symbolic-ref", "--short", "HEAD")
        _git(wt, "fetch", "-q", "origin")
        _git(wt, "rebase", "-q", "origin/main")
        _git(wt, "push", "-q", "--no-verify", "--force", "origin", branch)
        return Result(0, "publish: done\n", False, 0.0)

    def fake_verify_in(self, wt: Path, log: str) -> Result:
        number = self.number_of(wt)
        self.verified_in.append(number)
        rc = (self.verify_script.get(number) or [0]).pop(0)
        return Result(rc, "verify summary\n", False, 0.0)

    def train(self, *numbers: int, dry_run: bool = False, recent: int = 0) -> tuple[int, str]:
        self.printed.clear()
        rc = train.main(list(numbers), base="main", dry_run=dry_run, recent_minutes=recent)
        return rc, "\n".join(self.printed)

    def summary(self) -> list[str]:
        return self.printed[self.printed.index("merge-train summary") :]

    def remote_main_parents(self) -> list[list[str]]:
        """The parents of each commit on the remote's main since the base, newest first."""
        remote = self.repo.tmp / "remote.git"
        out = _git(remote, "log", "--first-parent", "--format=%P", f"{self.repo.base}..main")
        return [line.split() for line in out.splitlines()]

    def main_moves(self, files: dict[str, str | None]) -> None:
        """Another PR merged on GitHub: main moves on the remote."""
        _git(self.repo.work, "fetch", "-q", "origin")
        _git(self.repo.work, "switch", "-q", "-C", "other", "origin/main")
        self.repo.commit(files, "another merge")
        self.repo.push("other:main")
        _git(self.repo.work, "switch", "-q", "main")


class TrainTest(TrainCase):
    def test_prs_merge_in_series_each_after_main_moved(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        self.pr(31, {"core/b.gd": "extends Node\n"})
        rc, text = self.train(30, 31)
        self.assertEqual(rc, 0, text)
        self.assertEqual(self.published, [31])  # #30 had main in its head; #31 was behind once #30 merged
        self.assertEqual([args[2] for args in self.gh.merges], ["30", "31"])
        parents = self.remote_main_parents()
        self.assertEqual(len(parents), 2)
        self.assertEqual(parents[0][1], self.gh.prs[31]["headRefOid"])  # GitHub's merge of the rebased head
        self.assertEqual(parents[1][1], self.gh.prs[30]["headRefOid"])
        self.assertEqual(sum(line.startswith("wave: merged #") for line in self.printed), 2)
        self.assertIn("train: #30: in ", text)
        self.assertIn("way: main is already in its head: no publish", text)
        self.assertIn("way: publish (rebase on origin/main, verify, push with a lease)", text)
        self.assertEqual(self.summary(), [
            "merge-train summary",
            "  merged   #30 (core/30-task): no publish (main was in its head), CI green, the gate passed",
            "  merged   #31 (core/31-task): published, CI green, the gate passed",
            "merge-train: 2 merged, 0 skipped of 2 PRs",
        ])  # fmt: skip
        # Run again: both are merged now.
        rc, text = self.train(30, 31)
        self.assertEqual(rc, 0, text)
        self.assertEqual(self.summary()[1], "  merged   #30 (core/30-task): already merged")

    def test_a_red_verify_is_retried_once_and_a_second_red_skips_and_goes_on(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        self.pr(31, {"core/b.gd": "extends Node\n"})
        self.pr(32, {"core/c.gd": "extends Node\n"})
        self.main_moves({"core/z.gd": "extends Node\n"})
        self.publish_script = {30: ["red", "green"], 31: ["rebased-red", "rebased-red"]}
        head_31 = self.gh.prs[31]["headRefOid"]
        rc, text = self.train(30, 31, 32)
        self.assertEqual(rc, 1, text)
        self.assertEqual(self.published, [30, 30, 31, 31, 32])
        self.assertEqual(text.count("is red on the first try: retrying once (a timeout on a busy PC"), 2)
        self.assertEqual([args[2] for args in self.gh.merges], ["30", "32"])
        summary = self.summary()
        self.assertEqual(summary[1:4:2], [
            "  merged   #30 (core/30-task): published, CI green, the gate passed",
            "  merged   #32 (core/32-task): published, CI green, the gate passed",
        ])  # fmt: skip
        self.assertRegex(summary[2], r"^  skipped  #31 \(core/31-task\): verify was red twice after the rebase: "
                                     r"nothing was pushed; its rebase undone \(\w{10} -> " + head_31[:10] + r"\)$")
        self.assertEqual(summary[4], "merge-train: 2 merged, 1 skipped of 3 PRs")
        # The worktree is back at the PR's head, so the next run takes the PR again instead of finding it held.
        self.assertEqual(_git(self.wts[31], "rev-parse", "HEAD"), head_31)
        rc, text = self.train(31)
        self.assertEqual(rc, 0, text)
        self.assertEqual(self.published[-1], 31)
        self.assertEqual([args[2] for args in self.gh.merges], ["30", "32", "31"])

    def test_a_rebase_conflict_or_another_stop_skips_without_a_retry(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        self.pr(31, {"core/b.gd": "extends Node\n"})
        self.main_moves({"core/z.gd": "extends Node\n"})
        self.publish_script = {30: ["conflict"], 31: ["stale"]}
        rc, text = self.train(30, 31)
        self.assertEqual(rc, 1, text)
        self.assertEqual(self.published, [30, 31])
        self.assertNotIn("retrying", text)
        self.assertEqual(self.gh.merges, [])
        self.assertIn("#30 (core/30-task): the rebase on origin/main stopped on a conflict (publish aborted it): "
                      "pr-rebase", self.summary()[1])  # fmt: skip
        self.assertIn("#31 (core/31-task): publish stopped: the push was rejected. 'stale info'", self.summary()[2])

    def test_a_hung_git_call_skips_one_pr_and_the_train_goes_on(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        self.pr(31, {"core/b.gd": "extends Node\n"})
        real = merge._out
        hangs = [1]

        def hang_once(*args: str, cwd: Path | None = None) -> str:
            if args[:2] == ("worktree", "list") and hangs:
                hangs.pop()
                raise subprocess.TimeoutExpired(["git", *args], merge.TIMEOUT)
            return real(*args, cwd=cwd)

        with mock.patch.object(merge, "_out", hang_once):
            rc, text = self.train(30, 31)
        self.assertEqual(rc, 1, text)
        self.assertEqual([args[2] for args in self.gh.merges], ["31"])
        self.assertIn("  skipped  #30: Command '['git', 'worktree', 'list'", self.summary()[1])
        self.assertEqual(self.summary()[3], "merge-train: 1 merged, 1 skipped of 2 PRs")

    def test_an_unexpected_error_still_prints_the_summary(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        self.pr(31, {"core/b.gd": "extends Node\n"})
        real = train.ride

        def broken(number: int, recent_minutes: int) -> train.Outcome:
            if number == 31:
                raise RuntimeError("a bug")
            return real(number, recent_minutes)

        with mock.patch.object(train, "ride", broken), self.assertRaises(RuntimeError):
            self.train(30, 31)
        self.assertEqual(self.summary(), [
            "merge-train summary",
            "  merged   #30 (core/30-task): no publish (main was in its head), CI green, the gate passed",
            "merge-train: 1 merged, 0 skipped of 1 PRs, 1 not tried (the train stopped)",
        ])  # fmt: skip

    def test_red_ci_skips_at_once_and_names_the_failed_job(self) -> None:
        # 2026-10-04: a new required job, "runner on the minimum Python", failed #321 while verify passed.
        self.pr(30, {"core/a.gd": "extends Node\n"})
        self.gh.ci[30] = [[PASS, MIN_PYTHON_RED | {"bucket": "pending", "state": "PENDING"}], [PASS, MIN_PYTHON_RED]]
        rc, text = self.train(30)
        self.assertEqual(rc, 1, text)
        self.assertEqual(self.gh.merges, [])
        self.assertEqual(self.summary()[1], "  skipped  #30 (core/30-task): CI is red: runner on the minimum Python: "
                                            "FAILURE")  # fmt: skip
        self.assertEqual(self.sleeps, [train.POLL])  # the first poll was pending, the second red: no more waiting

    def test_pending_ci_and_gh_errors_are_waited_on_within_the_bound(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        self.pr(31, {"core/b.gd": "extends Node\n"})
        # No checks yet, a gh call that failed (a hang ends as a timeout), pending, then green.
        self.gh.ci[30] = [[], "error connecting to api.github.com", [PENDING], [PASS]]
        self.gh.ci[31] = [[PENDING]]
        rc, text = self.train(30, 31)
        self.assertEqual(rc, 1, text)
        self.assertEqual([args[2] for args in self.gh.merges], ["30"])
        self.assertEqual(self.summary()[2], "  skipped  #31 (core/31-task): CI gave no verdict within 40 min (verify)")
        self.assertLessEqual(self.clock[0], 3 * train.POLL + train.CI_WAIT + train.HEAD_WAIT)

    def test_gh_pr_checks_exit_code_is_never_the_verdict(self) -> None:
        # gh pr checks exits 8 while a check is pending and 1 when one failed: only the JSON tells them apart.
        self.pr(30, {"core/a.gd": "extends Node\n"})
        real = self.gh.__call__

        def nonzero(*args: str) -> Result:
            res = real(*args)
            return Result(8, res.out, False, 0.0) if args[:2] == ("pr", "checks") else res

        with mock.patch.object(merge, "gh", nonzero):
            self.gh.ci[30] = [[PENDING], [PASS]]
            self.assertEqual(train.wait_ci(30), "")

    def test_the_gates_standing_refusals_skip_before_any_publish(self) -> None:
        self.pr(30, {"tools/runner/guard.py": "X = 2\n"})
        self.pr(31, {"core/b.gd": "extends Node\n"}, body="## Needs the engineer\n1. Which port?\n")
        self.pr(32, {"core/c.gd": "extends Node\n"}, author={"login": merge.DESIGNER_LOGIN})
        self.main_moves({"core/z.gd": "extends Node\n"})
        rc, text = self.train(30, 31, 32)
        self.assertEqual(rc, 1, text)
        self.assertEqual((self.published, self.gh.merges), ([], []))
        summary = self.summary()
        self.assertIn("#30 (core/30-task): the gate would refuse it whatever a publish does: permission and safety "
                      "files (tools/runner/guard.py)", summary[1])  # fmt: skip
        self.assertIn("\"Needs the engineer\": item 1 (\"Which port?\") has no \"Answered", summary[2])
        self.assertIn("is not authored by the engineer's account", summary[3])

    def test_a_refusal_at_the_gate_skips_and_merges_nothing(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"}, mergeable="CONFLICTING")
        rc, text = self.train(30)
        self.assertEqual(rc, 1, text)
        self.assertEqual(self.gh.merges, [])
        self.assertIn("gate: refused: GitHub says it is not mergeable", text)
        self.assertEqual(self.summary()[1], "  skipped  #30 (core/30-task): the gate refused it (its gate: refused "
                                            "lines above)")  # fmt: skip

    def test_prs_it_cannot_take(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        self.gh.add(31, "core/30-task", "release/m1")  # another base
        for branch, start in (("core/32-task", "main"), ("release/m1", "origin/release/m1")):
            _git(self.repo.work, "switch", "-q", "-C", branch, start)
            self.repo.commit({f"core/{branch.replace('/', '_')}.gd": "extends Node\n"}, branch)
            self.repo.push(branch)
        _git(self.repo.work, "switch", "-q", "main")
        self.gh.add(32, "core/32-task", "main")  # no worktree has it
        self.gh.add(33, "release/m1", "main")  # a milestone's closing PR
        self.gh.prs[33]["body"] = "Approved by the engineer: https://github.com/o/r/pull/33#issuecomment-1\n"
        self.gh.add(34, "core/30-task", "main", state="CLOSED")
        self.gh.prs[34]["state"] = "CLOSED"
        rc, text = self.train(31, 32, 33, 34)
        self.assertEqual(rc, 1, text)
        self.assertEqual((self.published, self.gh.merges), ([], []))
        self.assertEqual(self.summary()[1:5], [
            "  skipped  #31 (core/30-task): it targets release/m1: merge-train merges only into main",
            "  skipped  #32 (core/32-task): no worktree has core/32-task checked out (git worktree list): publish it "
            "in its own checkout first",
            "  skipped  #33 (release/m1): its head release/m1 is not a task branch <area>/<n>-<slug>: merge it with "
            "merge 33 --base main",
            "  skipped  #34 (core/30-task): it is closed, not open",
        ])  # fmt: skip

    def test_never_touches_a_worktree_a_live_run_holds(self) -> None:
        wt = self.pr(30, {"core/a.gd": "extends Node\n"})
        self.main_moves({"core/z.gd": "extends Node\n"})
        live = sessions.Session(os.getpid(), "other", str(wt), "busy", 0.0, "implementer")

        def dirty() -> None:
            (wt / "core" / "a.gd").write_text("extends Object\n", encoding="utf-8")

        def clean() -> None:
            _git(wt, "checkout", "--", ".")

        def local_commit() -> None:
            self.repo.commit_in(wt, {"core/d.gd": "extends Node\n"}, "wip")

        def drop_local_commit() -> None:
            _git(wt, "reset", "-q", "--hard", "HEAD~1")

        def rebase_in_progress() -> None:
            (Path(_git(wt, "rev-parse", "--absolute-git-dir")) / "rebase-merge").mkdir()

        def no_rebase() -> None:
            (Path(_git(wt, "rev-parse", "--absolute-git-dir")) / "rebase-merge").rmdir()

        def bisect() -> None:
            (Path(_git(wt, "rev-parse", "--absolute-git-dir")) / "BISECT_LOG").write_text("# bad\n", encoding="utf-8")

        def no_bisect() -> None:
            (Path(_git(wt, "rev-parse", "--absolute-git-dir")) / "BISECT_LOG").unlink()

        cases = [
            ("a verify slot", lambda: self.holders.append(slots.Holder(2, wt.as_posix(), "core/30-task", os.getpid(),
                                                                         "2026-10-05T01:00:00Z")),
             self.holders.clear, "a verify holds slot 2 there (pid "),
            ("a load run", lambda: self.holders.append(slots.Holder(1, wt.as_posix(), "core/30-task", os.getpid(),
                                                                     "2026-10-05T01:00:00Z", slots.LOAD)),
             self.holders.clear, "a load run holds slot 1 there (pid "),
            ("a busy session", lambda: self.live.append(live), self.live.clear, "the Claude Code session 'implementer'"),
            ("a rebase", rebase_in_progress, no_rebase, "a rebase is in progress there"),
            ("a bisect", bisect, no_bisect, "a bisect is in progress there"),
            ("uncommitted changes", dirty, clean, "uncommitted changes there (1 files)"),
            ("a local commit", local_commit, drop_local_commit, "its HEAD "),
        ]  # fmt: skip
        for name, hold, release, expected in cases:
            with self.subTest(name):
                hold()
                head = _git(wt, "rev-parse", "HEAD")
                rc, text = self.train(30)
                self.assertEqual(rc, 1, text)
                self.assertIn(f"skipped  #30 (core/30-task): {wt.as_posix()} is held: {expected}", self.summary()[1])
                self.assertEqual(_git(wt, "rev-parse", "HEAD"), head)
                self.assertEqual(self.published, [])
                release()
        self.assertIn("is not the PR's head", text)  # the last case's whole reason
        # A slot holder elsewhere or a stale holder file (its process is gone) does not hold it.
        self.holders.append(slots.Holder(1, (self.repo.tmp / "elsewhere").as_posix(), "x/1-y", os.getpid(), "?"))
        self.holders.append(slots.Holder(2, wt.as_posix(), "core/30-task", None, "?"))
        # An idle session updated within --recent minutes holds it (it may wait for its human's answer); a stale one
        # (a finished Desktop session never archived) does not.
        self.live.append(sessions.Session(os.getpid(), "idle one", str(wt), "idle", time.time() - 60, "waiting"))
        rc, text = self.train(30, recent=10)
        self.assertEqual(rc, 1, text)
        self.assertIn("is held: the Claude Code session 'waiting' (pid ", self.summary()[1])
        self.assertIn("idle, last update 1 min ago", self.summary()[1])
        self.assertEqual(self.published, [])
        self.live[0] = sessions.Session(os.getpid(), "idle one", str(wt), "idle", time.time() - 3600, "finished")
        # A commit younger than --recent holds it; --recent 0 lets the train in.
        rc, text = self.train(30, recent=10)
        self.assertEqual(rc, 1, text)
        self.assertIn("its last commit is 0 min old (under --recent 10): a run may still work there; once you know "
                      "it ended, run again with --recent 0", self.summary()[1])  # fmt: skip
        self.assertEqual(self.published, [])
        rc, text = self.train(30)
        self.assertEqual(rc, 0, text)
        self.assertEqual(self.published, [30])

    def test_a_branch_with_merges_of_main_takes_main_in_by_a_merge(self) -> None:
        wt = self.pr(30, {"core/a.gd": "extends Node\n"})
        self.main_moves({"core/y.gd": "extends Node\n"})
        _git(wt, "fetch", "-q", "origin")
        _git(wt, "merge", "-q", "--no-edit", "origin/main")  # someone took main in by a merge before
        self.repo.push("core/30-task")
        self.main_moves({"core/z.gd": "extends Node\n"})
        self.repo.install_hook()  # the merge way's push is a fast-forward the pre-push hook allows
        before = self.repo.remote("core/30-task")
        rc, text = self.train(30)
        self.assertEqual(rc, 0, text)
        self.assertIn("way: its history holds merge commits: merge origin/main into it, verify, push", text)
        self.assertEqual((self.published, self.verified_in), ([], [30]))
        head = self.repo.remote("core/30-task")
        remote = self.repo.tmp / "remote.git"
        self.assertEqual(_git(remote, "merge-base", "--is-ancestor", before, head), "")  # no rewrite
        self.assertEqual(_git(remote, "log", "-1", "--format=%P", head).split()[0], before)
        self.assertEqual([args[2] for args in self.gh.merges], ["30"])
        self.assertIn("origin/main merged in, CI green, the gate passed", self.summary()[1])

    def test_the_merge_way_retries_a_red_verify_once_and_undoes_its_merge_after_two(self) -> None:
        wt = self.pr(30, {"core/a.gd": "extends Node\n"})
        self.main_moves({"core/y.gd": "extends Node\n"})
        _git(wt, "fetch", "-q", "origin")
        _git(wt, "merge", "-q", "--no-edit", "origin/main")
        self.repo.push("core/30-task")
        self.main_moves({"core/z.gd": "extends Node\n"})
        before = _git(wt, "rev-parse", "HEAD")
        self.verify_script[30] = [1, 1]
        rc, text = self.train(30)
        self.assertEqual(rc, 1, text)
        self.assertEqual(self.verified_in, [30, 30])
        self.assertIn("verify is red on the first try: retrying once", text)
        self.assertEqual((_git(wt, "rev-parse", "HEAD"), self.repo.remote("core/30-task")), (before, before))
        self.assertIn("verify was red twice after merging origin/main: nothing was pushed; the merge commit undone",
                      self.summary()[1])  # fmt: skip
        # A conflict with main is aborted and leaves the branch as it was.
        self.main_moves({"core/a.gd": "extends Object\n"})
        rc, text = self.train(30)
        self.assertEqual(rc, 1, text)
        self.assertIn("merging origin/main stopped on a conflict (aborted): pr-rebase", self.summary()[1])
        self.assertEqual(_git(wt, "rev-parse", "HEAD"), before)
        self.assertEqual(_git(wt, "status", "--porcelain"), "")

    def test_dry_run_prints_the_plan_and_changes_nothing(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        self.pr(31, {"core/b.gd": "extends Node\n"})
        main = self.repo.remote("main")
        rc, text = self.train(30, 31, dry_run=True)
        self.assertEqual(rc, 0, text)
        self.assertIn("plan: #30 (core/30-task) in ", text)
        self.assertIn(": main is already in its head: no publish", text)
        self.assertIn("gate: #30 would merge into main", text)
        self.assertIn("merge-train --dry-run: every PR would go; nothing changed", text)
        self.assertEqual((self.published, self.verified_in, self.gh.merges), ([], [], []))
        self.assertEqual(self.repo.remote("main"), main)
        self.main_moves({"core/z.gd": "extends Node\n"})
        self.pr(32, {"tools/runner/guard.py": "X = 3\n"})
        rc, text = self.train(30, 32, dry_run=True)
        self.assertEqual(rc, 1, text)
        self.assertIn("plan: #30 (core/30-task) in ", text)
        self.assertIn(": publish (rebase on origin/main, verify, push with a lease)", text)
        self.assertIn("gate: refused: behind main", text)
        self.assertIn("plan: #32 (core/32-task): would skip: the gate would refuse it whatever a publish does", text)
        self.assertEqual((self.published, self.gh.merges), ([], []))

    def test_refusals_before_anything_runs(self) -> None:
        with self.assertRaises(Failure) as caught:
            train.main([30], base="release/m1")
        self.assertIn("merge-train merges only into main", str(caught.exception))
        self.pr(30, {"core/a.gd": "extends Node\n"})
        with mock.patch.object(merge, "_cwd", lambda: self.wts[30]), self.assertRaises(Failure) as caught:
            train.main([30], base="main")
        self.assertIn("is a task's checkout", str(caught.exception))
        self.assertEqual(self.gh.merges, [])


class OwnRepo(guard.NoRepo):
    def github_repo(self) -> str | None:
        return "xperiaroco2/prime-game"


class TrainCommandTest(unittest.TestCase):
    LOG = "/c/Users/u/AppData/Local/Temp/claude/D--prime-game/x/scratchpad/manager/train-1.log"
    TYPED = [
        ("PowerShell", r"tools\run.cmd merge-train 350 321 --base main"),
        ("PowerShell", r"tools\run.cmd merge-train 350 321 --base main --dry-run"),
        ("Bash", f'tools/run.sh merge-train 350 321 --base main > {LOG} 2>&1; echo "exit=$?" >> {LOG}'),
        ("Bash", f"tools/run.sh wait {LOG}"),
    ]

    def test_the_typed_commands_run_without_a_prompt_from_the_main_checkout(self) -> None:
        # The unattended-work ADR: the manager's background train and its polling never ask, outside bypass too.
        for tool, command in self.TYPED:
            # Outside bypass: a human's own acceptEdits session (both humans' default mode), rules alone; and default
            # mode, which since #312 prompts for every file write, for the calls that redirect none.
            modes = [permissions.ACCEPT_EDITS] + ([permissions.DEFAULT] if ">" not in command else [])
            for mode in modes:
                with self.subTest(command=command, mode=mode):
                    verdict = permissions.verdict(RULES, guard, tool, command, MAIN, MAIN, OwnRepo(), mode=mode, attended=True)
                    self.assertEqual(verdict[0], permissions.PASS, verdict)

    def test_the_parser(self) -> None:
        parser = cli.build_parser()
        args = parser.parse_args(["merge-train", "350", "321", "--base", "main", "--dry-run"])
        self.assertEqual((args.prs, args.base, args.dry_run, args.recent), ([350, 321], "main", True, 10))
        self.assertEqual(args.recent, train.RECENT_MINUTES)
        with mock.patch("sys.stderr"), self.assertRaises(SystemExit):
            parser.parse_args(["merge-train", "350"])  # --base is required


if __name__ == "__main__":
    unittest.main()
