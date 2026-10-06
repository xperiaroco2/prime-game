"""`inbox` (#485): the GitHub half of the secretary's digest, from canned gh output."""

import io
import unittest
from contextlib import redirect_stderr, redirect_stdout
from typing import Any
from unittest import mock

from runner import inbox, merge
from runner.common import Failure

ENGINEER = merge.ENGINEER_LOGIN
DESIGNER = merge.DESIGNER_LOGIN

# The manager's block in a wave comment's notes, and housekeeping's own line further down (wave.py's shape).
WAVE = """# Wave 3 of the meta manager

For you:
1. Merge PR #490 yourself (the gate's exception: `.claude/settings.json`): https://github.com/o/r/pull/490
2. Answer PR #474's question 1: keep the 5 s timeout (recommended) or 10 s.
   The scenario: a join over a dead service waits 30 s.
3. Pull the main checkout:
```powershell
cd D:\\prime-game; git pull
```

Order from here: #484, then #485.

## Housekeeping

For you: nothing.

None.
"""


def comment(thread: int, created: str, body: str, login: str = ENGINEER, cid: int = 1) -> dict[str, Any]:
    return {
        "issue_url": f"https://api.github.com/repos/o/r/issues/{thread}",
        "html_url": f"https://github.com/o/r/issues/{thread}#issuecomment-{cid}",
        "created_at": created,
        "user": {"login": login},
        "body": body,
    }


def pr(number: int, body: str = "", base: str = "main", files: tuple[str, ...] = (), **extra: Any) -> dict[str, Any]:
    data: dict[str, Any] = {
        "number": number,
        "title": f"PR {number}",
        "url": f"https://github.com/o/r/pull/{number}",
        "body": body,
        "isDraft": False,
        "baseRefName": base,
        "headRefName": f"tooling/{number}-x",
        "author": {"login": ENGINEER},
        "files": [{"path": p, "changeType": "MODIFIED"} for p in files],
        "latestReviews": [],
    }
    data.update(extra)
    return data


class LabelTest(unittest.TestCase):
    def test_labels_and_their_rest(self) -> None:
        cases = {
            "For you:": "",
            "For you: nothing.": "nothing.",
            "**For you:** merge PR #1": "merge PR #1",
            "**For you**: merge PR #1": "merge PR #1",
            "### For you": "",
            "## Для вас:": "",
            "Для вас: 1. злити PR": "1. злити PR",
            "**For you**": "",
        }
        for line, rest in cases.items():
            self.assertEqual(inbox.label_rest(line), rest, line)

    def test_prose_is_no_label(self) -> None:
        for line in ("For you to decide, the options below.", "For your answer: see #3", "Not for you: x"):
            self.assertIsNone(inbox.label_rest(line), line)


class BlockTest(unittest.TestCase):
    def test_wave_comment_items_keep_their_lines_and_fences(self) -> None:
        items = inbox.for_you_block(WAVE)
        assert items is not None
        self.assertEqual(len(items), 3, items)
        self.assertTrue(items[0][0].startswith("1. Merge PR #490"))
        self.assertEqual(items[1][1], "   The scenario: a join over a dead service waits 30 s.")
        self.assertEqual(items[2][1:], ["```powershell", "cd D:\\prime-game; git pull", "```"])
        self.assertNotIn("Order from here", "\n".join(line for item in items for line in item))

    def test_nothing_and_none(self) -> None:
        self.assertEqual(inbox.for_you_block("Done.\n\nFor you: nothing.\n"), [])
        self.assertEqual(inbox.for_you_block("Для вас: нічого.\n"), [])
        self.assertIsNone(inbox.for_you_block("Merged #3.\n\nFor your eyes only: nothing here."))
        self.assertIsNone(inbox.for_you_block("<!-- For you: a hint in a comment -->\nMerged #3."))

    def test_bullets_and_a_heading_end(self) -> None:
        body = "### For you\n- **Look at** the loop:\n  https://x/pull/37\n- merge it\n### Next\n- not mine\n"
        self.assertEqual(inbox.for_you_block(body), [["- **Look at** the loop:", "  https://x/pull/37"], ["- merge it"]])

    def test_inline_item_on_the_label_line(self) -> None:
        body = "For you: close the Claude session in worktree 260, then run its block below.\n\n```powershell\nx\n```\n"
        items = inbox.for_you_block(body)
        assert items is not None
        self.assertEqual(items[0][0], "close the Claude session in worktree 260, then run its block below.")
        self.assertEqual(items[0][1:], ["```powershell", "x", "```"])


class ForYouOfTest(unittest.TestCase):
    def test_latest_block_per_thread_by_the_engineer_with_later_comments(self) -> None:
        comments = [
            comment(302, "2026-10-06T10:00:00Z", "For you:\n1. old item", cid=1),
            comment(302, "2026-10-06T12:00:00Z", WAVE, cid=2),
            comment(302, "2026-10-06T13:00:00Z", "The engineer's answers: 1A.", cid=3),
            comment(302, "2026-10-06T14:00:00Z", "For you:\n1. the designer's own", login=DESIGNER, cid=4),
            comment(33, "2026-10-06T11:00:00Z", "For you: nothing.", cid=5),
            comment(40, "2026-10-06T15:00:00Z", "No block here.", cid=6),
        ]
        found = inbox.for_you_of(comments)
        self.assertEqual([(f.thread, f.later) for f in found], [(302, 2), (33, 0)])
        self.assertTrue(found[0].url.endswith("issuecomment-2"))
        self.assertEqual(len(found[0].items), 3)
        self.assertEqual(found[1].items, [])


class PullRequestsTest(unittest.TestCase):
    def test_open_needs_items_name_the_pr(self) -> None:
        body = "## Needs the engineer\n1. Pick 3 or 5 s.\n2. Keep it. Answered: https://github.com/o/r/pull/1#c\n"
        found = inbox.needs_of([pr(474, body, base="release/m6", isDraft=True), pr(5, "## Needs the engineer\nNone.")])
        self.assertEqual(len(found), 1, found)
        self.assertIn("PR #474 (into release/m6, draft)", found[0])
        self.assertIn('item 1 ("Pick 3 or 5 s.")', found[0])
        self.assertTrue(found[0].endswith("https://github.com/o/r/pull/474"))

    def test_gate_exceptions_only_for_ready_engineer_prs_into_main(self) -> None:
        settings = (".claude/settings.json",)
        prs = [
            pr(1, files=settings),
            pr(2, files=settings, isDraft=True),
            pr(3, files=settings, base="release/m6"),
            pr(4, files=settings, author={"login": DESIGNER}),
            pr(5, files=("docs/decisions/2026-10-07-x.md",)),
            pr(6, "Approved by the engineer: https://github.com/o/r/issues/170#c", files=("docs/decisions/x.md",)),
            pr(7, files=("content/roles/x.tres",), latestReviews=[{"author": {"login": DESIGNER}, "state": "APPROVED"}]),
            pr(8, files=("content/roles/x.tres",)),
        ]
        found = inbox.exceptions_of(prs)
        self.assertEqual([row.split(" ", 2)[1] for row in found], ["#1", "#5", "#8"], found)
        self.assertIn("permission and safety files", found[0])
        self.assertIn("docs/decisions/2026-10-07-x.md (changed)", found[1])
        self.assertIn("the designer's area", found[2])

    def test_added_and_deleted_files_keep_their_kind(self) -> None:
        files = [{"path": "docs/decisions/a.md", "changeType": "ADDED"}, {"path": "docs/decisions/b.md", "changeType": "DELETED"}]
        data = pr(9)
        data["files"] = files
        found = inbox.exceptions_of([data])
        self.assertIn("docs/decisions/a.md (new), docs/decisions/b.md (deleted)", found[0])


class MainTest(unittest.TestCase):
    def run_main(self, gh: Any, repos: list[str] | None = None) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(inbox, "GH", gh), redirect_stdout(out), redirect_stderr(err):
            rc = inbox.main(since="2026-10-06T00:00:00Z", repos=repos, now=1791331200.0)
        return rc, out.getvalue(), err.getvalue()

    def test_every_repo_two_calls_and_the_gate_only_in_the_game_repo(self) -> None:
        calls: list[tuple[str, ...]] = []

        def gh(*args: str) -> Any:
            calls.append(args)
            if args[0] == "pr":
                return [pr(1, files=(".claude/settings.json",))]
            return [comment(302, "2026-10-06T12:00:00Z", WAVE)]

        rc, out, _ = self.run_main(gh)
        self.assertEqual(rc, 0)
        self.assertEqual(len(calls), 6)
        self.assertEqual([c[3] for c in calls if c[0] == "pr"], list(inbox.REPOS))
        self.assertIn("repos/xperiaroco2/prime-game-art/issues/comments?since=2026-10-06T00:00:00Z", calls[-1][1])
        self.assertEqual(out.count("### Merges only the engineer makes"), 1)
        self.assertEqual(out.count("### For you (each thread's latest"), 3)
        self.assertIn("1. #302, 2026-10-06T12:00:00Z: https://github.com/o/r/issues/302#issuecomment-1", out)
        self.assertIn("   2. Answer PR #474's question 1", out)
        self.assertNotIn("\n\n\n", out)

    def test_a_failed_source_says_so_and_the_rest_is_printed(self) -> None:
        def gh(*args: str) -> Any:
            if args[0] == "api":
                raise Failure("gh api failed: HTTP 502")
            return []

        rc, out, err = self.run_main(gh, repos=["xperiaroco2/prime-game"])
        self.assertEqual(rc, 1)
        self.assertIn("Unavailable: gh api issues/comments: gh api failed: HTTP 502", out)
        self.assertIn("### Needs the engineer (open PRs)\n\nNothing.", out)
        self.assertIn("could not be read", out + err)

    def test_default_window_is_three_days(self) -> None:
        seen: list[str] = []

        def gh(*args: str) -> Any:
            seen.extend(a for a in args if "since=" in a)
            return []

        with mock.patch.object(inbox, "GH", gh), redirect_stdout(io.StringIO()):
            inbox.main(repos=["o/r"], now=1791331200.0)
        self.assertEqual(seen, [f"repos/o/r/issues/comments?since={inbox.iso(1791331200.0 - 72 * 3600)}&sort=created"
                                f"&direction=desc&per_page={inbox.COMMENT_LIMIT}"])  # fmt: skip


if __name__ == "__main__":
    unittest.main()
