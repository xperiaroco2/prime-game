"""`wave` (#277): small synthetic manager transcripts and workflow journals written here (never real ones) for the
pairing of a Workflow call with its result, resumes, running versus finished runs, stopped runs, human steps, non-ASCII
args, --args and the read-only rule."""

import hashlib
import io
import json
import os
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timedelta, timezone
from pathlib import Path, PurePosixPath, PureWindowsPath
from unittest import mock

from runner import cli, metrics, sessions, wave
from runner.common import Failure

T0 = datetime(2026, 10, 3, 8, 0, tzinfo=timezone.utc)
NOW = T0.timestamp() + 4 * 3600  # 12:00
SID = "5ef6e325-aaaa-bbbb-cccc-000000000001"
SINCE = "2026-10-03T08:00:00Z"


def at(minutes: float) -> str:
    return (T0 + timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def usage(inp: int = 0, write: int = 0, read: int = 0, out: int = 0) -> dict:
    return {"input_tokens": inp, "cache_creation_input_tokens": write, "cache_read_input_tokens": read,
            "output_tokens": out}  # fmt: skip


def assistant(minutes: float, mid: str, blocks: list[dict] | None = None, u: dict | None = None) -> dict:
    return {
        "type": "assistant",
        "timestamp": at(minutes),
        "message": {"id": mid, "model": "claude-opus-5-5", "usage": u or usage(inp=1),
                    "content": blocks or [{"type": "text", "text": "working"}]},
    }  # fmt: skip


def workflow(tool_id: str, **inp: object) -> dict:
    return {"type": "tool_use", "id": tool_id, "name": "Workflow", "input": inp}


def launched(minutes: float, tool_id: str, run_id: str | None, task_id: str = "", *, name: str = "issue-task",
             with_result: bool = True, text: str | None = None) -> dict:  # fmt: skip
    """The user record with a Workflow call's result; with_result False leaves out toolUseResult."""
    body = text if text is not None else f"Workflow launched in the background. Run ID: {run_id}"
    record = {
        "type": "user",
        "timestamp": at(minutes),
        "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tool_id, "content": body}]},
    }
    if with_result and run_id:
        record["toolUseResult"] = {"status": "async_launched", "taskId": task_id or f"w{run_id[3:9]}",
                                   "taskType": "local_workflow", "workflowName": name, "runId": run_id}  # fmt: skip
    return record


def note_text(tool_id: str, task_id: str, status: str = "completed", result: str = "{}", summary: str = "") -> str:
    # No backslash inside an f-string's braces: Python 3.11, the runner's minimum, cannot parse one.
    summary = summary or 'Dynamic workflow "issue-task" ' + status
    return (f"<task-notification>\n<task-id>{task_id}</task-id>\n<tool-use-id>{tool_id}</tool-use-id>\n"
            f"<output-file>C:\\tmp\\{task_id}.output</output-file>\n<status>{status}</status>\n"
            f"<summary>{summary}</summary>\n<result>{result}</result>\n"
            "</task-notification>")  # fmt: skip


def enqueue(minutes: float, text: str) -> dict:
    return {"type": "queue-operation", "operation": "enqueue", "timestamp": at(minutes), "content": text}


def user_note(minutes: float, text: str) -> dict:
    return {"type": "user", "timestamp": at(minutes), "message": {"role": "user", "content": text}}


def write_lines(path: Path, lines: list[object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join((x if isinstance(x, str) else json.dumps(x, ensure_ascii=False)) + "\n" for x in lines))


def journal(folder: Path, agents: list[tuple], last_write: float | None = None) -> None:
    """agents: (key, label, phase, result or None); a None result leaves the agent started."""
    entries: list[dict] = [{"type": "launched"}]
    for key, label, phase, result in agents:
        entries.append({"type": "started", "key": key, "agentId": f"a-{key}", "label": label, "phase": phase})
        if result is not None:
            entries.append({"type": "result", "key": key, "agentId": f"a-{key}", "result": result})
    write_lines(folder / "journal.jsonl", entries)
    if last_write is not None:
        os.utime(folder / "journal.jsonl", (last_write, last_write))


def issue_args(n: int, **more: object) -> dict:
    return {"n": n, "title": f"tooling: task {n}", "wt": f"D:/prime-game/.claude/worktrees/{n}",
            "branch": f"tooling/{n}-task", "base": "main", **more}  # fmt: skip


PUBLISHED = {"published": True, "handoff_posted": True, "pr_number": 9, "pr_url": "https://github.com/o/r/pull/9",
             "ci_green": True}  # fmt: skip


class Project:
    """A transcript folder in a temp directory; each test writes its own manager session."""

    def __init__(self, root: Path) -> None:
        self.dir = root / "projects" / "D--prime-game"
        self.dir.mkdir(parents=True)
        self.lines: list[object] = [{"type": "custom-title", "customTitle": "AI productivity трек: хвиля 2"}]

    def run_dir(self, run_id: str) -> Path:
        return self.dir / SID / "subagents" / "workflows" / run_id

    def add(self, *records: object) -> None:
        self.lines += records

    def launch(self, minutes: float, tool_id: str, run_id: str, args: object = None, *, notice: str | None = None,
               notice_at: float | None = None, result: str = "{}", **inp: object) -> None:  # fmt: skip
        """A Workflow call by name with its result, and (notice: a status) its notification as an enqueue and a user
        record."""
        given = {"name": "issue-task", **inp}
        if args is not None:
            given["args"] = args
        task = f"w{tool_id}"
        self.add(assistant(minutes, f"msg-{tool_id}", [workflow(tool_id, **given)]),
                 launched(minutes, tool_id, run_id, task, name=str(given.get("name") or "inline")))
        if notice:
            t = notice_at if notice_at is not None else minutes + 30
            self.add(enqueue(t, note_text(tool_id, task, notice, result)),
                     user_note(t + 1, note_text(tool_id, task, notice, result)))  # fmt: skip

    def write(self) -> Path:
        path = self.dir / f"{SID}.jsonl"
        write_lines(path, self.lines)
        return path

    def session(self) -> wave.Session:
        return wave.read_session(self.write(), SID)

    def body(self, since: str = SINCE, now: float = NOW) -> str:
        s = self.session()
        return wave.render(wave.Wave(s, wave.build_runs(s), metrics.parse_time(since), now))


MAIN = "D:/prime-game"


def sha(n: int) -> str:
    return hashlib.sha1(str(n).encode()).hexdigest()


def merged_pr(n: int, head: str, merged_at: str, *, base: str = "main", title: str = "", issues: list[int] = (),
              oid: str = "", updated_at: str = "") -> dict:  # fmt: skip
    """One row of `gh pr list --state merged --json` as GitHub returns it."""
    refs = [{"id": f"I_{i}", "number": i, "url": f"https://github.com/o/r/issues/{i}"} for i in issues]
    return {"number": n, "title": title or f"title {n}", "headRefName": head, "baseRefName": base,
            "mergedAt": merged_at[:19] + "Z", "mergeCommit": {"oid": sha(n)}, "closingIssuesReferences": refs,
            "headRefOid": oid or sha(n + 1000), "updatedAt": (updated_at or merged_at)[:19] + "Z"}  # fmt: skip


# merge-check's printed output (merge.check), clean and flagged, in its real shape.
CLEAN_CHECK = """merge-check
  ok    fetched origin
  ok    3 open PRs: main (3)

### main (origin/main at c1dbd37293): #315, #316, #317

| check | textual | semantic |
|---|---|---|
| #315 onto main | clean | clean |

merge-check: clean (0 textual conflicts and 0 overlaps in 6 checks)"""
FLAGGED_CHECK = """merge-check
  ok    fetched origin
  ok    2 open PRs: main (2)

### main (origin/main at c1dbd37293): #316, #317

| check | textual | semantic |
|---|---|---|
| #316 onto main | clean | clean |
| #316 + #317 | conflict: CLAUDE.md | overlap: wave.main |

#316 + #317:
- wave.main (tools/runner/wave.py:700 changed; used at tools/runner/cli.py:398)

merge-check: 1 textual conflicts and 1 overlaps in 3 checks. Order the merges so the side that removes or changes a \
symbol goes first and the other is rebased on it, or run merge-check --trial <pr>... to see whether verify stays green.
Across bases: name the pair on both tracks' plan issues."""


def open_pr(n: int, head: str, *, base: str = "main", issues: list[int] = (), rollup: list[dict] = (),
            draft: bool = False, state: str = "CLEAN") -> dict:  # fmt: skip
    refs = [{"number": i} for i in issues]
    return {"number": n, "title": f"title {n}", "headRefName": head, "baseRefName": base, "isDraft": draft,
            "statusCheckRollup": list(rollup), "mergeStateStatus": state, "closingIssuesReferences": refs}  # fmt: skip


class FakeSources(wave.Sources):
    """Everything wave reads beyond the transcripts, from the test: gh's JSON per query, merge-check's printed output
    and exit, `git worktree list --porcelain`, the live sessions per worktree folder name and the open issues."""

    def __init__(self, merged: list[dict] | None = None, open_prs: list[dict] | None = None, check_out: str = "",
                 rc: int = 0, porcelain: str = "", alive: dict[str, list] | None = None,
                 open_issues: list[int] | None = None, fail: dict[str, Exception] | None = None) -> None:  # fmt: skip
        self.merged, self.open_prs, self.check_out, self.rc = merged or [], open_prs or [], check_out, rc
        self.porcelain, self.alive, self.open_issues = porcelain, alive or {}, open_issues or []
        self.fail = fail or {}
        self.gh_calls: list[tuple[str, ...]] = []
        self.checks: list[tuple[list[int], str]] = []

    def raise_for(self, what: str) -> None:
        if what in self.fail:
            raise self.fail[what]

    def gh_json(self, *args: str) -> object:
        self.gh_calls.append(args)
        if args[:2] == ("pr", "list") and "merged" in args:
            self.raise_for("merged")
            return self.merged
        if args[:2] == ("pr", "list"):
            self.raise_for("open")
            return self.open_prs
        if args[:2] == ("issue", "list"):
            self.raise_for("issues")
            return [{"number": n} for n in self.open_issues]
        raise AssertionError(f"unexpected gh call {args}")

    def check(self, numbers: list[int], base: str) -> int:
        self.checks.append((numbers, base))
        if self.check_out:
            print(self.check_out)
        self.raise_for("check")
        return self.rc

    def worktree_list(self, main: Path) -> str:
        self.raise_for("worktrees")
        return self.porcelain

    def alive_in(self, path: Path) -> list:
        return self.alive.get(path.name, [])

    def history(self, main: Path) -> list[Path]:
        return []

    def main_checkout(self) -> Path:
        return Path(MAIN)


class WaveTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.p = Project(self.root)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def main(self, **kw: object) -> tuple[int, str, str]:
        """wave.main on this test's transcript folder; GitHub, merge-check, git and the sessions are FakeSources."""
        self.p.write()
        out, err = io.StringIO(), io.StringIO()
        kw.setdefault("sources", FakeSources())
        with redirect_stdout(out), redirect_stderr(err):
            rc = wave.main(session=kw.pop("session", SID), dirs=[self.p.dir], now=NOW, **kw)
        return rc, out.getvalue(), err.getvalue()

    def runs(self) -> dict[str, wave.Run]:
        return {r.run_id: r for r in wave.build_runs(self.p.session())}

    def row(self, body: str, needle: str) -> str:
        return next(line for line in body.splitlines() if line.startswith("|") and needle in line)

    def test_launch_pairs_with_its_result_by_tool_use_id(self) -> None:
        self.p.add(
            assistant(0, "msg-1", [workflow("t1", name="issue-task", args={"n": 5}),
                                   workflow("t2", scriptPath="D:/prime-game/.claude/workflows/issue-task.js",
                                            args={"n": 6})]),
            launched(1, "t2", "wf_b"),
            {"type": "user", "timestamp": at(1), "message": {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": "bash-1", "content": "Run ID: wf_zzz"}]}},
            launched(2, "t1", "wf_a"),
        )  # fmt: skip
        launches = {x.tool_use_id: x for x in self.p.session().launches}
        self.assertEqual((launches["t1"].run_id, launches["t1"].args), ("wf_a", {"n": 5}))
        self.assertEqual((launches["t2"].run_id, launches["t2"].args), ("wf_b", {"n": 6}))
        self.assertEqual([launches["t1"].name, launches["t2"].name], ["issue-task", "issue-task"])
        self.assertTrue(launches["t1"].passed_args)

    def test_run_id_from_the_text_when_tool_use_result_is_missing(self) -> None:
        self.p.add(assistant(0, "m", [workflow("t1", name="issue-task", args='{"n": 3}')]),
                   launched(0, "t1", "wf_c", with_result=False))  # fmt: skip
        (launch,) = self.p.session().launches
        self.assertEqual(launch.run_id, "wf_c")
        self.assertEqual(launch.args, {"n": 3}, "a JSON string of args is parsed")
        self.assertEqual(launch.run_dir, self.p.run_dir("wf_c"))

    def test_a_resume_keeps_the_original_args(self) -> None:
        args = issue_args(7, notes="first")
        self.p.launch(0, "t1", "wf_r", args, notice="failed", notice_at=20)
        self.p.launch(30, "t2", "wf_r", None, notice="completed", notice_at=60, resumeFromRunId="wf_r")
        journal(self.p.run_dir("wf_r"), [("k", "publish:#7", "Publish", PUBLISHED)])
        runs = self.runs()
        self.assertEqual(list(runs), ["wf_r"])
        run = runs["wf_r"]
        self.assertEqual(len(run.launches), 2)
        self.assertEqual(run.args, args)
        self.assertFalse(run.latest.passed_args)
        self.assertEqual(run.status, "completed")
        rc, out, err = self.main(args_issue=7)
        self.assertEqual((rc, json.loads(out)), (0, args))
        self.assertIn("inherited from wf_r", err)

    def test_a_resume_with_a_new_run_id(self) -> None:
        self.p.launch(0, "t1", "wf_r", issue_args(7), notice="failed", notice_at=20)
        self.p.launch(30, "t2", "wf_r2", None, resumeFromRunId="wf_r")
        journal(self.p.run_dir("wf_r2"), [("k", "implement:#7", "Implement", None)])
        runs = self.runs()
        self.assertEqual(runs["wf_r"].resumed_as, "wf_r2")
        self.assertEqual(runs["wf_r2"].args, issue_args(7))
        body = self.p.body()
        self.assertIn("resumed as wf_r2", self.row(body, "wf_r "))
        self.assertNotIn("Finished runs that need a resume", body, "its resume already runs")
        self.assertIn("wf_r2;", body.split("## Handover data")[1])
        _, out, err = self.main(args_issue=7)
        self.assertEqual(json.loads(out), issue_args(7))
        self.assertIn("run wf_r2", err)

    def test_a_fresh_relaunch_replaces_a_stopped_run(self) -> None:
        self.p.launch(0, "t1", "wf_a", issue_args(5), notice="completed", notice_at=20)
        journal(self.p.run_dir("wf_a"), [("k1", "implement:#5", "Implement", {"verify_green": False})])
        self.p.launch(30, "t2", "wf_b", issue_args(5, notes="again"))
        journal(self.p.run_dir("wf_b"), [("k2", "implement:#5", "Implement", None)])
        runs = self.runs()
        self.assertEqual(runs["wf_a"].relaunched_as, "wf_b")
        self.assertFalse(runs["wf_b"].finished)
        body = self.p.body()
        self.assertIn("relaunched as wf_b", self.row(body, "wf_a"))
        self.assertIn("wf_b", self.row(body.split("## Running")[1], "wf_b"))
        handover = body.split("## Handover data")[1]
        self.assertNotIn("Finished runs that need a resume", handover, "its fresh relaunch already runs")
        self.assertNotIn("wf_a;", handover)
        self.assertIn(f"wf_b; session {SID} ", handover, "the owning session's full id")

    def test_a_relaunch_of_another_workflow_replaces_nothing(self) -> None:
        self.p.launch(0, "t1", "wf_a", issue_args(5), notice="completed", notice_at=20)
        journal(self.p.run_dir("wf_a"), [("k1", "implement:#5", "Implement", {"verify_green": False})])
        self.p.launch(30, "t2", "wf_p", {"n": 5, "pr": 12, "why": "x"}, name="pr-rebase")
        self.assertIsNone(self.runs()["wf_a"].relaunched_as, "a pr-rebase of #5 is not a relaunch of its issue-task")

    def test_a_resume_of_another_sessions_run_points_at_its_args(self) -> None:
        old_sid = "40774c17-aaaa-bbbb-cccc-000000000002"
        old_dir = self.p.dir / old_sid / "subagents" / "workflows" / "wf_old"
        journal(old_dir, [("k1", "implement:#8", "Implement", None)])
        self.p.launch(0, "t1", "wf_old", None, resumeFromRunId="wf_old")
        self.p.lines[-1]["toolUseResult"]["transcriptDir"] = str(old_dir)
        body = self.p.body()
        handover = body.split("## Handover data")[1].split("---")[0]
        self.assertNotIn("no args were passed", handover)
        self.assertIn("a resume of wf_old", handover)
        self.assertIn(f"tools\\run.cmd wave --args 8 --session {old_sid}", handover)

    def test_args_skip_a_rejected_launch(self) -> None:
        self.p.launch(0, "t1", "wf_a", issue_args(5))
        self.p.add(assistant(5, "m-bad", [workflow("t2", name="issue-task", args={"n": 5, "bad": True})]),
                   launched(5, "t2", None, text="Error: the input does not match the schema"))  # fmt: skip
        _, out, err = self.main(args_issue=5)
        self.assertEqual(json.loads(out), issue_args(5), "the launch that ran, not the rejected one after it")
        self.assertIn("run wf_a", err)

    def test_running_versus_finished(self) -> None:
        self.p.launch(210, "t1", "wf_open", issue_args(6))  # 11:30, 30 minutes before NOW
        journal(self.p.run_dir("wf_open"), [("k1", "implement:#6", "Implement", {"verify_green": True}),
                                            ("k2", "review:code:#6", "Review", None)], last_write=NOW - 300)
        self.p.launch(10, "t2", "wf_done", issue_args(9), notice="completed")
        journal(self.p.run_dir("wf_done"), [("k3", "publish:#9", "Publish", PUBLISHED)])
        self.p.launch(20, "t3", "wf_quiet", issue_args(8))
        journal(self.p.run_dir("wf_quiet"), [("k4", "publish:#8", "Publish", PUBLISHED)])
        runs = self.runs()
        self.assertFalse(runs["wf_open"].finished)
        self.assertEqual(runs["wf_open"].working, [("review:code:#6", "Review")])
        self.assertEqual(runs["wf_done"].status, "completed")
        self.assertEqual(runs["wf_quiet"].status, "finished (no notification)")
        body = self.p.body()
        running = body.split("## Running")[1].split("## Handover")[0]
        row = self.row(running, "wf_open")
        for want in ("#6", "tooling: task 6", "D:/prime-game/.claude/worktrees/6", "tooling/6-task", "| main |",
                     "review:code:#6 (Review)", "| 30 | 5 |"):  # fmt: skip
            self.assertIn(want, row)
        finished = body.split("## Running")[0]
        self.assertIn("https://github.com/o/r/pull/9", self.row(finished, "wf_done"))
        self.assertIn("wf_quiet", finished)
        self.assertNotIn("wf_open", finished)

    def test_a_pr_rebase_in_review_is_running_until_its_end(self) -> None:
        self.p.launch(0, "t1", "wf_pr", {"n": 5, "pr": 12, "why": "x"}, name="pr-rebase")
        green = {"up_to_date": True, "verify_green": True, "published": True}
        journal(self.p.run_dir("wf_pr"), [("k1", "rebase:#12", "Rebase", green),
                                          ("k2", "review:code:#12", "Review", None)])  # fmt: skip
        self.assertFalse(self.runs()["wf_pr"].finished, "reviewers still run after a green rebase")
        journal(self.p.run_dir("wf_pr"), [("k1", "rebase:#12", "Rebase", green),
                                          ("k2", "review:code:#12", "Review", {"findings": [{"severity": "major"}]})])
        self.assertFalse(self.runs()["wf_pr"].finished, "a major finding starts a fix agent")
        journal(self.p.run_dir("wf_pr"), [("k1", "rebase:#12", "Rebase", green),
                                          ("k2", "review:code:#12", "Review", {"findings": [{"severity": "minor"}]})])
        run = self.runs()["wf_pr"]
        self.assertTrue(run.finished, "no blocker or major: the script ends after the review")
        self.assertIn("| #12 |", self.row(self.p.body(), "wf_pr"), "the PR from args.pr")

    def test_finished_fields_come_from_the_journal_not_the_notification(self) -> None:
        cut = '{"n":5,"pub":{"published":true,"pr_url":"https://github.com/o/r/pull/999","ci_green":false,"not_fi'
        self.p.launch(0, "t1", "wf_x", issue_args(5), notice="completed", result=cut)
        pub = {**PUBLISHED, "not_fixed": ["a", "b"], "needs_engineer": ["c"]}
        journal(self.p.run_dir("wf_x"), [("k1", "implement:#5", "Implement", {"verify_green": True}),
                                         ("k2", "publish:#5", "Publish", pub)])  # fmt: skip
        body = self.p.body()
        self.assertIn("| https://github.com/o/r/pull/9 | green | yes | 2 | 1 |", self.row(body, "wf_x"))
        self.assertNotIn("999", body)

    def test_a_stopped_run_is_flagged(self) -> None:
        red = [("k1", "implement:#1", "Implement", {"verify_green": False})]
        cases = {
            "wf_red": (red, "completed", "{}"),
            "wf_unpub": ([("k1", "publish:#2", "Publish", {"published": False})], "completed", "{}"),
            "wf_reb": ([("k1", "rebase:#3", "Rebase", {"verify_green": True, "published": False})], "completed", "{}"),
            "wf_said": ([("k1", "publish:#4", "Publish", PUBLISHED)], "completed",
                        '{"n":4,"stopped":"tools\\\\run.cmd mutants exited 2'),
            "wf_mut": ([("k1", "publish:#6", "Publish", {"published": False, "stopped_by_mutants": True})], "completed",
                       "{}"),
            "wf_ok": ([("k1", "publish:#5", "Publish", PUBLISHED)], "completed", "{}"),
        }  # fmt: skip
        for i, (run_id, (agents, status, result)) in enumerate(cases.items()):
            self.p.launch(i, f"t{i}", run_id, {"n": i + 1}, notice=status, result=result)
            journal(self.p.run_dir(run_id), agents)
        # A red implementer with no notification yet: issue-task stops there, so it is finished too.
        self.p.launch(9, "t9", "wf_red_quiet", {"n": 9})
        journal(self.p.run_dir("wf_red_quiet"), red)
        body = self.p.body()
        for run_id in ("wf_red", "wf_unpub", "wf_reb", "wf_said", "wf_mut", "wf_red_quiet"):
            self.assertIn(wave.RELAUNCH, self.row(body, run_id), run_id)
        self.assertNotIn(wave.RELAUNCH, self.row(body, "wf_ok"))
        self.assertIn("verify red after the implementer", self.row(body, "wf_red_quiet"))
        self.assertIn("mutants exited 2", self.row(body, "wf_mut"))
        self.assertIn("run.cmd mutants exited 2", self.row(body, "wf_said"))
        handover = body.split("## Handover data")[1]
        self.assertIn("### Finished runs that need a resume or a fresh relaunch", handover)
        self.assertIn("wf_red;", handover)
        self.assertNotIn("wf_ok;", handover)

    def test_human_steps_in_both_shapes(self) -> None:
        steps = [
            {"why": "Remove the worktree", "command": "cd D:\\prime-game; tools\\run.cmd worktree-done 5"},
            {"why": "Drag the PNG into the PR", "command": ""},
            "Review and merge PR #9",
            {"why": "A fenced one", "command": "echo ```"},
        ]
        self.p.launch(0, "t1", "wf_pr", {"n": 5, "pr": 9}, name="pr-rebase", notice="completed")
        journal(self.p.run_dir("wf_pr"), [
            ("k1", "rebase:#9", "Rebase", {"verify_green": True, "published": True, "human_steps": steps[:2]}),
            ("k2", "review:code:#9", "Review", {"findings": [{"severity": "major"}]}),
            ("k3", "fix:#9", "Fix", {"fixed": ["x"], "verify_green": True, "published": True, "ci_green": True,
                                     "human_steps": steps[1:]}),
        ])  # fmt: skip
        body = self.p.body()
        self.assertIn("**#5 human steps** (wf_pr)", body)
        self.assertIn("- Remove the worktree\n\n```powershell\ncd D:\\prime-game; tools\\run.cmd worktree-done 5\n```",
                      body)  # fmt: skip
        self.assertIn("- Drag the PNG into the PR\n\n- Review", body, "no fence for an empty command")
        self.assertEqual(body.count("Drag the PNG"), 1, "a step both agents returned is listed once")
        self.assertIn("- Review and merge PR #9", body)
        self.assertIn("````powershell\necho ```\n````", body)

    def test_non_ascii_args_survive_byte_for_byte(self) -> None:
        args = issue_args(4, notes="§7 Кирилиця «лапки»")
        self.p.launch(200, "t1", "wf_u", args)
        journal(self.p.run_dir("wf_u"), [("k1", "implement:#4", "Implement", None)])
        target = self.root / "out" / "w.md"
        self.main(since=SINCE, out=str(target))
        raw = target.read_bytes()
        self.assertIn("§7 Кирилиця «лапки»".encode("utf-8"), raw)
        self.assertIn("AI productivity трек: хвиля 2".encode("utf-8"), raw)
        self.assertNotIn(b"\r\n", raw)
        text = raw.decode("utf-8")
        block = text.split("```json\n")[1].split("\n```")[0]
        self.assertEqual(json.loads(block), args)
        self.assertEqual(block, json.dumps(args, indent=1, ensure_ascii=False))
        _, out, _ = self.main(args_issue=4)
        self.assertEqual(out, json.dumps(args, indent=1, ensure_ascii=False) + "\n")

    def test_args_for_a_missing_issue(self) -> None:
        self.p.launch(0, "t1", "wf_a", issue_args(5))
        self.p.add(assistant(1, "m-s", [workflow("t2", script="export default 1")]),
                   launched(1, "t2", "wf_s", name="scouting"))  # fmt: skip
        with self.assertRaises(Failure) as caught:
            self.main(args_issue=99)
        self.assertIn("#99", str(caught.exception))
        self.assertIn(SID, str(caught.exception))
        self.assertIn("launched: #5", str(caught.exception))
        with mock.patch.object(wave.agents_check, "project_dirs", return_value=[self.p.dir]), \
                mock.patch.object(wave.metrics, "main_checkout", return_value=self.root), \
                redirect_stdout(io.StringIO()):  # fmt: skip
            self.assertEqual(cli.main(["wave", "--args", "99", "--session", SID]), 1)
            self.assertEqual(cli.main(["wave", "--args", "5", "--session", SID[:8]]), 0)

    def test_args_by_workflow(self) -> None:
        self.p.launch(0, "t1", "wf_a", issue_args(5))
        self.p.launch(60, "t2", "wf_b", {"n": 5, "pr": 9, "why": "conflict"}, name="pr-rebase")
        _, out, err = self.main(args_issue=5)
        self.assertEqual(json.loads(out)["pr"], 9)
        self.assertIn("pr-rebase", err)
        _, out, _ = self.main(args_issue=5, workflow="issue-task")
        self.assertEqual(json.loads(out), issue_args(5))

    def snapshot(self) -> dict[str, str]:
        return {str(p.relative_to(self.root)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.root.rglob("*") if p.is_file()}  # fmt: skip

    def test_writes_only_the_out_file(self) -> None:
        self.p.launch(0, "t1", "wf_a", issue_args(5), notice="completed")
        journal(self.p.run_dir("wf_a"), [("k1", "publish:#5", "Publish", PUBLISHED)])
        self.p.write()
        before = self.snapshot()
        target = self.root / "w.md"
        boom = mock.Mock(side_effect=AssertionError("no process may start"))
        with mock.patch.object(subprocess, "run", boom), mock.patch.object(subprocess, "Popen", boom), \
                mock.patch.object(wave, "ensure_out", boom):  # fmt: skip
            rc, out, _ = self.main(since=SINCE, out=str(target))
            self.assertEqual(rc, 0)
            self.assertIn(str(target), out)
            after = self.snapshot()
            self.assertEqual(set(after) - set(before), {"w.md"})
            self.assertEqual({k: after[k] for k in before}, before)
            # --args without --out writes nothing; with --out only that file.
            self.main(args_issue=5)
            self.assertEqual(self.snapshot(), after)
            self.main(args_issue=5, out=str(self.root / "a.json"))
            self.assertEqual(set(self.snapshot()) - set(after), {"a.json"})
        self.assertEqual(wave.default_out(SID), wave.OUT / "wave" / "wave-5ef6e325.md")

    def test_since_leaves_out_runs_finished_before_it(self) -> None:
        self.p.launch(-120, "t1", "wf_early", issue_args(1), notice="completed", notice_at=-60)  # 07:00
        journal(self.p.run_dir("wf_early"), [("k1", "publish:#1", "Publish", PUBLISHED)])
        self.p.launch(-120, "t2", "wf_long", issue_args(2))  # 06:00, still running
        journal(self.p.run_dir("wf_long"), [("k2", "implement:#2", "Implement", None)])
        body = self.p.body()
        finished = body.split("## Running")[0]
        self.assertNotIn("wf_early", finished)
        self.assertIn("1 run finished before 2026-10-03T08:00:00Z, left out.", finished)
        self.assertIn("wf_long", body.split("## Running")[1])

    def test_the_footer(self) -> None:
        calls = [(f"m{i}", usage(inp=1000 * i, write=10000, read=10000 * i, out=500 * i)) for i in range(45)]
        for i, (mid, u) in enumerate(calls):
            self.p.add(assistant(i, mid, u=u))
        self.p.add(assistant(44.5, "m44", u=calls[44][1]))  # the same message on a second line
        self.p.add({"type": "assistant", "timestamp": at(46), "message": {"model": "<synthetic>", "usage": usage(9)}})
        path = self.p.write()
        s = wave.read_session(path, SID)
        self.assertEqual(len(s.calls), 45)
        agent = metrics.read_agent(path)
        self.assertEqual((len(s.calls), s.last_ctx), (agent["api_calls"], agent["last_ctx"]))

        def mean(chosen: list) -> float:
            priced = [{**u, "cache_write_1h": 0, "model": "claude-opus-5-5"} for _, u in chosen]
            return sum(sum(metrics.usd_of(u).values()) for u in priced) / len(priced)

        body = self.p.body(now=metrics.parse_time("2026-10-03T13:00:00Z"))
        footer = body.split("---")[-1]
        self.assertIn(f'Session {SID} "AI productivity трек: хвиля 2": 5.0 h old', footer)
        self.assertIn(f"the last call's context {metrics.fmt_tok(sum(calls[44][1].values()))}", footer)
        self.assertIn(f"first 20 {metrics.fmt_usd(mean(calls[:20]))}, last 20 {metrics.fmt_usd(mean(calls[-20:]))} "
                      "(45 calls)", footer)  # fmt: skip
        self.assertNotEqual(metrics.fmt_usd(mean(calls[:20])), metrics.fmt_usd(mean(calls[-20:])))

    def test_session_default_and_prefix(self) -> None:
        self.p.write()
        other = self.p.dir / "5ef6e325-ffff.jsonl"
        write_lines(other, [])
        with mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": SID}):
            self.assertEqual(wave.find_transcript(None, [self.p.dir])[1], SID)
        self.assertEqual(wave.find_transcript("5ef6e325-aaaa", [self.p.dir])[1], SID)
        with self.assertRaises(Failure) as caught:
            wave.find_transcript("5ef6e325", [self.p.dir])
        self.assertIn("5ef6e325-ffff", str(caught.exception))
        self.assertIn(SID, str(caught.exception))
        with self.assertRaises(Failure) as caught:
            wave.find_transcript("0000", [self.p.dir])
        self.assertIn(str(self.p.dir), str(caught.exception))
        with mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": ""}), self.assertRaises(Failure) as caught:
            wave.find_transcript(None, [self.p.dir])
        self.assertIn("--session", str(caught.exception))

    def test_a_non_issue_workflow_is_listed_with_its_name(self) -> None:
        self.p.add(assistant(0, "m-s", [workflow("t1", script="export default 1")]),
                   launched(0, "t1", "wf_s", name="scouting"))  # fmt: skip
        journal(self.p.run_dir("wf_s"), [("k1", "data", "Scout", {"summary": "#12 is fine"})])
        self.p.add(enqueue(30, note_text("t1", "wwf_s", summary='Dynamic workflow "scouting" completed')))
        body = self.p.body()
        self.assertIn("| — | scouting | wf_s | completed |", self.row(body, "wf_s"))
        self.assertNotIn("<details>", body)

    def test_unknown_records_are_skipped_and_counted(self) -> None:
        self.p.add("{not json", assistant(0, "m1", [workflow("t1", name="issue-task", args={"n": 1})]),
                   assistant(1, "m2", [{"type": "tool_use", "id": "bash-1", "name": "Bash", "input": {}}]),
                   {"type": "brand-new-record", "timestamp": at(2)},
                   enqueue(3, note_text("t-unknown", "wzzz")),
                   enqueue(4, note_text("bash-1", "b1", summary="Background command finished")),
                   enqueue(5, note_text("toolu-of-a-subagent", "b2", summary="Background command done")))  # fmt: skip
        footer = self.p.body().split("---")[-1]
        self.assertIn("Skipped: not JSON 1, Workflow call without a result 1, workflow notification for no known "
                      "launch 1.", footer)  # fmt: skip

    def test_a_table_cell_keeps_its_row(self) -> None:
        self.p.launch(0, "t1", "wf_a", issue_args(5, title="a | b"))
        journal(self.p.run_dir("wf_a"), [("k1", "implement:#5", "Implement", None)])
        self.p.launch(1, "t2", "wf_f", issue_args(6), notice="failed")
        self.p.lines[-2] = enqueue(31, note_text("t2", "wt2", "failed", summary="threw:\nresume this | run"))
        body = self.p.body()
        self.assertIn("a \\| b", self.row(body, "wf_a"))
        self.assertIn("failed: threw: resume this \\| run", self.row(body, "wf_f"))

    def test_the_command_line(self) -> None:
        args = cli.build_parser().parse_args(["wave", "--since", "2026-10-03T14:00:00Z", "--session", "abc",
                                              "--out", "x.md"])  # fmt: skip
        self.assertEqual((args.since, args.session, args.out, args.args), ("2026-10-03T14:00:00Z", "abc", "x.md", None))
        self.assertEqual((args.base, args.plan, args.title, args.notes, args.stage_since, args.merge_check),
                         (None, None, None, None, None, True))  # fmt: skip
        self.assertEqual(cli.build_parser().parse_args(["wave", "--args", "231"]).args, 231)
        args = cli.build_parser().parse_args(["wave", "--since", "T", "--base", "release/m5", "--plan", "302", "--title",
                                              "Wave 3", "--notes", "n.md", "--stage-since", "S",
                                              "--no-merge-check"])  # fmt: skip
        self.assertEqual((args.base, args.plan, args.title, args.notes, args.stage_since, args.merge_check),
                         ("release/m5", 302, "Wave 3", "n.md", "S", False))  # fmt: skip
        for bad in (["wave", "--since", "x", "--args", "1"], ["wave"], ["wave", "--since", "x", "--plan", "p"]):
            with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
                cli.build_parser().parse_args(bad)

    def test_since_flags_refused_with_args(self) -> None:
        self.p.launch(0, "t1", "wf_a", issue_args(5))
        self.p.write()
        for flag in (["--base", "main"], ["--plan", "302"], ["--title", "W"], ["--notes", "n.md"],
                     ["--stage-since", SINCE], ["--no-merge-check"]):  # fmt: skip
            out = io.StringIO()
            with mock.patch.object(wave.agents_check, "project_dirs", return_value=[self.p.dir]), \
                    mock.patch.object(wave.metrics, "main_checkout", return_value=self.root), \
                    redirect_stdout(out):  # fmt: skip
                self.assertEqual(cli.main(["wave", "--args", "5", "--session", SID, *flag]), 1, flag)
            self.assertIn(f"{flag[0]} goes with --since", out.getvalue())
        with self.assertRaises(Failure) as caught:
            self.main(since=SINCE, stage_since="yesterday")
        self.assertIn("yesterday", str(caught.exception))

    def test_args_reads_no_github(self) -> None:
        self.p.launch(0, "t1", "wf_a", issue_args(5))
        boom = mock.Mock(side_effect=AssertionError("--args reads no source"))
        with mock.patch.multiple(wave.Sources, gh_json=boom, check=boom, worktree_list=boom, alive_in=boom,
                                 history=boom, main_checkout=boom):  # fmt: skip
            rc, out, _ = self.main(args_issue=5, sources=wave.Sources())
        self.assertEqual((rc, json.loads(out)), (0, issue_args(5)))

    def section(self, body: str, heading: str) -> str:
        """The text of one '## ' section of a body, its heading line included."""
        part = body.split(f"\n## {heading}")[1]
        return f"## {heading}" + part.split("\n## ")[0].split("\n---\n")[0]

    def test_merged_rows_from_gh_json(self) -> None:
        merged = [
            merged_pr(311, "tooling/305-keep-warm", at(60), title="feat: a | b"),
            merged_pr(300, "tooling/299-early", at(-30)),
            merged_pr(320, "release/m5", at(120)),
            merged_pr(310, "tooling/303-waits", at(30), issues=[283, 290]),
            merged_pr(321, "core/250-items", at(90), base="release/m5"),
        ]
        src = FakeSources(merged=merged)
        target = self.root / "w.md"
        self.main(since=SINCE, out=str(target), sources=src, merge_check=False)
        self.assertIn(("pr", "list", "--state", "merged", "--search", "sort:updated-desc", "--limit",
                       str(wave.MERGED_LIMIT), "--json", wave.MERGED_FIELDS), src.gh_calls)  # fmt: skip
        self.assertIn("updatedAt", wave.MERGED_FIELDS.split(","))
        body = target.read_text(encoding="utf-8")
        part = self.section(body, "Merged into main since")
        rows = [line for line in part.splitlines() if line.startswith("| #")]
        self.assertEqual([r.split(" | ")[0] for r in rows], ["| #310", "| #311", "| #320"], "by mergedAt, from since")
        self.assertEqual(rows[0], f"| #310 | title 310 | tooling/303-waits | {at(30)[:19]}Z | {sha(310)[:10]} | "
                         "#283, #290 |", "the closing issues")  # fmt: skip
        self.assertIn("| #311 | feat: a \\| b | tooling/305-keep-warm |", rows[1])
        self.assertTrue(rows[1].endswith(" | #305 |"), "no closing issue: the issue from the branch")
        self.assertTrue(rows[2].endswith(" | — |"), "release/m5 names no issue")
        self.main(since=SINCE, out=str(target), sources=FakeSources(merged=merged), merge_check=False,
                  base="release/m5")  # fmt: skip
        part = self.section(target.read_text(encoding="utf-8"), "Merged into release/m5 since")
        self.assertEqual([line.split(" | ")[0] for line in part.splitlines() if line.startswith("| #")], ["| #321"])
        self.main(since="2026-10-03T13:00:00Z", out=str(target), sources=FakeSources(merged=merged),
                  merge_check=False)  # fmt: skip
        self.assertIn("None.", self.section(target.read_text(encoding="utf-8"), "Merged into main since"))

    def test_merged_note_at_the_limit(self) -> None:
        """gh lists the most recently updated merged PRs; at its limit, a PR merged before the oldest update may be
        missing. Judged by gh's raw row count (a row without mergedAt counts too), not by the parsed rows."""
        target = self.root / "w.md"
        no_merge_time = {**merged_pr(312, "tooling/12-x", at(25)), "mergedAt": None}

        def note(rows: list[dict]) -> str:
            self.main(since=SINCE, out=str(target), sources=FakeSources(merged=rows), merge_check=False)
            part = self.section(target.read_text(encoding="utf-8"), "Merged into main since")
            return "\n".join(line for line in part.splitlines() if line.startswith("gh returned"))

        with mock.patch.object(wave, "MERGED_LIMIT", 3):
            cut = [merged_pr(310, "tooling/10-x", at(60)), no_merge_time,
                   merged_pr(311, "tooling/11-x", at(20), updated_at=at(30))]  # fmt: skip
            self.assertEqual(note(cut), f"gh returned its limit of 3 merged PRs, the most recently updated, back to an "
                             f"update at {at(25)[:19]}Z: a PR merged before then may be missing here and in "
                             "housekeeping.")  # fmt: skip
            whole = [merged_pr(310, "tooling/10-x", at(60)), merged_pr(311, "tooling/11-x", at(20)),
                     merged_pr(309, "tooling/9-x", at(-90), updated_at=at(-10))]  # fmt: skip
            self.assertEqual(note(whole), "", "the oldest update is before since: every PR merged since is listed")
            self.assertEqual(note(cut[:2]), "", "under the limit gh listed them all")

    def test_open_pr_ci_cell(self) -> None:
        def run_(name: str, status: str = "COMPLETED", conclusion: str = "SUCCESS") -> dict:
            return {"__typename": "CheckRun", "name": name, "status": status, "conclusion": conclusion}

        def ctx(name: str, state: str) -> dict:
            return {"__typename": "StatusContext", "context": name, "state": state}

        self.assertEqual(wave.ci_cell([]), "none")
        self.assertEqual(wave.ci_cell([run_("verify"), run_("lint", conclusion="NEUTRAL"),
                                       run_("docs", conclusion="SKIPPED"), ctx("ext", "SUCCESS")]), "green")
        self.assertEqual(wave.ci_cell([run_("verify", conclusion="FAILURE"), run_("lint")]), "red: verify")
        self.assertEqual(wave.ci_cell([run_("verify", status="IN_PROGRESS", conclusion=""),
                                       run_("lint", status="QUEUED", conclusion="")]), "pending: verify, lint")
        self.assertEqual(wave.ci_cell([ctx("ext", "PENDING")]), "pending: ext")
        self.assertEqual(wave.ci_cell([ctx("ext", "ERROR"), run_("verify", status="IN_PROGRESS", conclusion="")]),
                         "red: ext", "red beats pending")  # fmt: skip
        self.assertEqual(wave.ci_cell([run_("verify", conclusion="CANCELLED"), run_("verify", conclusion="FAILURE")]),
                         "red: verify", "a name once")  # fmt: skip
        prs = [
            open_pr(316, "tooling/300-autonomy", issues=[300], rollup=[run_("verify")], state="CLEAN"),
            open_pr(318, "tooling/301-child", base="tooling/300-autonomy", draft=True, state="BLOCKED"),
            open_pr(317, "net/284-bots", rollup=[run_("verify", status="IN_PROGRESS", conclusion="")],
                    state="UNSTABLE"),
            open_pr(330, "core/250-items", base="release/m5"),
        ]  # fmt: skip
        src = FakeSources(open_prs=prs)
        target = self.root / "w.md"
        self.main(since=SINCE, out=str(target), sources=src, merge_check=False)
        self.assertIn(("pr", "list", "--state", "open", "--limit", "200", "--json", wave.OPEN_FIELDS), src.gh_calls)
        part = self.section(target.read_text(encoding="utf-8"), "Open PRs")
        rows = [line for line in part.splitlines() if line.startswith("| #")]
        self.assertEqual(rows, [
            "| #316 | title 316 | #300 | main | no | green | CLEAN |",
            "| #317 | title 317 | #284 | main | no | pending: verify | UNSTABLE |",
            "| #318 | title 318 | #301 | tooling/300-autonomy | yes | none | BLOCKED |",
        ], "into main and stacked on a PR into main; not into release/m5")  # fmt: skip
        self.main(since=SINCE, out=str(target), sources=FakeSources(), merge_check=False)
        self.assertIn("None.", self.section(target.read_text(encoding="utf-8"), "Open PRs"))
        failing = FakeSources(fail={"open": Failure("gh pr list failed: HTTP 502")})
        rc, out, _ = self.main(since=SINCE, out=str(target), sources=failing, merge_check=False)
        self.assertEqual(rc, 0, "a source that fails still writes the body")
        self.assertIn("Unavailable: gh pr list failed: HTTP 502", self.section(target.read_text(encoding="utf-8"),
                                                                                "Open PRs"))  # fmt: skip
        self.assertIn("warn  wave: open PRs unavailable: gh pr list failed: HTTP 502", out)

    def test_merge_check_capture_clean(self) -> None:
        src = FakeSources(check_out=CLEAN_CHECK, rc=0)
        target = self.root / "w.md"
        rc, out, _ = self.main(since=SINCE, out=str(target), sources=src)
        self.assertEqual((rc, src.checks), (0, [([], "main")]))
        self.assertNotIn("open PRs: main", out, "merge-check's own lines are captured, not printed")
        part = self.section(target.read_text(encoding="utf-8"), "Merge safety")
        self.assertEqual(part, "## Merge safety\n\n`merge-check --base main`: exit 0.\n\n"
                         "merge-check: clean (0 textual conflicts and 0 overlaps in 6 checks)\n")  # fmt: skip

        class RealCheck(FakeSources):
            check = wave.Sources.check

        with mock.patch.object(wave.merge, "fetch", lambda: wave.merge.ok("fetched origin")), \
                mock.patch.object(wave.merge, "open_prs", return_value=[]):  # fmt: skip
            self.main(since=SINCE, out=str(target), sources=RealCheck(), base="release/m5")
        part = self.section(target.read_text(encoding="utf-8"), "Merge safety")
        self.assertEqual(part, "## Merge safety\n\n`merge-check --base release/m5`: exit 0.\n\n"
                         "no open PRs to check into release/m5\n")  # fmt: skip

    def test_merge_check_capture_flagged(self) -> None:
        src = FakeSources(check_out=FLAGGED_CHECK, rc=1)
        target = self.root / "w.md"
        rc, _, _ = self.main(since=SINCE, out=str(target), sources=src)
        self.assertEqual(rc, 0, "a flagged merge-check is data in the body, not wave's exit code")
        part = self.section(target.read_text(encoding="utf-8"), "Merge safety")
        printed = FLAGGED_CHECK.split("\n\n", 1)[1]  # from '### main' on, as merge-check printed it
        self.assertTrue(printed.startswith("### main"))
        self.assertEqual(part, f"## Merge safety\n\n`merge-check --base main`: exit 1.\n\n{printed}\n")
        self.assertNotIn("fetched origin", part)
        failing = FakeSources(check_out="merge-check\n  ok    fetched origin\n  warn  origin/m9 is gone",
                              fail={"check": Failure("gh not found")})  # fmt: skip
        rc, out, _ = self.main(since=SINCE, out=str(target), sources=failing)
        self.assertEqual(rc, 0)
        part = self.section(target.read_text(encoding="utf-8"), "Merge safety")
        self.assertEqual(part, "## Merge safety\n\n`merge-check --base main`: exit 1.\n\nmerge-check failed: gh not found"
                         "\n\n  warn  origin/m9 is gone\n")  # fmt: skip
        self.assertIn("warn  wave: merge-check failed: gh not found", out)
        self.assertIn("## Handover data", target.read_text(encoding="utf-8"), "the rest of the body is written")
        skipped = FakeSources(check_out=CLEAN_CHECK)
        self.main(since=SINCE, out=str(target), sources=skipped, merge_check=False)
        self.assertEqual(skipped.checks, [])
        self.assertEqual(self.section(target.read_text(encoding="utf-8"), "Merge safety"),
                         "## Merge safety\n\nSkipped (--no-merge-check).\n")  # fmt: skip

    def test_cost_block(self) -> None:
        self.p.add(assistant(-30, "m-early", u=usage(inp=999, out=50)))  # 07:30, before --since
        self.p.launch(10, "t1", "wf_a", issue_args(5), notice="completed")
        journal(self.p.run_dir("wf_a"), [("k1", "implement:#5", "Implement", {"verify_green": True}),
                                         ("k2", "publish:#5", "Publish", PUBLISHED)])  # fmt: skip
        write_lines(self.p.run_dir("wf_a") / "agent-a-k1.jsonl",
                    [assistant(12, "a1", u=usage(inp=10, write=1000, read=5000, out=200))])  # fmt: skip
        write_lines(self.p.run_dir("wf_a") / "agent-a-k2.jsonl", [assistant(38, "a2", u=usage(inp=10, out=100))])
        self.p.write()

        def compact(since: str) -> list[str]:
            t = metrics.parse_time(since)
            return metrics.build(metrics.collect([self.p.dir], {SID: None}, t, NOW), [], None, t, NOW)[2]

        target = self.root / "w.md"
        self.main(since=SINCE, out=str(target), merge_check=False)
        part = self.section(target.read_text(encoding="utf-8"), "Cost")
        self.assertIn("```text\n" + "\n".join(compact(SINCE)) + "\n```", part, "metrics' own compact lines")
        self.assertIn("1 finished issue-task runs", part)
        self.assertNotIn("stage since", part)
        stage = "2026-10-03T07:00:00Z"
        want = [line for line in compact(stage) if line.startswith(("total API list $", "% of a Max 20x week"))]
        self.assertEqual(len(want), 2)
        self.assertNotEqual(want[0], next(x for x in compact(SINCE) if x.startswith("total API")), "07:30 counts")
        self.main(since=SINCE, out=str(target), merge_check=False, stage_since=stage)
        part = self.section(target.read_text(encoding="utf-8"), "Cost")
        self.assertIn("\n".join(compact(SINCE)) + f"\n\nstage since {stage}:\n" + "\n".join(want) + "\n```", part)
        extra = [lambda record: [f"an extra line since {record['since']}"]]
        with mock.patch.object(wave, "COST_EXTRAS", extra):
            self.main(since=SINCE, out=str(target), merge_check=False)
        part = self.section(target.read_text(encoding="utf-8"), "Cost")
        self.assertIn("\n".join(compact(SINCE)) + f"\nan extra line since {SINCE}\n```", part, "the #314 hook")
        late = "2026-10-03T11:30:00Z"  # nothing of the session after it
        self.main(since=late, out=str(target), merge_check=False)
        part = self.section(target.read_text(encoding="utf-8"), "Cost")
        self.assertIn("None.", part)
        self.assertNotIn("```", part)
        self.p.add(assistant(215, "m-late", u=usage(inp=5, out=5)))  # 11:35: one call in the window
        self.main(since=late, out=str(target), merge_check=False)
        part = self.section(target.read_text(encoding="utf-8"), "Cost")
        self.assertIn("```text\n" + "\n".join(compact(late)) + "\n```", part)

    def test_cd_main_keeps_the_root(self) -> None:
        # A POSIX-flavoured path is how the main checkout reaches housekeeping on Linux; Python 3.11 used to turn it
        # into the drive-relative "D:prime-game".
        for main in (PurePosixPath(MAIN), PureWindowsPath(MAIN), Path(MAIN)):
            self.assertEqual(wave.cd_main(main), "cd D:\\prime-game; ", repr(main))

    def test_housekeeping_filters(self) -> None:
        def wt(name: str, branch: str | None, head: str) -> str:
            path = MAIN if name == "main" else f"{MAIN}/.claude/worktrees/{name}"
            return f"worktree {path}\nHEAD {head}\n" + (f"branch refs/heads/{branch}\n" if branch else "detached\n")

        porcelain = "\n".join([
            wt("main", "main", sha(1)),
            wt("305", "tooling/305-keep-warm", sha(1405)),  # merged into main: ready
            wt("300", "tooling/300-autonomy", sha(7)),  # an open PR: not listed
            wt("278", "tooling/278-wave", sha(1378)),  # merged, but a run of this session works there
            wt("250", "core/250-items", sha(1350)),  # merged into release/m5, which is not on main yet
            wt("251", "core/251-x", sha(1351)),  # merged into release/m4, which merged into main later: ready
            wt("260", "tooling/260-x", sha(1360)),  # merged; a live Claude session sits there
            wt("262", "tooling/262-x", sha(9)),  # merged, but its HEAD moved on since
            wt("264", "tooling/264-child", sha(1364)),  # merged into its parent, which merged into main: ready
            wt("266", "tooling/266-child", sha(1366)),  # merged into a parent that is still open
            wt("release-m4", "release/m4", sha(1340)),  # the manager's release worktree, its PR merged: ready
            wt("playtest-m4", None, sha(8)),  # detached, not a task's: not listed
        ])  # fmt: skip
        merged = [
            merged_pr(405, "tooling/305-keep-warm", at(60)),
            merged_pr(378, "tooling/278-wave", at(70)),
            merged_pr(350, "core/250-items", at(30), base="release/m5"),
            merged_pr(351, "core/251-x", at(20), base="release/m4"),
            merged_pr(340, "release/m4", at(100)),
            merged_pr(360, "tooling/260-x", at(65)),
            merged_pr(362, "tooling/262-x", at(66)),
            merged_pr(364, "tooling/264-child", at(40), base="tooling/265-parent"),
            merged_pr(365, "tooling/265-parent", at(80)),
            merged_pr(366, "tooling/266-child", at(50), base="tooling/267-parent"),
        ]
        self.p.launch(0, "t1", "wf_x", issue_args(278))
        journal(self.p.run_dir("wf_x"), [("k1", "implement:#278", "Implement", None)])
        solo = sessions.Session(4242, "s-260", f"{MAIN}/.claude/worktrees/260", "idle", NOW - 600, "solo")
        src = FakeSources(merged=merged, porcelain=porcelain, alive={"260": [solo]}, open_issues=[305, 250, 251, 264, 9])
        target = self.root / "w.md"
        self.main(since=SINCE, out=str(target), sources=src, merge_check=False)
        part = self.section(target.read_text(encoding="utf-8"), "Housekeeping")

        def block(command: str) -> str:
            return f"```powershell\ncd D:\\prime-game; {command}\n```"

        lines = part.splitlines()
        self.assertEqual(lines[2], "For you: close the Claude session in worktree 260 ('solo' (pid 4242, idle, last "
                         "update 10 min ago)), then run its block below; run the blocks under Ready to remove "
                         "(worktrees 305, 251, 264 and release-m4).")  # fmt: skip
        for n in (251, 264, 305, 260):
            self.assertIn(block(f"tools\\run.cmd worktree-done {n}"), part)
        self.assertEqual(part.count("```powershell"), 6, "four worktree-done blocks and the release worktree's two")
        self.assertIn(block("git worktree remove .claude/worktrees/release-m4"), part)
        self.assertIn(block("git branch -D release/m4"), part)
        self.assertLess(part.index("worktree-done 305"), part.index("Held by a live Claude session"))
        self.assertGreater(part.index("worktree-done 260"), part.index("Held by a live Claude session"))
        for n in (250, 262, 266, 278, 300):
            self.assertNotIn(f"worktree-done {n}", part)
        notes = [line for line in lines if line.startswith("- worktree ")]
        self.assertIn("- worktree 250: PR #350 merged into release/m5; after release/m5 reaches main.", notes)
        self.assertIn("- worktree 266: PR #366 merged into tooling/267-parent; after tooling/267-parent reaches main.",
                      notes)  # fmt: skip
        self.assertIn("- worktree 278: run wf_x still running there.", notes)
        self.assertIn(f"- worktree 262: HEAD {sha(9)[:10]} is not PR #362's merged head {sha(1362)[:10]}: check "
                      "before removing.", notes)  # fmt: skip
        self.assertNotIn("300", "\n".join(notes))
        self.assertNotIn("playtest", part)
        self.assertIn(f"Issues still open whose PR reached main since {SINCE} (close each once its acceptance criteria "
                      "are met): #251 (PR #351 via release/m4), #264 (PR #364 via tooling/265-parent), #305 (PR #405).",
                      part)  # fmt: skip
        self.assertIn(("issue", "list", "--state", "open", "--limit", "1000", "--json", "number"), src.gh_calls)
        self.main(since=SINCE, out=str(target), sources=FakeSources(porcelain=wt("main", "main", sha(1))),
                  merge_check=False)  # fmt: skip
        self.assertEqual(self.section(target.read_text(encoding="utf-8"), "Housekeeping"),
                         "## Housekeeping\n\nFor you: nothing.\n\nNone.\n")  # fmt: skip
        only_ready = FakeSources(merged=merged, porcelain="\n".join([wt("main", "main", sha(1)),
                                                                     wt("305", "tooling/305-keep-warm", sha(1405))]))
        self.main(since=SINCE, out=str(target), sources=only_ready, merge_check=False)
        self.assertEqual(self.section(target.read_text(encoding="utf-8"), "Housekeeping").splitlines()[2],
                         "For you: run the blocks under Ready to remove (worktree 305).",
                         "ready blocks are the human's until the manager runs them itself")  # fmt: skip
        failing = FakeSources(merged=merged, fail={"worktrees": Failure("git worktree list failed: no git")})
        self.main(since=SINCE, out=str(target), sources=failing, merge_check=False)
        self.assertIn("Unavailable: git worktree list failed: no git",
                      self.section(target.read_text(encoding="utf-8"), "Housekeeping"))  # fmt: skip
        no_gh = FakeSources(porcelain=porcelain, fail={"merged": Failure("gh: HTTP 502")})
        self.main(since=SINCE, out=str(target), sources=no_gh, merge_check=False)
        self.assertIn("Unavailable: merged PRs: gh: HTTP 502",
                      self.section(target.read_text(encoding="utf-8"), "Housekeeping"))  # fmt: skip

    HEADINGS = ["## Merged into main since", "## Finished runs since", "## Running", "## Open PRs", "## Merge safety",
                "## Cost", "## Housekeeping", "## Handover data", "\n---\n"]  # fmt: skip

    def assert_order(self, body: str, needles: list[str]) -> None:
        places = [body.find(x) for x in needles]
        self.assertNotIn(-1, places, dict(zip(needles, places)))
        self.assertEqual(places, sorted(places), dict(zip(needles, places)))

    def test_section_order(self) -> None:
        self.p.launch(10, "t1", "wf_done", issue_args(9), notice="completed")
        journal(self.p.run_dir("wf_done"), [("k1", "publish:#9", "Publish", PUBLISHED)])
        self.p.launch(20, "t2", "wf_open", issue_args(6))
        journal(self.p.run_dir("wf_open"), [("k2", "implement:#6", "Implement", None)])
        notes = self.root / "notes.md"
        notes.write_text("The manager's own notes.\n", encoding="utf-8")
        porcelain = f"worktree {MAIN}/.claude/worktrees/9\nHEAD {sha(1409)}\nbranch refs/heads/tooling/9-task\n"
        src = FakeSources(merged=[merged_pr(409, "tooling/9-task", at(30))], porcelain=porcelain,
                          open_prs=[open_pr(410, "tooling/6-task")], check_out=CLEAN_CHECK)  # fmt: skip
        target = self.root / "w.md"
        rc, out, _ = self.main(since=SINCE, out=str(target), sources=src, title="Wave 3", notes=str(notes))
        body = target.read_text(encoding="utf-8")
        self.assertEqual(rc, 0)
        self.assert_order(body, ["# Wave 3", "The manager's own notes.", *self.HEADINGS])
        self.assertTrue(body.split("\n---\n")[-1].lstrip().startswith(f"Session {SID}"), "the footer is last")
        for missing in ("Not read.", "Unavailable", "None."):
            self.assertNotIn(missing, body)
        self.assertIn("worktree-done 9", self.section(body, "Housekeeping"))
        self.assertIn(f"wave: 1 finished since {SINCE}, 1 running, 0 finished before; wrote {target} in ", out)
        empty = FakeSources(check_out="merge-check\n  ok    fetched origin\n  ok    no open PRs to check into main")
        self.p.lines = self.p.lines[:1]
        self.main(since=SINCE, out=str(target), sources=empty)
        body = target.read_text(encoding="utf-8")
        self.assert_order(body, ["# Wave report since", *self.HEADINGS])
        for heading in ("Merged into main since", "Finished runs since", "Running", "Open PRs", "Cost", "Housekeeping"):
            self.assertIn("None.", self.section(body, heading), heading)
        self.assertIn("no open PRs to check into main", self.section(body, "Merge safety"))
        bare = self.p.body()  # a Wave built without the sources: each of their sections says so
        self.assert_order(bare, self.HEADINGS)
        for heading in ("Merged into main since", "Open PRs", "Merge safety", "Cost", "Housekeeping"):
            self.assertIn("Not read.", self.section(bare, heading), heading)

    def test_split_over_limit(self) -> None:
        big = ["x" * 25000, "y" * 25000, "z" * 25000]
        for i, notes in enumerate(big):
            self.p.launch(i, f"t{i}", f"wf_{i}", issue_args(i + 1, notes=notes))
            journal(self.p.run_dir(f"wf_{i}"), [(f"k{i}", f"implement:#{i + 1}", "Implement", None)])
        target = self.root / "w.md"
        _, out, _ = self.main(since=SINCE, out=str(target), merge_check=False)
        first = target.read_text(encoding="utf-8")
        parts = [self.root / "w-2.md", self.root / "w-3.md"]
        self.assertLess(len(first), wave.SPLIT_LIMIT)
        self.assert_order(first, self.HEADINGS)
        self.assertIn("Moved to the next 2 comments (w-2.md, w-3.md): the args of 3 runs", first)
        for notes in big:
            self.assertNotIn(notes, first)
        texts = [p.read_text(encoding="utf-8") for p in parts]
        self.assertTrue(texts[0].startswith(f"## Handover data, part 2 of 3 (session {SID} "), texts[0][:100])
        self.assertTrue(texts[1].startswith(f"## Handover data, part 3 of 3 (session {SID} "), texts[1][:100])
        for t in texts:
            self.assertLessEqual(len(t), wave.SPLIT_LIMIT)
        blocks = [json.loads(b.split("\n```")[0]) for t in texts for b in t.split("```json\n")[1:]]
        self.assertEqual(blocks, [issue_args(i + 1, notes=n) for i, n in enumerate(big)])
        for p in [target, *parts]:
            self.assertIn(str(p), out)
        self.assertNotIn("warn", out)
        self.p.launch(9, "t9", "wf_9", issue_args(9, notes="w" * 70000))
        journal(self.p.run_dir("wf_9"), [("k9", "implement:#9", "Implement", None)])
        _, out, _ = self.main(since=SINCE, out=str(target), merge_check=False)
        parts.append(self.root / "w-4.md")
        alone = parts[-1].read_text(encoding="utf-8")
        self.assertIn('"' + "w" * 70000 + '"', alone, "the 70,000 characters in w-4.md")
        self.assertEqual(alone.count("```json"), 1, "alone in w-4.md")
        self.assertIn("warn  w-4.md has 70", out)
        self.assertIn("over GitHub's comment limit of 65536", out, "one run's args alone are too long to post")
        self.p.lines = self.p.lines[:1]
        _, out, _ = self.main(since=SINCE, out=str(target), merge_check=False)
        self.assertIn("No run is running.", target.read_text(encoding="utf-8"))
        self.assertTrue(all(p.exists() for p in parts), "an earlier part is never deleted")
        for p in parts:
            self.assertIn(f"warn  {p} is from an earlier run of wave, not part of this body", out)
        self.assertNotIn("w-5.md", out)

    def test_notes_and_title(self) -> None:
        notes = self.root / "notes.md"
        text = "Decisions:\r\n1. Кирилиця «лапки» stays.\r\n\r\nOrder from here: #279 then #204.\r\n"
        notes.write_bytes(b"\xef\xbb\xbf" + text.encode("utf-8"))
        target = self.root / "w.md"
        self.main(since=SINCE, out=str(target), title="Wave 3: a cheaper manager", plan=302, notes=str(notes),
                  merge_check=False)  # fmt: skip
        body = target.read_text(encoding="utf-8")
        head = body.split("\n## ")[0]
        self.assertTrue(head.startswith("# Wave 3: a cheaper manager\n\n"), head)
        self.assertIn("Plan #302; base main; since 2026-10-03T08:00:00Z", head)
        self.assertIn("\n\nDecisions:\n1. Кирилиця «лапки» stays.\n\nOrder from here: #279 then #204.\n", head)
        self.assertNotIn("﻿", body)
        self.assertNotIn(b"\r", target.read_bytes())
        self.main(since=SINCE, out=str(target), merge_check=False)
        body = target.read_text(encoding="utf-8")
        self.assertTrue(body.startswith("# Wave report since 2026-10-03T08:00:00Z\n"), body[:80])
        self.assertNotIn("Plan #", body.split("\n## ")[0])
        with self.assertRaises(Failure) as caught:
            self.main(since=SINCE, out=str(target), notes=str(self.root / "missing.md"))
        self.assertIn("missing.md", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
