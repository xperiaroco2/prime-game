"""publish: which branch it rebases on, and what it refuses before touching git history."""

import unittest
from unittest import mock

from runner import publish
from runner.common import Failure, Result


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


if __name__ == "__main__":
    unittest.main()
