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
from pathlib import Path
from unittest import mock

from runner import cli, metrics, wave
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
    return (f"<task-notification>\n<task-id>{task_id}</task-id>\n<tool-use-id>{tool_id}</tool-use-id>\n"
            f"<output-file>C:\\tmp\\{task_id}.output</output-file>\n<status>{status}</status>\n"
            f"<summary>{summary or 'Dynamic workflow \"issue-task\" ' + status}</summary>\n<result>{result}</result>\n"
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


class WaveTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.p = Project(self.root)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def main(self, **kw: object) -> tuple[int, str, str]:
        self.p.write()
        out, err = io.StringIO(), io.StringIO()
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
        self.assertIn("resumed as wf_r2", self.row(self.p.body(), "wf_r "))
        _, out, err = self.main(args_issue=7)
        self.assertEqual(json.loads(out), issue_args(7))
        self.assertIn("run wf_r2", err)

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
        self.assertEqual(cli.build_parser().parse_args(["wave", "--args", "231"]).args, 231)
        for bad in (["wave", "--since", "x", "--args", "1"], ["wave"]):
            with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
                cli.build_parser().parse_args(bad)


if __name__ == "__main__":
    unittest.main()
